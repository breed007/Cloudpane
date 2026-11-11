// Cloudpane M0 feasibility spike.
//
// Walks the File Provider roots under ~/Library/CloudStorage and the iCloud Drive folder
// under ~/Library/Mobile Documents, reads URL resource values and lstat(2) facts for every
// item, and prints per-root totals, placeholder samples and extended attributes from a
// sample of files.
//
// Strictly read-only. The script never opens or reads file contents, never asks a provider
// to download anything, and disables dataless-file materialization for its own process
// before the walk, so an accidental read fails instead of triggering a download.
//
// Usage:
//   swift Spike/footprint-spike.swift [--home <dir>] [--redact] [--allow-folder-listing]
//
//   --home <dir>  Look for <dir>/Library/CloudStorage and
//                 <dir>/Library/Mobile Documents/com~apple~CloudDocs instead of the real home.
//   --redact      Replace account suffixes, unrecognized root names, file paths and extended
//                 attribute names not on an allowlist with stable placeholders and suppress
//                 attribute values, so the output can be committed.
//   --allow-folder-listing
//                 Let a provider fetch the listing of a folder it has not listed on this Mac
//                 yet. Materialization is turned on for this thread only around each folder
//                 listing call and turned off again before any file is looked at, so the
//                 script never reads or downloads a file's contents. A provider may still
//                 download items it keeps local by its own policy once their folder is
//                 listed. A check at the end of the run re-reads every file that was
//                 cloud-only and reports any that gained local data, with the time it did.

import Darwin
import Foundation
import UniformTypeIdentifiers

// MARK: - Provider table

enum NameMatch: Sendable {
    case exact(String)
    case prefix(String)

    /// Returns the account suffix when the folder name matches, or nil when it does not.
    func suffix(of name: String) -> String? {
        switch self {
        case .exact(let value):
            return name == value ? "" : nil
        case .prefix(let value):
            return name.hasPrefix(value) ? String(name.dropFirst(value.count)) : nil
        }
    }

    var pattern: String {
        switch self {
        case .exact(let value): return value
        case .prefix(let value): return value + "*"
        }
    }
}

struct RootRule: Sendable {
    let provider: String
    /// Parent directory relative to the home directory.
    let parent: String
    let match: NameMatch
    /// Whether the account suffix is user data that must be redacted.
    let suffixIsAccount: Bool
}

/// The only place provider layout lives. A layout change is an edit to this table.
let rootRules: [RootRule] = [
    RootRule(provider: "iCloud Drive", parent: "Library/Mobile Documents",
             match: .exact("com~apple~CloudDocs"), suffixIsAccount: false),
    RootRule(provider: "Dropbox", parent: "Library/CloudStorage",
             match: .prefix("Dropbox"), suffixIsAccount: true),
    RootRule(provider: "Google Drive", parent: "Library/CloudStorage",
             match: .prefix("GoogleDrive-"), suffixIsAccount: true),
    RootRule(provider: "OneDrive", parent: "Library/CloudStorage",
             match: .prefix("OneDrive-"), suffixIsAccount: true),
    RootRule(provider: "Box", parent: "Library/CloudStorage",
             match: .exact("Box-Box"), suffixIsAccount: false),
]

/// Parent directories whose unmatched children are reported as unrecognized. Mobile Documents
/// is excluded because it always holds per-app iCloud containers besides CloudDocs.
let parentsReportingUnrecognized: Set<String> = ["Library/CloudStorage"]

/// Attribute names printed verbatim in redacted output. Everything else is tokenized.
/// com.dropbox.ignored is the attribute Dropbox documents for excluding a file from sync.
let allowedXattrNames: Set<String> = [
    "com.apple.provenance", "com.apple.quarantine", "com.apple.FinderInfo",
    "com.apple.ResourceFork", "com.apple.lastuseddate#PS", "com.apple.decmpfs",
    "com.dropbox.ignored",
]

/// Spotlight attributes, also verbatim: "com.apple.metadata:" followed by an MDItem key.
let allowedXattrMetadataPrefix = "com.apple.metadata:"

/// Vendor prefixes kept in front of a token for names not on the allowlist, so the output
/// still shows whose attribute it is ("com.google.<xattr-3>").
let knownXattrVendors = [
    "com.apple", "com.dropbox", "com.getdropbox", "com.google", "com.microsoft", "com.box",
]

let unrecognizedProvider = "Unrecognized"
let placeholderSampleLimit = 5
let xattrSampleLimit = 20
let xattrValuePreviewLimit = 64

// MARK: - Options

/// realpath(3), so /tmp and /private/tmp match the paths the enumerator returns.
func canonicalPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

struct Options {
    var home = URL(fileURLWithPath: canonicalPath(FileManager.default.homeDirectoryForCurrentUser.path),
                   isDirectory: true)
    var homeIsReal = true
    var redact = false
    var allowFolderListing = false
}

