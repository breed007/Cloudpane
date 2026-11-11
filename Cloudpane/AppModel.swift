import CloudpaneCore
import Foundation
import Observation
import os

/// One row of the provider list: the catalog's status joined with the snapshot's totals.
struct ProviderRow: Identifiable, Sendable {
    let id: String
    let name: String
    let state: RootState
    /// Shown under the name when the provider is not simply installed.
    let reason: String?
    let accounts: Int
    let files: Int
    let logicalBytes: Int64
    let cloudOnlyBytes: Int64
    /// Accounts the user excluded from scans; not counted in accounts.
    var excludedAccounts = 0
    /// Every account of the provider is excluded from scans.
    var isExcluded = false
    /// A plan the user added with no folder on this Mac.
    var isCostOnly = false
    var localBytes: Int64 { logicalBytes - cloudOnlyBytes }
    var hasData: Bool { files > 0 }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case json
    case csv
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

struct ExportResult: Sendable {
    let url: URL
    let message: String
}

@MainActor
@Observable
final class AppModel {
    static let scanOnLaunchKey = "scanOnLaunch"
    static let onboardingKey = "onboardingComplete"
    static let unrecognizedName = ScanRoot.unrecognizedProviderName

    let access: FolderAccess
    private(set) var inventory: Inventory?
    private(set) var startupError: String?
    private(set) var onboardingComplete: Bool
    private(set) var report: CatalogReport?
    private(set) var snapshot: Snapshot?
    private(set) var roots: [RootSummary] = []
    private(set) var totals: [ProviderTotal] = []
    private(set) var types: [TypeTotal] = []
    private(set) var progress: ScanProgress?
    private(set) var isScanning = false
    var lastExport: ExportResult?
    var errorMessage: String?

    // Subscriptions, grade and backup locations (AppModel+M3.swift).
    var subscriptions: [Subscription] = []
    var planReport: PlanReport?
    var grade: GradeReport?
    var gradeNote: String?
    /// A grade is being computed; the view keeps showing the last one meanwhile.
    var isRegrading = false
    /// Only the newest grade is ever published; starting one cancels the one before.
    /// The value is nil when there is no complete scan to grade.
    let gradeRuns = LatestOnly<GradeReport?>()

    // Duplicates, hashing, the watcher and history (AppModel+M4.swift).
    static let watchKey = "watchForChanges"
    var duplicates: DuplicateReport?
    var isFindingDuplicates = false
    let duplicateRuns = LatestOnly<DuplicateReport?>()
    var hashFolders: [HashFolder] = []
    var hashProgress: HashProgress?
    var isHashing = false
    var hashMessage: String?
    var hashTask: Task<Void, Never>?
    var history: [HistoryPoint] = []
    var snapshotList: [Snapshot] = []
    var watcher: FileWatcher?
    var watchTask: Task<Void, Never>?
    var isWatching = false
    var isUpdating = false
    var pendingChanges: Set<String> = []
    var pendingFullRescan = false
    var backupLocations: [BackupLocation] = []
    /// Backup locations whose bookmark did not resolve, usually a disk that is not connected.
    var disconnectedBackups: Set<Int64> = []
    var backupAccess: [Int64: URL] = [:]
    let priceCatalog: PriceCatalog?
    let providerFacts: ProviderFacts?

    // The Providers view (AppModel+Providers.swift).
    /// Per-account totals of the latest complete scan.
    var latestCompleteRoots: [RootSummary] = []
    /// A provider whose plan editor Providers should open, set from Overview.
    var pendingPlanProvider: String?
    /// Excluded accounts, providers the user added and forgotten accounts.
    var scanChoices = ScanChoices()

    // The iCloud figures and the report (AppModel+M5.swift).
    var iCloudUsage: ICloudUsage?
    var photosLibrary: PhotosLibraryRecord?
    var isMeasuringPhotos = false
    var photosMessage: String?
    var isExportingReport = false

