import CloudpaneCore
import Foundation
import os

/// Duplicates, opt-in hashing, the change watcher and snapshot history.
extension AppModel {
    // MARK: - Watcher

    var watchEnabled: Bool { defaults.bool(forKey: AppModel.watchKey) }

    /// The folders to watch: the two granted folders and connected backup locations. Each
    /// is watched only while its security-scoped access is active.
    var watchPaths: [String] {
        var paths = GrantedFolder.allCases.compactMap { access.granted[$0]?.path }
        paths += backupAccess.values.map(\.path)
        return paths
    }

    /// Starts, restarts or stops the watcher to match the setting and the grants.
    func updateWatching() {
        stopWatching()
        guard onboardingComplete, watchEnabled, inventory != nil, !watchPaths.isEmpty else { return }
        let watcher = FileWatcher(paths: watchPaths, excluding: scanChoices.excludedRoots)
        self.watcher = watcher
        isWatching = true
        let events = watcher.start()
        watchTask = Task { [self] in
            for await event in events {
                switch event {
                case .changed(let paths): applyChanges(paths)
                case .rescanNeeded: requestFullRescan()
                }
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        watcher?.stop()
        watcher = nil
        isWatching = false
    }

    private func requestFullRescan() {
        if isScanning || isUpdating {
            pendingFullRescan = true
        } else {
            scan()
        }
    }

    /// Records the changes as an incremental snapshot, or queues them while a scan or an
    /// update is running. Changes that cannot be applied piecemeal start a full scan.
    func applyChanges(_ paths: Set<String>) {
        pendingChanges.formUnion(paths)
        guard !isScanning, !isUpdating, let inventory, let report else { return }
        let changed = pendingChanges
        pendingChanges = []
        let rootList = report.scanRoots(includeUnrecognized: true, backups: connectedBackupRoots, choices: scanChoices)
        // A different set of roots than the last scan saw needs a full scan.
        guard Set(rootList.map(\.id)) == Set(roots.map(\.root.id)) else {
            scan()
            return
        }
        let parents = [access.granted[.cloudStorage]?.path].compactMap { $0 }
        let excluded = scanChoices.excludedRoots
        isUpdating = true
        Task { [self] in
            defer {
                isUpdating = false
                afterUpdate()
            }
            do {
                let scanner = IncrementalScanner(roots: rootList, changedPaths: changed, rootParents: parents,
                                                 excluding: excluded)
                switch try await inventory.recordIncremental(scanner, homePath: report.homePath) {
                case .recorded(let id):
                    await show(snapshotID: id)
                case .needsFullRescan:
                    pendingFullRescan = true
                }
            } catch {
                Logger(subsystem: "com.404tools.cloudpane", category: "watch")
                    .error("Incremental update failed: \(String(describing: error), privacy: .public)")
                pendingFullRescan = true
            }
        }
    }

    /// Runs whatever arrived while a scan or an update was busy.
    func afterUpdate() {
        guard !isScanning, !isUpdating else { return }
        if pendingFullRescan {
            pendingFullRescan = false
            pendingChanges = []
            scan()
        } else if !pendingChanges.isEmpty {
            applyChanges([])
        } else {
            hashLocalFilesInOptedInFolders()
        }
    }

    // MARK: - Duplicates

    func refreshDuplicates() {
        guard let inventory else { return }
        isFindingDuplicates = true
        Task { [self] in
            do {
                let result = try await duplicateRuns.run { () async throws -> DuplicateReport? in
                    guard let latest = try await inventory.snapshots().last(where: { $0.status == .complete }) else {
                        return nil
                    }
                    return try await inventory.duplicates(snapshotID: latest.id)
                }
                guard let outcome = result else { return }
                duplicates = outcome
                isFindingDuplicates = false
            } catch {
                isFindingDuplicates = false
                errorMessage = "Cloudpane could not look for duplicates. \(error)"
            }
        }
    }

    // MARK: - Hashing

    func refreshHashFolders() async {
        hashFolders = (try? await inventory?.hashFolders()) ?? []
    }

    func hashPlan(for folder: HashFolder) async -> HashPlan? {
        try? await inventory?.hashPlan(for: [folder])
    }

    /// Hashes exactly the plan the user confirmed in the sheet. Only the cloud-only files in
    /// that plan may download; anything that appeared since waits for the next confirmation,
    /// and a file evicted since is skipped rather than downloaded. Opts the folder in, so
    /// later changes to files already on this Mac are hashed automatically.
    func startHashing(_ folder: HashFolder, confirmed plan: HashPlan) {
        guard let inventory, !isHashing else { return }
        isHashing = true
        hashMessage = nil
        hashProgress = nil
        hashTask = Task { [self] in
            do {
                try await inventory.setHashing(folder, enabled: true)
                await refreshHashFolders()
                let summary = try await inventory.recordHashing(FileHasher(items: plan.items)) { [self] event in
                    if case .progress(let value) = event { Task { @MainActor in self.hashProgress = value } }
                }
                hashMessage = summary.map(describe) ?? "Hashing stopped."
            } catch {
                hashMessage = "Hashing stopped with an error. \(error)"
            }
            isHashing = false
            hashTask = nil
            refreshDuplicates()
            regrade()
        }
    }

    func stopHashing() {
        hashTask?.cancel()
    }

    func stopHashingFolder(_ folder: HashFolder) async {
        try? await inventory?.setHashing(folder, enabled: false)
        await refreshHashFolders()
    }

    /// After an update, files already on this Mac in opted-in folders are hashed without
    /// asking: nothing downloads. Files only in the cloud wait for the user to hash the
    /// folder again, with the confirmation that says how much will download.
    func hashLocalFilesInOptedInFolders() {
        guard let inventory, !isHashing, !hashFolders.isEmpty else { return }
        let folders = hashFolders
        Task { [self] in
            guard let plan = try? await inventory.hashPlan(for: folders) else { return }
            let local = plan.items.filter { !$0.isPlaceholder }
            guard !local.isEmpty, !isHashing else { return }
            isHashing = true
            // Downloads off on the worker thread: a file evicted since the scan fails to read
            // instead of downloading.
            _ = try? await inventory.recordHashing(FileHasher(items: local, allowsDownloads: false)) { [self] event in
                if case .progress(let value) = event { Task { @MainActor in self.hashProgress = value } }
            }
            isHashing = false
            refreshDuplicates()
            regrade()
        }
    }

    private func describe(_ summary: HashSummary) -> String {
        var parts = ["Hashed \(Format.count(summary.hashed)) \(summary.hashed == 1 ? "file" : "files")."]
        if summary.skipped > 0 { parts.append(summary.skipped == 1 ? "1 changed while being read and was skipped." : "\(Format.count(summary.skipped)) changed while being read and were skipped.") }
        if summary.needsConfirmation > 0 {
            parts.append(summary.needsConfirmation == 1
                ? "1 is only in the cloud now and was skipped; choose Hash this folder again to confirm downloading it."
                : "\(Format.count(summary.needsConfirmation)) are only in the cloud now and were skipped; choose Hash this folder again to confirm downloading them.")
        }
        if summary.failed > 0 { parts.append("\(Format.count(summary.failed)) could not be read.") }
        if summary.wasCanceled { parts.append("Stopped before the end; what was hashed is kept.") }
        return parts.joined(separator: " ")
    }

    // MARK: - History

    func refreshHistory() async {
        guard let inventory else { return }
        history = (try? await inventory.totalsHistory()) ?? []
        snapshotList = ((try? await inventory.snapshots()) ?? []).filter { $0.status == .complete }
    }

    func diff(from old: Int64, to new: Int64) async -> SnapshotDiff? {
        try? await inventory?.diff(from: old, to: new, limit: 300)
    }
}