func parseOptions() -> Options {
    var options = Options()
    var args = CommandLine.arguments.dropFirst()
    while let arg = args.popFirst() {
        switch arg {
        case "--home":
            guard let value = args.popFirst() else {
                fputs("error: --home needs a directory\n", stderr)
                exit(2)
            }
            options.home = URL(fileURLWithPath: canonicalPath((value as NSString).expandingTildeInPath),
                               isDirectory: true)
            options.homeIsReal = false
        case "--redact":
            options.redact = true
        case "--allow-folder-listing":
            options.allowFolderListing = true
        case "-h", "--help":
            print("usage: swift Spike/footprint-spike.swift [--home <dir>] [--redact] [--allow-folder-listing]")
            exit(0)
        default:
            fputs("error: unknown argument \(arg)\n", stderr)
            exit(2)
        }
    }
    return options
}

// MARK: - Text safety

/// Makes control characters visible so a file name can never break a line of output.
func flat(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if scalar.value < 0x20 || scalar.value == 0x7f {
                out += String(format: "\\x%02x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    return out
}

/// Markdown table cell: flattened, with pipes escaped.
func cell(_ text: String) -> String {
    flat(text).replacingOccurrences(of: "|", with: "\\|")
}

func row(_ cells: [String]) -> String {
    "| " + cells.map(cell).joined(separator: " | ") + " |"
}

// MARK: - Redaction

final class Redactor {
    let enabled: Bool
    private var accounts: [String: String] = [:]
    private var unrecognized: [String: String] = [:]
    private var paths: [String: String] = [:]
    private var xattrNames: [String: String] = [:]

    init(enabled: Bool) { self.enabled = enabled }

    /// Root folder name for display. Recognized roots keep the provider prefix and replace the
    /// account suffix ("GoogleDrive-<account-1>"); unrecognized roots are replaced entirely.
    func rootName(_ name: String, rule: RootRule?) -> String {
        guard enabled else { return name }
        guard let rule else { return token(name, in: &unrecognized, prefix: "unrecognized") }
        guard rule.suffixIsAccount, let suffix = rule.match.suffix(of: name), !suffix.isEmpty
        else { return name }
        return String(name.dropLast(suffix.count)) + token(suffix, in: &accounts, prefix: "account")
    }

    private func token(_ key: String, in table: inout [String: String], prefix: String) -> String {
        if let existing = table[key] { return existing }
        let label = "<\(prefix)-\(table.count + 1)>"
        table[key] = label
        return label
    }

    /// Path relative to a root for display. The redacted form keeps an extension only when the
    /// system knows it as a declared type (UTType is not dynamic), and never for a name that
    /// contains "@", so names like "Letter.Smith" or "someone@example.com" do not leak.
    func path(_ url: URL, root: URL, rootLabel: String) -> String {
        let full = url.path
        let base = root.path
        let relative = full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : full
        guard enabled else { return "\(rootLabel)/\(relative)" }
        if let existing = paths[full] { return existing }
        let ext = url.pathExtension
        let keep = !ext.isEmpty && !url.lastPathComponent.contains("@")
            && UTType(filenameExtension: ext).map { !$0.isDynamic } == true
        let label = "\(rootLabel)/<file-\(String(format: "%04d", paths.count + 1))>"
            + (keep ? ".\(ext)" : "")
        paths[full] = label
        return label
    }

    /// Extended attribute name for display. Redacted output keeps allowlisted names and
    /// Spotlight keys verbatim. Any other name under a known vendor prefix keeps only that
    /// prefix ("com.google.<xattr-3>"); everything else becomes <xattr-N>. The token is a
    /// per-run counter, not a hash, so it cannot be reversed by guessing.
    func xattrName(_ name: String) -> String {
        guard enabled else { return name }
        if allowedXattrNames.contains(name) || isSpotlightKey(name) { return name }
        let label = token(name, in: &xattrNames, prefix: "xattr")
        if let vendor = knownXattrVendors.first(where: { name.hasPrefix($0 + ".") }) {
            return "\(vendor).\(label)"
        }
        return label
    }

    /// "com.apple.metadata:kMDItemWhereFroms" and the like: an MDItem key and nothing else.
    private func isSpotlightKey(_ name: String) -> Bool {
        guard name.hasPrefix(allowedXattrMetadataPrefix) else { return false }
        var key = Substring(name.dropFirst(allowedXattrMetadataPrefix.count))
        if key.hasPrefix("_") { key = key.dropFirst() }
        return key.hasPrefix("kMDItem") && key.count > 7
            && key.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.letters.contains($0) }
    }

    func home(_ url: URL, isReal: Bool) -> String {
        guard enabled else { return url.path }
        return isReal ? "~" : "<fake home>"
    }
}

// MARK: - Errors

struct PosixError: Error, CustomStringConvertible {
    let code: Int32
    init(_ code: Int32 = errno) { self.code = code }
    var description: String { "errno \(code) \(String(cString: strerror(code)))" }
}

/// Domain and code, the underlying POSIX errno when there is one, and a hint for the two
/// failures this spike most needs to recognize.
func describe(error: Error) -> String {
    let ns = error as NSError
    var text = "\(ns.domain) \(ns.code)"
    var posix: Int32?
    if ns.domain == NSPOSIXErrorDomain {
        posix = Int32(ns.code)
    } else if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
        if underlying.domain == NSPOSIXErrorDomain {
            posix = Int32(underlying.code)
        } else {
            text += ", underlying \(underlying.domain) \(underlying.code)"
        }
    }
    if let posix { text += ", \(PosixError(posix))" }
    if posix == EDEADLK {
        text += " [possibly blocked materialization of a dataless item (unverified)]"
    }
    if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadInvalidFileNameError {
        text += " [path may exceed PATH_MAX (\(PATH_MAX) bytes); nothing below this item was walked]"
    }
    return text
}