    private var scanTask: Task<Void, Never>?
    private var started = false
    let defaults: UserDefaults
    /// Nil for the app's container; tests pass a database of their own.
    private let databaseOverride: String?
    private let log = Logger(subsystem: "com.404tools.cloudpane", category: "scan")

    init(defaults: UserDefaults = .standard, homePath: String = ProviderCatalog.userHome.path,
         databasePath: String? = nil) {
        self.defaults = defaults
        databaseOverride = databasePath
        defaults.register(defaults: [AppModel.scanOnLaunchKey: true, AppModel.reportHidesPathsKey: true])
        access = FolderAccess(homePath: homePath, defaults: defaults)
        onboardingComplete = defaults.bool(forKey: AppModel.onboardingKey)
        defaults.register(defaults: [AppModel.watchKey: true])
        // Belt and braces: the system default is already off, but never inherit "on".
        // Only the hashing worker turns materialization on, for its own thread.
        MaterializationPolicy.disableForProcess()
        priceCatalog = try? PriceCatalog.bundled()
        providerFacts = try? ProviderFacts.bundled()
    }

    // MARK: - Startup

    /// Runs once per launch: restores folder access, opens the inventory, shows the last
    /// scan, and starts a new one when the user asked for scans on launch.
    func start() async {
        guard !started else { return }
        started = true
        access.restore()
        do {
            inventory = try Inventory(path: try databaseOverride ?? AppModel.databasePath())
        } catch {
            startupError = "Cloudpane could not open its inventory. \(error)"
            return
        }
        refreshCatalog()
        await restoreBackupLocations()
        await refreshScanChoices()
        await refreshPhotosLibrary()
        await refreshHashFolders()
        await loadLatestSnapshot()
        if onboardingComplete && defaults.bool(forKey: AppModel.scanOnLaunchKey) {
            scan()
        }
        updateWatching()
    }

    /// The inventory lives in the app's container: Application Support/Cloudpane.
    private static func databasePath() throws -> String {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Cloudpane", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("inventory.sqlite").path
    }

    func completeOnboarding() {
        onboardingComplete = true
        defaults.set(true, forKey: AppModel.onboardingKey)
        updateWatching()
    }

    /// Forgets both folder grants and returns to onboarding. Past scans stay in the inventory.
    func resetAccess() {
        stopWatching()
        cancelScan()
        access.reset()
        onboardingComplete = false
        defaults.set(false, forKey: AppModel.onboardingKey)
        refreshCatalog()
    }

    /// Measures both folders again and redetects providers, for "Check again".
    func checkFolders() {
        access.refreshPresence()
        refreshCatalog()
        // Grants may have changed; the watcher follows them.
        updateWatching()
    }

    /// Redetects providers. A root is a partial view when the scan on screen could not get
    /// some of its folders' lists from the provider.
    func refreshCatalog() {
        report = ProviderCatalog(home: URL(fileURLWithPath: access.homePath),
                                 partialViewDetector: ScanPartialViewDetector(lastScan: roots)).detect()
    }

    // MARK: - Scanning

    func scan() {
        // One writer at a time: a scan asked for during an incremental update runs after it.
        // A scan asked for while one runs (after excluding an account or naming a folder)
        // runs as soon as the current one ends, so the change is never lost.
        if isUpdating || scanTask != nil {
            pendingFullRescan = true
            return
        }
        guard let inventory else { return }
        refreshCatalog()
        guard let report else { return }
        let scanner = Scanner(roots: report.scanRoots(includeUnrecognized: true, backups: connectedBackupRoots,
                                                      choices: scanChoices))
        isScanning = true
        progress = nil
        errorMessage = nil
        // Strong captures: the model lives as long as the app, and the task ends with the scan.
        scanTask = Task { [self] in
            do {
                let id = try await inventory.recordScan(scanner, homePath: report.homePath) { [self] event in
                    guard case .progress(let value) = event else { return }
                    Task { @MainActor in self.progress = value }
                }
                await finishScan(snapshotID: id)
            } catch {
                failScan(error)
            }
        }
    }

