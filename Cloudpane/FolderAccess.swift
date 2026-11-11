import AppKit
import CloudpaneCore
import Darwin
import Foundation
import Observation
import os

/// The two folders Cloudpane asks the user to grant. Nothing else under ~/Library is ever
/// requested: the app asks for these two folders by exact path and refuses anything else.
enum GrantedFolder: String, CaseIterable, Identifiable, Sendable {
    case cloudStorage
    case cloudDocs

    var id: String { rawValue }

    /// Relative to the user's home folder.
    var relativePath: String {
        switch self {
        case .cloudStorage: return "Library/CloudStorage"
        case .cloudDocs: return "Library/Mobile Documents/com~apple~CloudDocs"
        }
    }

    var displayPath: String { "~/" + relativePath }

    var title: String {
        switch self {
        case .cloudStorage: return "Cloud storage folder"
        case .cloudDocs: return "\(ProviderRule.iCloudDrive.displayName) folder"
        }
    }

    var purpose: String {
        switch self {
        case .cloudStorage:
            return "Most cloud storage apps keep their synced folders here, one per account."
        case .cloudDocs:
            return "\(ProviderRule.iCloudDrive.displayName) keeps its files here. Finder shows it in the sidebar."
        }
    }

    /// The provider-table parent this grant covers.
    func covers(_ rule: ProviderRule) -> Bool {
        switch self {
        case .cloudStorage: return rule.parent == "Library/CloudStorage"
        case .cloudDocs: return rule.id == ProviderRule.iCloudDrive.id
        }
    }

    fileprivate var defaultsKey: String { "folderAccess.\(rawValue)" }
}

/// Whether a granted folder exists, read with lstat(2). The App Sandbox allows lstat
/// without a grant, so this works before the user has granted anything.
enum FolderPresence: Equatable, Sendable {
    case present
    case absent
    case unknown(String)
}

/// Security-scoped, app-scope bookmarks for the two folders, held open while the app runs.
/// Bookmarks are created read-only, so no grant can ever be used to write.
@MainActor
@Observable
final class FolderAccess {
    let homePath: String
    private(set) var granted: [GrantedFolder: URL] = [:]
    /// Observable, so views update when refreshPresence() finds a folder that appeared.
    private(set) var presences: [GrantedFolder: FolderPresence] = [:]
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.404tools.cloudpane", category: "access")

    init(homePath: String = ProviderCatalog.userHome.path, defaults: UserDefaults = .standard) {
        self.homePath = homePath
        self.defaults = defaults
        refreshPresence()
    }

    func path(of folder: GrantedFolder) -> String { homePath + "/" + folder.relativePath }

    /// The last measured presence. Call refreshPresence() to measure again.
    func presence(of folder: GrantedFolder) -> FolderPresence {
        presences[folder] ?? measurePresence(of: folder)
    }

    /// Checks both folders again, for "Check again" and whenever a folder row appears.
    func refreshPresence() {
        var fresh: [GrantedFolder: FolderPresence] = [:]
        for folder in GrantedFolder.allCases { fresh[folder] = measurePresence(of: folder) }
        if fresh != presences { presences = fresh }
    }