// MARK: - Per-item facts

let resourceKeys: [URLResourceKey] = [
    .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey,
    .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .isPackageKey,
]

enum DownloadStatus: String {
    case current, downloaded, notDownloaded, none

    init(_ status: URLUbiquitousItemDownloadingStatus?) {
        switch status {
        case .some(.current): self = .current
        case .some(.downloaded): self = .downloaded
        case .some(.notDownloaded): self = .notDownloaded
        default: self = .none
        }
    }
}

struct Item {
    let url: URL
    let logical: Int64
    let allocated: Int64
    let logicalReported: Bool
    let allocatedReported: Bool
    let modified: Date?
    let isUbiquitous: Bool
    let status: DownloadStatus
    let isPackage: Bool
    /// SF_DATALESS from lstat(2): the kernel's own record that the item has no local data.
    let isDataless: Bool
    /// UF_COMPRESSED from lstat(2): data lives in a decmpfs attribute, so allocated can be 0.
    let isCompressed: Bool

    /// Only an item that reports fileSize 0. A package directory reports no fileSize at all;
    /// it is counted under "No fileSize" instead.
    var isZeroByte: Bool { logicalReported && logical == 0 }
    var hasContent: Bool { logical > 0 }

    /// Both placeholder tests need logical > 0, so zero-byte files and items with no reported
    /// size never count as placeholders.
    ///
    /// Loose definition: allocated == 0 or not downloaded.
    /// "Not downloaded" is read as status == notDownloaded. A nil status (non-ubiquitous file)
    /// is not "not downloaded", so the file falls back to the allocated test alone.
    var isPlaceholderLoose: Bool {
        hasContent && (allocated == 0 || status == .notDownloaded)
    }

    /// Strict definition: materialized when allocated > 0 or status == current; placeholder
    /// otherwise. A nil status is treated as "not current", so again only allocated decides.
    var isPlaceholderStrict: Bool {
        hasContent && allocated == 0 && status != .current
    }

    var isSampleWorthy: Bool { isPlaceholderLoose || isPlaceholderStrict || isDataless }
}

/// Hard links share (device, inode). The first path seen is counted; later ones are skipped.
final class HardLinkTracker {
    private var seen: Set<[UInt64]> = []

    /// Returns true when this inode was already counted.
    func isDuplicate(_ info: stat) -> Bool {
        guard info.st_nlink > 1 else { return false }
        return !seen.insert([UInt64(UInt32(bitPattern: info.st_dev)), info.st_ino]).inserted
    }
}

// MARK: - Per-root stats

final class RootStats {
    let provider: String
    let rule: RootRule?
    let url: URL
    let label: String
    var note: String?

    var files = 0
    var packages = 0
    var directories = 0
    var datalessDirectories = 0
    var logical: Int64 = 0
    var allocated: Int64 = 0
    var placeholdersLoose = 0
    var placeholdersStrict = 0
    var dataless = 0
    var compressed = 0
    var zeroByte = 0
    var hardLinkDuplicates = 0
    var symlinks = 0
    var otherTypes = 0
    var errors: [String] = []
    var ubiquitous = 0
    var statusCounts: [DownloadStatus: Int] = [:]
    var missingLogical = 0
    var missingAllocated = 0
    var elapsed: Duration = .zero
    var placeholderSamples: [Item] = []
    var xattrPlaceholderPool: [Item] = []
    var xattrOtherPool: [Item] = []

    // --allow-folder-listing only.
    var datalessFolderListings = 0
    var foldersStillDataless = 0
    var datalessFilePaths: [String] = []
    /// Files that were cloud-only when visited and had local data at the final check, with
    /// their inode change time (ctime), so a provider-side download can be placed in time.
    var filesNowLocal: [(url: URL, changed: Date)] = []
    var filesGone = 0

    init(provider: String, rule: RootRule?, url: URL, label: String) {
        self.provider = provider
        self.rule = rule
        self.url = url
        self.label = label
    }

