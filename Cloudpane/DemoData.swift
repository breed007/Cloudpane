#if DEBUG
import AppKit
import CloudpaneCore
import Darwin
import Foundation

/// Demo data for screenshots. Debug builds only: this whole file is compiled out
/// of Release, so the shipping app has no demo mode and no launch argument that turns one on.
///
/// Launched with -CloudpaneDemo, the app uses a made-up home folder, database and defaults
/// suite in its temporary folder, rebuilt on every demo launch, and every path and account on
/// screen is invented. The real inventory and folder grants are not read or changed, and open
/// panels are turned off so they cannot save a last folder to the real defaults. The isolation
/// is not complete: AppKit still saves the window frame and sidebar width in the app's real
/// defaults domain, since those go through the standard domain whatever the model uses.
/// docs/screenshots.md explains how to use it.
enum DemoData {
    static let argument = "-CloudpaneDemo"
    static let defaultsSuite = "com.404tools.cloudpane.demo"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    /// Screenshot helpers, demo only: `-CloudpaneDemoSize 860x612` sizes the window, and
    /// `-CloudpaneDemoAddProvider` opens the Add provider sheet in Providers.
    static var opensAddProvider: Bool {
        isRequested && ProcessInfo.processInfo.arguments.contains("-CloudpaneDemoAddProvider")
    }

    /// `-CloudpaneDemoHelp <topic>` opens the Help window at a topic, and
    /// `-CloudpaneDemoHelpSearch <words>` types a search there.
    static var helpTopic: String? { value(after: "-CloudpaneDemoHelp") }
    static var helpSearch: String? { value(after: "-CloudpaneDemoHelpSearch") }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isRequested, let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The sheet's tab, from `-CloudpaneDemoAddProvider <supported|planOnly|nameFolder>`.
    static var addProviderTab: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard opensAddProvider, let index = arguments.firstIndex(of: "-CloudpaneDemoAddProvider"),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The real domain's window and split-view frames as they were when the demo started.
    @MainActor private static var savedWindowState: [String: Any]?