    private func measurePresence(of folder: GrantedFolder) -> FolderPresence {
        var info = stat()
        guard lstat(path(of: folder), &info) == 0 else {
            let code = errno
            if code == ENOENT { return .absent }
            return .unknown(String(cString: strerror(code)))
        }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: return .present
        case S_IFLNK: return .unknown("It is a symbolic link, which Cloudpane does not follow.")
        default: return .unknown("It is not a folder.")
        }
    }

    func isGranted(_ folder: GrantedFolder) -> Bool { granted[folder] != nil }

    /// Resolves saved bookmarks and starts access. A bookmark that no longer resolves to the
    /// expected folder is dropped, and the folder shows as not granted.
    func restore() {
        refreshPresence()
        for folder in GrantedFolder.allCases {
            guard granted[folder] == nil, let data = defaults.data(forKey: folder.defaultsKey) else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  matches(url, folder), url.startAccessingSecurityScopedResource() else {
                defaults.removeObject(forKey: folder.defaultsKey)
                log.notice("Dropped a saved grant that no longer resolves: \(folder.rawValue, privacy: .public)")
                continue
            }
            if stale, let fresh = try? Self.bookmark(for: url) {
                defaults.set(fresh, forKey: folder.defaultsKey)
            }
            granted[folder] = url
        }
        for folder in GrantedFolder.allCases {
            log.notice("""
                Folder \(folder.rawValue, privacy: .public): \(self.describePresence(folder), privacy: .public), \
                \(self.isGranted(folder) ? "granted" : "not granted", privacy: .public)
                """)
        }
    }

    /// Set only by the Debug-only demo mode: an open panel saves its last folder and size in
    /// the app's real defaults, which the demo must not change.
    static var panelsDisabled = false
    static let panelsDisabledMessage = "Open panels are turned off in demo mode."

    /// Shows the open panel at the folder and saves a read-only bookmark if the user picks
    /// exactly that folder. Returns a message for the user when the grant did not happen
    /// for a reason other than canceling.
    func requestGrant(_ folder: GrantedFolder) -> String? {
        if FolderAccess.panelsDisabled { return FolderAccess.panelsDisabledMessage }
        let expected = URL(fileURLWithPath: path(of: folder), isDirectory: true)
        let panel = NSOpenPanel()
        panel.title = "Grant access to the \(folder.title.lowercased())"
        panel.message = "Click Grant access to let Cloudpane read \(folder.displayPath). "
            + "Cloudpane reads names, sizes and dates only. It never changes, moves or downloads a file."
        panel.prompt = "Grant access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = expected
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard matches(url, folder) else {
            return "That is not \(folder.displayPath). Cloudpane needs exactly that folder, "
                + "not one above or inside it."
        }
        do {
            let data = try Self.bookmark(for: url)
            // Start the new grant before letting go of the old one, so a failure here leaves
            // the existing grant, its live access and its bookmark exactly as they were.
            guard url.startAccessingSecurityScopedResource() else {
                return "macOS did not allow access to \(folder.displayPath)."
            }
            let previous = granted[folder]
            defaults.set(data, forKey: folder.defaultsKey)
            granted[folder] = url
            previous?.stopAccessingSecurityScopedResource()
            refreshPresence()
            log.notice("Granted \(folder.rawValue, privacy: .public)")
            return nil
        } catch {
            return "Cloudpane could not save access to \(folder.displayPath): \(error.localizedDescription)"
        }
    }

    /// Stops access and forgets both bookmarks.
    func reset() {
        for (folder, url) in granted {
            url.stopAccessingSecurityScopedResource()
            defaults.removeObject(forKey: folder.defaultsKey)
        }
        for folder in GrantedFolder.allCases { defaults.removeObject(forKey: folder.defaultsKey) }
        granted = [:]
        log.notice("Reset folder access")
    }

    private func describePresence(_ folder: GrantedFolder) -> String {
        switch presence(of: folder) {
        case .present: return "present"
        case .absent: return "absent"
        case .unknown(let why): return "unknown (\(why))"
        }
    }

    /// Asks the user for a backup folder. Any folder can be picked here; the caller checks
    /// it against the synced folders before keeping it.
    static func chooseBackupFolder() -> URL? {
        if panelsDisabled { return nil }
        let panel = NSOpenPanel()
        panel.title = "Add a backup location"
        panel.message = "Choose the folder that holds your backup, such as a Time Machine backup, a folder on an external drive, or a NAS share. For Time Machine, choose the latest backup rather than the whole disk. Cloudpane only reads it."
        panel.prompt = "Add backup location"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Resolves a saved backup bookmark and starts access, and says whether the bookmark
    /// is stale and should be saved again. Nil when it does not resolve, usually because
    /// the disk is not connected.
    static func startAccess(bookmark: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        return (url, stale)
    }

    /// A read-only, app-scope, security-scoped bookmark.
    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                             includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Exact folder only, after resolving symbolic links, compared without regard to case
    /// or Unicode normalization, as the default APFS volume compares names.
    private func matches(_ url: URL, _ folder: GrantedFolder) -> Bool {
        func key(_ path: String) -> String {
            let resolved: String
            if let pointer = realpath(path, nil) {
                resolved = String(cString: pointer)
                free(pointer)
            } else {
                resolved = (path as NSString).standardizingPath
            }
            return resolved.precomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: nil)
        }
        return key(url.path) == key(path(of: folder))
    }
}