    func add(_ item: Item) {
        files += 1
        if item.isPackage { packages += 1 }
        logical += item.logical
        allocated += item.allocated
        if !item.logicalReported { missingLogical += 1 }
        if !item.allocatedReported { missingAllocated += 1 }
        if item.isZeroByte { zeroByte += 1 }
        if item.isPlaceholderLoose { placeholdersLoose += 1 }
        if item.isPlaceholderStrict { placeholdersStrict += 1 }
        if item.isDataless { dataless += 1 }
        if item.isCompressed { compressed += 1 }
        if item.isUbiquitous { ubiquitous += 1 }
        statusCounts[item.status, default: 0] += 1
        if item.isSampleWorthy {
            if placeholderSamples.count < placeholderSampleLimit { placeholderSamples.append(item) }
            if xattrPlaceholderPool.count < xattrSampleLimit { xattrPlaceholderPool.append(item) }
        } else if xattrOtherPool.count < xattrSampleLimit {
            xattrOtherPool.append(item)
        }
    }

    /// Up to 20 files, half placeholders and half not when both exist, filled from the other
    /// pool when one runs short.
    var xattrSample: [Item] {
        let half = xattrSampleLimit / 2
        var placeholders = Array(xattrPlaceholderPool.prefix(half))
        var others = Array(xattrOtherPool.prefix(half))
        let room = xattrSampleLimit - placeholders.count - others.count
        if room > 0 {
            if placeholders.count < half {
                others = Array(xattrOtherPool.prefix(others.count + room))
            } else {
                placeholders = Array(xattrPlaceholderPool.prefix(placeholders.count + room))
            }
        }
        return placeholders + others
    }
}

// MARK: - Root discovery

enum ParentState {
    case listed([String])
    case missing
    case symlink(String)
    case notDirectory(String)
    case unreadable(String)
}

func lstatInfo(_ path: String) -> stat? {
    var info = stat()
    return lstat(path, &info) == 0 ? info : nil
}

func fileType(_ info: stat) -> mode_t { info.st_mode & S_IFMT }

/// Checks every component of the parent below home without following symbolic links, then
/// lists it. A symlinked Library or CloudStorage is reported, never followed.
func readParent(home: URL, parent: String) -> ParentState {
    var current = home
    var walked: [String] = []
    for component in parent.split(separator: "/").map(String.init) {
        current = current.appendingPathComponent(component, isDirectory: true)
        walked.append(component)
        let shown = walked.joined(separator: "/")
        guard let info = lstatInfo(current.path) else {
            return errno == ENOENT ? .missing : .unreadable("\(shown): \(PosixError())")
        }
        switch fileType(info) {
        case S_IFDIR: continue
        case S_IFLNK: return .symlink(shown)
        default: return .notDirectory(shown)
        }
    }
    do {
        return .listed(try FileManager.default.contentsOfDirectory(atPath: current.path))
    } catch {
        return .unreadable("\(parent): \(describe(error: error))")
    }
}

struct ProviderStatus {
    let provider: String
    let status: String
}

struct Discovery {
    var roots: [RootStats] = []
    var missing: [ProviderStatus] = []
}

func discoverRoots(home: URL, redactor: Redactor) -> Discovery {
    var discovery = Discovery()
    var seenProviders: Set<String> = []
    var parentStates: [String: ParentState] = [:]

    let parents = Array(Set(rootRules.map(\.parent))).sorted()
    for parent in parents {
        let state = readParent(home: home, parent: parent)
        parentStates[parent] = state
        guard case .listed(let names) = state else { continue }
        let parentURL = home.appendingPathComponent(parent, isDirectory: true)
        let rules = rootRules.filter { $0.parent == parent }
        for name in names.sorted() where !name.hasPrefix(".") {
            let url = parentURL.appendingPathComponent(name, isDirectory: true)
            let rule = rules.first { $0.match.suffix(of: name) != nil }
            if rule == nil && !parentsReportingUnrecognized.contains(parent) { continue }
            let provider = rule?.provider ?? unrecognizedProvider
            let stats = RootStats(provider: provider, rule: rule, url: url,
                                  label: redactor.rootName(name, rule: rule))
            if let info = lstatInfo(url.path) {
                switch fileType(info) {
                case S_IFDIR: break
                case S_IFLNK: stats.note = "symbolic link, not followed"
                default: stats.note = "not a directory"
                }
            } else {
                stats.note = "could not stat: \(PosixError())"
            }
            // Any matching entry, walkable or not, is that provider's status.
            seenProviders.insert(provider)
            discovery.roots.append(stats)
        }
    }

    for rule in rootRules where !seenProviders.contains(rule.provider) {
        if discovery.missing.contains(where: { $0.provider == rule.provider }) { continue }
        let status: String
        switch parentStates[rule.parent] ?? .missing {
        case .listed:
            status = "not installed (no \(rule.match.pattern) in \(rule.parent))"
        case .missing:
            status = "not installed (\(rule.parent) does not exist)"
        case .symlink(let where_):
            status = "unknown (\(where_) is a symbolic link, not followed)"
        case .notDirectory(let where_):
            status = "unknown (\(where_) is not a directory)"
        case .unreadable(let reason):
            status = "unknown (could not read \(reason))"
        }
        discovery.missing.append(ProviderStatus(provider: rule.provider, status: status))
    }

    let order = rootRules.map(\.provider) + [unrecognizedProvider]
    discovery.roots.sort {
        let a = order.firstIndex(of: $0.provider) ?? order.count
        let b = order.firstIndex(of: $1.provider) ?? order.count
        return a != b ? a < b : $0.url.lastPathComponent < $1.url.lastPathComponent
    }
    return discovery
}