    func cancelScan() {
        // Stopping means stopping: no queued rescan starts after it.
        pendingFullRescan = false
        scanTask?.cancel()
    }

    private func finishScan(snapshotID: Int64) async {
        scanTask = nil
        isScanning = false
        await load(snapshotID: snapshotID)
        afterUpdate()
        log.notice("Scan \(snapshotID, privacy: .public) ended: \(self.snapshot?.status.rawValue ?? "unknown", privacy: .public), \(self.roots.count, privacy: .public) roots")
    }

    private func failScan(_ error: Error) {
        scanTask = nil
        isScanning = false
        errorMessage = "The scan stopped with an error. \(error)"
        log.error("Scan failed: \(String(describing: error), privacy: .public)")
    }

    // MARK: - Loading

    private func loadLatestSnapshot() async {
        guard let inventory, let latest = try? await inventory.snapshots().last else {
            await refreshPlans()
            return
        }
        await load(snapshotID: latest.id)
    }

    private func load(snapshotID: Int64) async {
        guard let inventory else { return }
        do {
            snapshot = try await inventory.snapshot(snapshotID)
            roots = try await inventory.rootSummaries(snapshotID: snapshotID)
            // A canceled or interrupted scan is shown with a banner saying it is partial.
            totals = try await inventory.providerTotals(snapshotID: snapshotID, allowIncomplete: true)
            types = try await inventory.typeBreakdown(snapshotID: snapshotID, allowIncomplete: true)
        } catch {
            errorMessage = "Cloudpane could not read its last scan. \(error)"
        }
        refreshCatalog()
        await refreshPlans()
        regrade()
        refreshDuplicates()
        await refreshHistory()
    }

    /// Loads a snapshot recorded elsewhere in the model, such as an incremental one.
    func show(snapshotID: Int64) async {
        await load(snapshotID: snapshotID)
    }

    // MARK: - Derived

    /// Providers in table order, then other cloud folders when any were scanned. Backup
    /// roots never count toward the cloud footprint.
    var providerRows: [ProviderRow] {
        guard let report else { return [] }
        let byProvider = Dictionary(uniqueKeysWithValues: totals.map { ($0.provider, $0) })
        var rows = report.providers.map { status -> ProviderRow in
            let total = byProvider[status.rule.id]
            let walkable = status.roots.filter(\.isWalkable)
            let excluded = status.roots.filter { scanChoices.isExcluded($0.path) }.count
            return ProviderRow(id: status.rule.id, name: status.rule.displayName, state: status.state,
                               reason: displayReason(status), accounts: status.roots.count - excluded,
                               files: total?.files ?? 0, logicalBytes: total?.logicalBytes ?? 0,
                               cloudOnlyBytes: total?.placeholderBytes ?? 0, excludedAccounts: excluded,
                               isExcluded: !walkable.isEmpty && walkable.allSatisfy { scanChoices.isExcluded($0.path) })
        }
        // Providers the user added: named folders with their scan data, and plans with no
        // folder, which Overview lists so their plan can be edited from here too.
        for custom in scanChoices.customProviders {
            let total = byProvider[custom.providerID]
            let found = custom.folderName.map { name in report.unrecognized.contains { $0.folderName == name } } ?? false
            let path = custom.folderName.flatMap { name in report.unrecognized.first { $0.folderName == name }?.path }
            rows.append(ProviderRow(id: custom.providerID, name: custom.name,
                                    state: custom.isCostOnly || found ? .installed : .missing, reason: nil,
                                    accounts: custom.isCostOnly ? 0 : 1, files: total?.files ?? 0,
                                    logicalBytes: total?.logicalBytes ?? 0, cloudOnlyBytes: total?.placeholderBytes ?? 0,
                                    isExcluded: path.map { scanChoices.isExcluded($0) } ?? false,
                                    isCostOnly: custom.isCostOnly))
        }
        if let other = byProvider[ScanRoot.unrecognizedProvider] {
            rows.append(ProviderRow(id: other.provider, name: AppModel.unrecognizedName, state: .installed,
                                    reason: nil, accounts: other.roots, files: other.files,
                                    logicalBytes: other.logicalBytes, cloudOnlyBytes: other.placeholderBytes))
        }
        return rows
    }