    /// AppKit saves the window frame and the sidebar's split-view frames in the app's
    /// standard defaults domain, which is the real one even in demo mode. Turning off the
    /// window's autosave name keeps its frame out of it. SwiftUI still saves the split view's
    /// frames, so the demo puts the real values back when it quits normally. A demo stopped
    /// with kill skips that; docs/screenshots.md says how to restore.
    @MainActor
    static func keepWindowStateOutOfRealDefaults() {
        guard isRequested else { return }
        if savedWindowState == nil {
            savedWindowState = UserDefaults.standard.dictionaryRepresentation()
                .filter { $0.key.hasPrefix("NSWindow Frame") || $0.key.hasPrefix("NSSplitView Subview Frames") }
        }
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.setFrameAutosaveName("")
            var pending: [NSView] = window.contentView.map { [$0] } ?? []
            while let view = pending.popLast() {
                if let split = view as? NSSplitView { split.autosaveName = nil }
                pending.append(contentsOf: view.subviews)
            }
        }
    }

    /// Puts the real domain's window and split-view frames back as they were.
    @MainActor
    static func restoreRealWindowState() {
        guard isRequested, let saved = savedWindowState else { return }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("NSWindow Frame") || key.hasPrefix("NSSplitView Subview Frames") {
            if let value = saved[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        for (key, value) in saved { defaults.set(value, forKey: key) }
        defaults.synchronize()
    }

    @MainActor
    static func applyWindowSize() {
        let arguments = ProcessInfo.processInfo.arguments
        guard isRequested, let index = arguments.firstIndex(of: "-CloudpaneDemoSize"), index + 1 < arguments.count
        else { return }
        let parts = arguments[index + 1].split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }),
              let screen = window.screen ?? NSScreen.main else { return }
        let frame = NSRect(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 40 - parts[1],
                           width: parts[0], height: parts[1])
        window.setFrame(frame, display: true)
    }

    static var base: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CloudpaneDemo", isDirectory: true)
    }

    static var home: String { base.appendingPathComponent("home").path }
    static var database: String { base.appendingPathComponent("inventory.sqlite").path }

    /// The model for a demo launch, or nil for a normal one.
    @MainActor
    static func modelIfRequested() -> AppModel? {
        guard isRequested, let defaults = UserDefaults(suiteName: defaultsSuite) else { return nil }
        defaults.removePersistentDomain(forName: defaultsSuite)
        defaults.set(true, forKey: AppModel.onboardingKey)
        defaults.set(true, forKey: AppModel.scanOnLaunchKey)
        defaults.set(false, forKey: AppModel.watchKey)
        try? FileManager.default.removeItem(at: base)
        FolderAccess.panelsDisabled = true
        return AppModel(defaults: defaults, homePath: home, databasePath: database)
    }

    /// Builds the made-up folders, records an earlier scan so History has two points, and
    /// enters plans and a backup location. Runs before the model starts.
    static func prepare() async {
        guard isRequested else { return }
        do {
            try buildTree()
            let inventory = try Inventory(path: database)
            let catalog = ProviderCatalog(home: URL(fileURLWithPath: home)).detect()
            _ = try await inventory.recordScan(Scanner(roots: catalog.scanRoots()), homePath: home)
            try addLaterFiles()
            for plan in plans { try await inventory.save(plan) }
            // A plan with no folder, a named folder, and an excluded account, so Providers
            // shows each.
            let vault = try await inventory.save(CustomProvider(name: "Photo vault"))
            try await inventory.save(Subscription(provider: vault.providerID, name: "Vault 5 TB",
                                                  price: Decimal(string: "7.99")!, currency: "USD",
                                                  planBytes: 5_000_000_000_000))
            try await inventory.save(CustomProvider(name: "SyncSpace", folderName: "SyncSpace-Home"))
            try await inventory.setExcluded(true, rootPath: home + "/" + oneDriveWork)
            let backup = URL(fileURLWithPath: base.appendingPathComponent("Backups/Studio NAS").path, isDirectory: true)
            if let bookmark = try? await FolderAccess.bookmark(for: backup) {
                try await inventory.save(BackupLocation(path: backup.path, label: "Studio NAS", kind: .nasShare,
                                                        isOffsite: false, bookmark: bookmark))
            }
        } catch {
            NSLog("Demo data could not be prepared: %@", String(describing: error))
        }
    }

    private static let plans: [Subscription] = [
        Subscription(provider: "icloud-drive", name: "iCloud+ 200 GB", price: Decimal(string: "2.99")!, currency: "USD",
                     planBytes: 200_000_000_000),
        Subscription(provider: "dropbox", name: "Plus", price: Decimal(string: "11.99")!, currency: "USD",
                     planBytes: 2_000_000_000_000),
        Subscription(provider: "google-drive", name: "Google One 100 GB", price: Decimal(string: "1.99")!, currency: "USD",
                     planBytes: 100_000_000_000),
        Subscription(provider: "onedrive", name: "Microsoft 365 Personal", price: Decimal(string: "9.99")!, currency: "USD",
                     planBytes: 1_000_000_000_000, bundle: .microsoft365),
    ]

    private static let cloudStorage = "Library/CloudStorage"
    private static let iCloud = "Library/Mobile Documents/com~apple~CloudDocs"
    private static let dropbox = cloudStorage + "/Dropbox"
    private static let google = cloudStorage + "/GoogleDrive-you@example.com/My Drive"
    private static let oneDrive = cloudStorage + "/OneDrive-Personal"
    /// A second account, so Providers shows two accounts sharing one plan.
    private static let oneDriveWork = cloudStorage + "/OneDrive-Northwind"
    private static let box = cloudStorage + "/Box-Box"

    private static func buildTree() throws {
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/" + cloudStorage + "/GoogleDrive-you@example.com/Shared drives",
                                                withIntermediateDirectories: true)
        // Placeholders: logical size only. Local: a few real bytes stand for a downloaded file.
        let placeholders: [(String, Int64)] = [
            (iCloud + "/Documents/Taxes/2025 return.pdf", 2_400_000),
            (iCloud + "/Documents/Taxes/2024 return.pdf", 2_100_000),
            (iCloud + "/Desktop/Projects/Kitchen remodel.key", 184_000_000),
            (iCloud + "/Documents/Scans/Passport.pdf", 3_800_000),
            (dropbox + "/Photos/2023 Lisbon/IMG_2041.heic", 4_200_000),
            (dropbox + "/Photos/2023 Lisbon/IMG_2042.heic", 4_100_000),
            (dropbox + "/Photos/2023 Lisbon/Harbor walk.mov", 1_250_000_000),
            (dropbox + "/Archive/Studio backups 2022.zip", 38_000_000_000),
            (dropbox + "/Clients/Northwind/Brand guide.pdf", 26_000_000),
            (dropbox + "/Clients/Northwind/Logo final.ai", 88_000_000),
            (google + "/School/Thesis draft.docx", 1_900_000),
            (google + "/School/Lecture recordings/Week 3.mp4", 2_600_000_000),
            (google + "/Recipes/Bread.pdf", 640_000),
            (oneDrive + "/Documents/Budget 2026.xlsx", 410_000),
            (oneDrive + "/Pictures/Camera Roll/IMG_2041.heic", 4_200_000),
            (oneDrive + "/Videos/Harbor walk.mov", 1_250_000_000),
            (oneDriveWork + "/Shared/Quarterly review.pptx", 48_000_000),
            (oneDriveWork + "/Shared/Roadmap.docx", 2_300_000),
            // A folder that matches no provider, listed under "Other cloud folders".
            (cloudStorage + "/SyncSpace-Home/Notes/Garden plan.pdf", 6_400_000),
            // One left unnamed, so Add provider has a folder to offer.
            (cloudStorage + "/MediaShare-Home/Clips/Recital.mov", 310_000_000),
            (box + "/Contracts/Northwind MSA.pdf", 1_100_000),
            (box + "/Contracts/Brand guide.pdf", 26_000_000),
        ]
        for (path, size) in placeholders { try sparse(home + "/" + path, size) }
        let local: [String] = [
            iCloud + "/Documents/Notes/Packing list.txt",
            dropbox + "/Clients/Northwind/Invoice 1042.pdf",
            google + "/Recipes/Focaccia.txt",
            "../Backups/Studio NAS/Clients/Northwind/Invoice 1042.pdf",
        ]
        for path in local { try real(home + "/" + path) }
        try FileManager.default.createDirectory(atPath: base.appendingPathComponent("Backups/Studio NAS").path,
                                                withIntermediateDirectories: true)
    }

    private static func addLaterFiles() throws {
        try sparse(home + "/" + dropbox + "/Photos/2024 Kyoto/Temple.mov", 2_900_000_000)
        try sparse(home + "/" + iCloud + "/Documents/Scans/Lease.pdf", 5_200_000)
    }

    private static func sparse(_ path: String, _ size: Int64) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: path, contents: nil), truncate(path, off_t(size)) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
        }
    }

    private static func real(_ path: String) throws {
        let standardized = (path as NSString).standardizingPath
        try FileManager.default.createDirectory(atPath: (standardized as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: standardized, contents: Data(repeating: 0x2A, count: 48_000)) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: standardized])
        }
    }
}
#endif