// MARK: - Walk

func walk(_ stats: RootStats, redactor: Redactor, hardLinks: HardLinkTracker) {
    let clock = ContinuousClock()
    let start = clock.now
    defer { stats.elapsed = clock.now - start }

    func log(_ url: URL, _ what: String) {
        stats.errors.append("\(redactor.path(url, root: stats.url, rootLabel: stats.label)): \(what)")
    }

    let enumerator = FileManager.default.enumerator(
        at: stats.url,
        includingPropertiesForKeys: resourceKeys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { url, error in
            log(url, describe(error: error))
            return true
        })
    guard let enumerator else {
        stats.errors.append("\(stats.label): could not create enumerator")
        return
    }

    // One autorelease pool per item. Foundation autoreleases URLs and resource values on
    // every step, and the main thread's pool would not drain until the walk returned, so a
    // large tree would hold every item's objects in memory at once.
    while true {
        let more: Bool = autoreleasepool {
            guard let next = enumerator.nextObject() else { return false }
            guard let url = next as? URL else { return true }
            _ = visit(url, stats: stats, hardLinks: hardLinks, log: log)
            return true
        }
        if !more { break }
    }
}

/// Records one item. Returns the URL when it is a folder to descend into (not a package).
func visit(_ url: URL, stats: RootStats, hardLinks: HardLinkTracker,
           log: (URL, String) -> Void) -> URL? {
    guard let info = lstatInfo(url.path) else {
        log(url, "lstat \(PosixError())")
        return nil
    }
    let isDataless = info.st_flags & UInt32(SF_DATALESS) != 0
    switch fileType(info) {
    case S_IFLNK:
        stats.symlinks += 1
        return nil
    case S_IFDIR, S_IFREG:
        break
    default:
        stats.otherTypes += 1
        return nil
    }

    let values: URLResourceValues
    do {
        values = try url.resourceValues(forKeys: Set(resourceKeys))
    } catch {
        log(url, "resource values \(describe(error: error))")
        return nil
    }
    let isPackage = fileType(info) == S_IFDIR && values.isPackage == true
    if fileType(info) == S_IFDIR && !isPackage {
        stats.directories += 1
        if isDataless { stats.datalessDirectories += 1 }
        return url
    }
    if fileType(info) == S_IFREG && hardLinks.isDuplicate(info) {
        stats.hardLinkDuplicates += 1
        return nil
    }
    stats.add(Item(
        url: url,
        logical: Int64(values.fileSize ?? 0),
        allocated: Int64(values.totalFileAllocatedSize ?? 0),
        logicalReported: values.fileSize != nil,
        allocatedReported: values.totalFileAllocatedSize != nil,
        modified: values.contentModificationDate,
        isUbiquitous: values.isUbiquitousItem == true,
        status: DownloadStatus(values.ubiquitousItemDownloadingStatus),
        isPackage: isPackage,
        isDataless: isDataless,
        isCompressed: info.st_flags & UInt32(UF_COMPRESSED) != 0))
    if isDataless && fileType(info) == S_IFREG { stats.datalessFilePaths.append(url.path) }
    return nil
}

// MARK: - Walk with folder listing (--allow-folder-listing)

/// Sets this thread's dataless materialization policy. ON lets a provider fill in a folder's
/// listing; DEFAULT returns the thread to the process policy, which run() sets to OFF.
func setThreadMaterialization(_ on: Bool) -> Bool {
    setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                   on ? IOPOL_MATERIALIZE_DATALESS_FILES_ON : IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT) == 0
}

/// Lists one folder with materialization on for exactly the directory read. No resource
/// values are prefetched and no options are passed, so nothing about the children is read
/// while the policy is on (.skipsHiddenFiles would read each child's hidden flag). Hidden
/// children are dropped afterward, with the policy back off: names starting with a dot here,
/// and items with the hidden flag set (UF_HIDDEN) by lstat.
func listFolder(_ url: URL) throws -> [URL] {
    guard setThreadMaterialization(true) else { throw PosixError() }
    let listed = Result {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [], options: [])
    }
    if !setThreadMaterialization(false) {
        fputs("error: could not turn materialization back off; stopping\n", stderr)
        exit(3)
    }
    return try listed.get().filter { child in
        guard !child.lastPathComponent.hasPrefix(".") else { return false }
        guard let info = lstatInfo(child.path) else { return true }  // visit() logs the error
        return info.st_flags & UInt32(UF_HIDDEN) == 0
    }
}