    var footprintBytes: Int64 {
        totals.filter { $0.provider != ScanRoot.backupProvider }.reduce(0) { $0 + $1.logicalBytes }
    }

    var cloudOnlyBytes: Int64 {
        totals.filter { $0.provider != ScanRoot.backupProvider }.reduce(0) { $0 + $1.placeholderBytes }
    }

    /// The reason to show for a provider, rewritten when the real cause is a missing grant.
    func displayReason(_ status: ProviderStatus) -> String? {
        if status.state == .installed { return nil }
        if status.state == .unavailable,
           let folder = GrantedFolder.allCases.first(where: { $0.covers(status.rule) }),
           !access.isGranted(folder), access.presence(of: folder) == .present {
            return "Cloudpane does not have access to \(folder.displayPath) yet. Grant access in Settings."
        }
        return status.reason
    }

    func providerName(for id: String) -> String {
        if id == ScanRoot.unrecognizedProvider { return AppModel.unrecognizedName }
        if id == ScanRoot.backupProvider { return "Backup" }
        if let custom = scanChoices.customProviders.first(where: { $0.providerID == id }) { return custom.name }
        // A provider the user has since removed still has records in past scans.
        if CustomProvider.isCustom(id) { return totals.first { $0.provider == id }?.providerName ?? "Removed provider" }
        return ProviderRule.defaultTable.first { $0.id == id }?.displayName ?? id
    }

    func accountName(forRoot rootID: String) -> String {
        roots.first { $0.root.id == rootID }?.root.name ?? rootID
    }

    // MARK: - Queries

    func folderTotals(provider: String) async -> [FolderTotal] {
        guard let inventory, let snapshot else { return [] }
        return (try? await inventory.folderTotals(snapshotID: snapshot.id, provider: provider,
                                                   allowIncomplete: true)) ?? []
    }

    func search(_ text: String) async -> [FileRecord] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let inventory, let snapshot, !query.isEmpty else { return [] }
        return (try? await inventory.search(snapshotID: snapshot.id, text: query, in: .name, limit: 1_000)) ?? []
    }

    // MARK: - Export

    /// Writes the current snapshot to ~/Downloads under a name that never replaces an
    /// existing file. Downloads is the only place Cloudpane writes outside its container.
    func export(_ format: ExportFormat) async {
        guard let inventory, let snapshot else { return }
        let downloads = URL(fileURLWithPath: access.homePath + "/Downloads", isDirectory: true)
        let stamp = AppModel.fileStamp(snapshot.startedAt)
        // Core never replaces a file: if a name is taken by the time the export lands,
        // it fails with destinationExists and the next free name is tried.
        for _ in 0..<20 {
            let target = AppModel.unusedURL(in: downloads, base: "Cloudpane scan \(stamp)", ext: format.rawValue)
            do {
                switch format {
                case .json: try await inventory.exportJSON(snapshotID: snapshot.id, to: target)
                case .csv: try await inventory.exportCSV(snapshotID: snapshot.id, to: target)
                }
                lastExport = ExportResult(url: target, message: "Saved \(target.lastPathComponent) to Downloads.")
                return
            } catch ExportError.destinationExists {
                continue
            } catch {
                errorMessage = "Cloudpane could not save the export to Downloads. \(error.localizedDescription)"
                return
            }
        }
        errorMessage = "Cloudpane could not find a free name for the export in Downloads."
    }

    /// Fixed format, whatever the locale: "2026-10-24 at 15.32". Finder shows ":" as "/".
    static func fileStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d at %02d.%02d", parts.year ?? 0, parts.month ?? 0,
                      parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "<base>.ext", or "<base> 2.ext" and up when that name is taken.
    static func unusedURL(in folder: URL, base: String, ext: String) -> URL {
        let safeBase = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        var candidate = folder.appendingPathComponent("\(safeBase).\(ext)")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(safeBase) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}