func isDataless(_ path: String) -> Bool? {
    guard let info = lstatInfo(path) else { return nil }
    return info.st_flags & UInt32(SF_DATALESS) != 0
}

/// Depth-first walk that lists each folder itself instead of using an enumerator, so the
/// materialization policy can be on for the listing and off for everything else.
func walkWithFolderListing(_ stats: RootStats, redactor: Redactor, hardLinks: HardLinkTracker) {
    let clock = ContinuousClock()
    let start = clock.now
    defer { stats.elapsed = clock.now - start }

    func log(_ url: URL, _ what: String) {
        stats.errors.append("\(redactor.path(url, root: stats.url, rootLabel: stats.label)): \(what)")
    }

    var pending: [URL] = [stats.url]
    while let folder = pending.popLast() {
        autoreleasepool {
            let wasDataless = isDataless(folder.path) == true
            let children: [URL]
            do {
                children = try listFolder(folder)
            } catch {
                log(folder, "list \(describe(error: error))")
                return
            }
            if wasDataless {
                stats.datalessFolderListings += 1
                if isDataless(folder.path) == true { stats.foldersStillDataless += 1 }
            }
            var subfolders: [URL] = []
            for child in children.sorted(by: { $0.path < $1.path }) {
                autoreleasepool {
                    if let sub = visit(child, stats: stats, hardLinks: hardLinks, log: log) {
                        subfolders.append(sub)
                    }
                }
            }
            pending.append(contentsOf: subfolders.reversed())
        }
    }
}

/// Reads every file that was cloud-only when visited again. Called once, at the very end of
/// the run, after the extended-attribute sampling and the rest of the output, so the check
/// covers the whole run window.
func recheckDataless(_ stats: RootStats) {
    for path in stats.datalessFilePaths {
        guard let info = lstatInfo(path) else {
            stats.filesGone += 1
            continue
        }
        if info.st_flags & UInt32(SF_DATALESS) != 0 { continue }
        let changed = Date(timeIntervalSince1970: Double(info.st_ctimespec.tv_sec)
                           + Double(info.st_ctimespec.tv_nsec) / 1e9)
        stats.filesNowLocal.append((URL(fileURLWithPath: path), changed))
    }
}

// MARK: - Extended attributes (metadata only, never file contents)

struct XattrEntry {
    let name: String
    let length: Int
    let preview: String
}

func readXattrs(_ url: URL, redact: Bool) -> Result<[XattrEntry], PosixError> {
    let path = url.path
    let listSize = listxattr(path, nil, 0, XATTR_NOFOLLOW)
    if listSize < 0 { return .failure(PosixError()) }
    if listSize == 0 { return .success([]) }

    var buffer = [CChar](repeating: 0, count: listSize)
    let read = listxattr(path, &buffer, listSize, XATTR_NOFOLLOW)
    if read < 0 { return .failure(PosixError()) }

    let names = buffer[0..<read].split(separator: 0).map {
        String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    var entries: [XattrEntry] = []
    for name in names {
        let length = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        if length < 0 {
            entries.append(XattrEntry(name: name, length: -1, preview: "error \(PosixError())"))
            continue
        }
        // The resource fork is file data; never read it.
        guard name != "com.apple.ResourceFork", length <= xattrValuePreviewLimit else {
            entries.append(XattrEntry(name: name, length: length, preview: "(value not read)"))
            continue
        }
        var value = [UInt8](repeating: 0, count: max(length, 1))
        let got = getxattr(path, name, &value, length, 0, XATTR_NOFOLLOW)
        if got < 0 {
            entries.append(XattrEntry(name: name, length: length, preview: "error \(PosixError())"))
            continue
        }
        entries.append(XattrEntry(name: name, length: length,
                                  preview: describe(Array(value[0..<got]), redact: redact)))
    }
    return .success(entries)
}

func describe(_ bytes: [UInt8], redact: Bool) -> String {
    let isBplist = bytes.starts(with: Array("bplist".utf8))
    let text = String(bytes: bytes, encoding: .utf8)
    let printable = text.map { str in
        str.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f }
    } ?? false
    let isHexText = printable && !bytes.isEmpty && bytes.allSatisfy {
        (0x30...0x39).contains($0) || (0x61...0x66).contains($0) || (0x41...0x46).contains($0)
    }

    let kind: String
    if isBplist { kind = "binary plist" }
    else if isHexText { kind = "hex text, \(bytes.count) chars" }
    else if printable { kind = "UTF-8 text" }
    else { kind = "binary" }
    if redact { return kind }

    if printable, let text {
        let short = text.count > 48 ? String(text.prefix(48)) + "..." : text
        return "\(kind): \"\(short)\""
    }
    let hex = bytes.prefix(32).map { String(format: "%02x", $0) }.joined()
    return "\(kind): \(hex)\(bytes.count > 32 ? "..." : "")"
}

// MARK: - Output helpers

func human(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func milliseconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    let ms = Double(seconds) * 1000 + Double(attoseconds) / 1e15
    return String(format: "%.1f", ms)
}

func dateString(_ date: Date?) -> String {
    guard let date else { return "-" }
    return date.formatted(.iso8601)
}

func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

// MARK: - Main

/// Disables dataless-file materialization for this process, so a read that would make a
/// provider fetch content fails instead of downloading. The man page does not name the
/// errno a blocked read returns; EDEADLK is the expected one and is flagged as unverified.
func disableMaterialization() -> String {
    let result = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES,
                                IOPOL_SCOPE_PROCESS,
                                IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    return result == 0
        ? "off for this process (setiopolicy_np)"
        : "could not disable (\(PosixError())); the script still never reads file contents"
}

func run() {
    let runStarted = Date()
    let options = parseOptions()
    let redactor = Redactor(enabled: options.redact)
    let materialization = disableMaterialization()

    print("# Cloudpane M0 footprint spike")
    print("")
    print("- Home: \(flat(redactor.home(options.home, isReal: options.homeIsReal)))"
          + (options.homeIsReal ? "" : " (--home)"))
    print("- Run at: \(Date().formatted(.iso8601))")
    print("- Dataless materialization: \(materialization)")
    if options.allowFolderListing {
        print("- Folder listing: allowed. Materialization is on for this thread only around each")
        print("  folder listing call; every file is examined with it off.")
    }
    print("- Redacted: \(options.redact ? "yes" : "no")")
    print("- Placeholder (loose): logical > 0 and (allocated == 0 or status == notDownloaded)")
    print("- Placeholder (strict): logical > 0 and allocated == 0 and status != current")
    print("- Dataless (st_flags): SF_DATALESS set by the kernel; the ground truth for the two above.")
    print("- Compressed: UF_COMPRESSED set; such files can report allocated 0 with data on disk.")
    print("- A nil download status (non-ubiquitous item) counts as neither notDownloaded nor current.")
    print("- Only regular files and packages are counted. Packages count as one item with the")
    print("  sizes the package directory itself reports. Extra hard links to a counted inode,")
    print("  symbolic links and other file types (FIFOs, sockets, devices) are skipped and counted.")

    let discovery = discoverRoots(home: options.home, redactor: redactor)
    let hardLinks = HardLinkTracker()
    for stats in discovery.roots where stats.note == nil {
        if options.allowFolderListing {
            walkWithFolderListing(stats, redactor: redactor, hardLinks: hardLinks)
        } else {
            walk(stats, redactor: redactor, hardLinks: hardLinks)
        }
    }

    print("")
    print("## Roots")
    print("")
    print(row(["Provider", "Account root", "Status"]))
    print(row(["---", "---", "---"]))
    for stats in discovery.roots {
        let status = stats.note ?? (stats.rule == nil ? "unrecognized, walked" : "walked")
        print(row([stats.provider, stats.label, status]))
    }
    for missing in discovery.missing {
        print(row([missing.provider, "-", missing.status]))
    }

    let walked = discovery.roots.filter { $0.note == nil }
    guard !walked.isEmpty else {
        print("")
        print("No provider roots found. Nothing to walk.")
        return
    }

    print("")
    print("## Totals")
    print("")
    print(row(["Provider", "Account root", "Files", "Packages", "Dirs", "Logical bytes",
               "Logical", "Allocated bytes", "Allocated", "Placeholders (loose)",
               "Placeholders (strict)", "Dataless (st_flags)", "Compressed", "Zero-byte",
               "Hard links skipped", "Symlinks skipped", "Other types skipped", "Errors",
               "Walk ms"]))
    print(row(Array(repeating: "---", count: 19)))
    for s in walked {
        print(row([s.provider, s.label, "\(s.files)", "\(s.packages)", "\(s.directories)",
                   "\(s.logical)", human(s.logical), "\(s.allocated)", human(s.allocated),
                   "\(s.placeholdersLoose)", "\(s.placeholdersStrict)", "\(s.dataless)",
                   "\(s.compressed)", "\(s.zeroByte)", "\(s.hardLinkDuplicates)",
                   "\(s.symlinks)", "\(s.otherTypes)", "\(s.errors.count)",
                   milliseconds(s.elapsed)]))
    }

    print("")
    print("## Ubiquity and download status")
    print("")
    print(row(["Account root", "Ubiquitous", "current", "downloaded", "notDownloaded",
               "nil", "No fileSize", "No allocated size", "Dataless dirs"]))
    print(row(Array(repeating: "---", count: 9)))
    for s in walked {
        print(row([s.label, "\(s.ubiquitous)",
                   "\(s.statusCounts[.current, default: 0])",
                   "\(s.statusCounts[.downloaded, default: 0])",
                   "\(s.statusCounts[.notDownloaded, default: 0])",
                   "\(s.statusCounts[.none, default: 0])",
                   "\(s.missingLogical)", "\(s.missingAllocated)", "\(s.datalessDirectories)"]))
    }

    print("")
    print("## Placeholder samples (first \(placeholderSampleLimit) per root, any definition)")
    for s in walked {
        print("")
        print("### \(flat(s.label))")
        print("")
        if s.placeholderSamples.isEmpty {
            print("No placeholders.")
            continue
        }
        print(row(["Path", "Logical bytes", "Allocated bytes", "Status", "Loose",
                   "Strict", "Dataless", "Compressed", "Modified"]))
        print(row(Array(repeating: "---", count: 9)))
        for item in s.placeholderSamples {
            print(row([redactor.path(item.url, root: s.url, rootLabel: s.label),
                       "\(item.logical)", "\(item.allocated)", item.status.rawValue,
                       yesNo(item.isPlaceholderLoose), yesNo(item.isPlaceholderStrict),
                       yesNo(item.isDataless), yesNo(item.isCompressed),
                       dateString(item.modified)]))
        }
    }

    print("")
    print("## Extended attributes (sample of up to \(xattrSampleLimit) files per root)")
    for s in walked {
        print("")
        print("### \(flat(s.label))")
        print("")
        let sample = s.xattrSample
        if sample.isEmpty {
            print("No files.")
            continue
        }
        var nameCounts: [String: Int] = [:]
        var lines: [String] = []
        var withAny = 0
        for item in sample {
            let path = flat(redactor.path(item.url, root: s.url, rootLabel: s.label))
            switch readXattrs(item.url, redact: options.redact) {
            case .failure(let err):
                lines.append("- \(path): listxattr failed: \(err)")
            case .success(let entries):
                if entries.isEmpty { continue }
                withAny += 1
                lines.append("- \(path)")
                for entry in entries {
                    let name = redactor.xattrName(entry.name)
                    nameCounts[name, default: 0] += 1
                    lines.append("  - \(flat(name)) (\(entry.length) bytes): \(flat(entry.preview))")
                }
            }
        }
        print("Sampled \(sample.count) \(sample.count == 1 ? "file" : "files"), "
              + "\(withAny) with extended attributes.")
        if !nameCounts.isEmpty {
            print("")
            print(row(["Attribute", "Files"]))
            print(row(["---", "---"]))
            for (name, count) in nameCounts.sorted(by: { $0.key < $1.key }) {
                print(row([name, "\(count)"]))
            }
            print("")
            lines.forEach { print($0) }
        }
    }

    let withErrors = walked.filter { !$0.errors.isEmpty }
    if !withErrors.isEmpty {
        print("")
        print("## Enumerator errors")
        for s in withErrors {
            print("")
            print("### \(flat(s.label))")
            print("")
            s.errors.forEach { print("- \(flat($0))") }
        }
    }

    // Last, so it covers the whole run: the walk, the extended-attribute sampling and the
    // output above.
    if options.allowFolderListing {
        walked.forEach(recheckDataless)
        print("")
        print("## Folder listing check")
        print("")
        print("Every file that was cloud-only (SF_DATALESS) when visited is read again at the very end")
        print("of the run. The spike never reads file contents, so a file that gained local data was")
        print("downloaded by its provider. Its change time (ctime) tells when; compare it with the")
        print("provider's logs to tell a download the provider scheduled on its own from anything else.")
        print("")
        print("- Run started: \(runStarted.formatted(.iso8601))")
        print("- Check at: \(Date().formatted(.iso8601))")
        print("")
        print(row(["Account root", "Cloud-only folders listed", "Folders still cloud-only after listing",
                   "Cloud-only files", "Now local", "Gone since visit"]))
        print(row(Array(repeating: "---", count: 6)))
        for s in walked {
            print(row([s.label, "\(s.datalessFolderListings)", "\(s.foldersStillDataless)",
                       "\(s.datalessFilePaths.count)", "\(s.filesNowLocal.count)", "\(s.filesGone)"]))
        }
        let local = walked.flatMap { s in s.filesNowLocal.map { (s, $0) } }
        print("")
        if local.isEmpty {
            print("Result: no cloud-only file gained local data during the run.")
        } else {
            print("Result: \(local.count) \(local.count == 1 ? "file" : "files") gained local data during the run.")
            for (s, item) in local.prefix(20) {
                print("- \(flat(redactor.path(item.url, root: s.url, rootLabel: s.label))), changed \(item.changed.formatted(.iso8601))")
            }
        }
    }
}

run()