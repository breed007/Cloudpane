import Foundation

/// The help topic each part of the app links to, by file name in docs/help without ".md".
/// A test checks that every one exists.
enum HelpTopics {
    static let gettingStarted = "getting-started"
    static let overview = "overview"
    static let fileSearch = "file-search"
    static let duplicates = "duplicates"
    static let backupGrade = "backup-grade"
    static let providers = "providers"
    static let iCloud = "icloud"
    static let history = "history"
    static let exporting = "exporting"
    static let settings = "settings"
    static let troubleshooting = "troubleshooting"

    /// Learn more links outside the main views' help buttons, each to its section: "topic"
    /// or "topic#heading-anchor".
    static let folderAccess = "getting-started#the-two-folders"
    static let hashing = "duplicates#hashing"
    static let addProvider = "providers#adding-a-provider"
    static let partialView = "troubleshooting#partial-view"
    static let pdfExport = "exporting#the-pdf-report"

    static let all = [gettingStarted, overview, fileSearch, duplicates, backupGrade, providers, iCloud, history,
                      exporting, settings, troubleshooting, folderAccess, hashing, addProvider, partialView, pdfExport]
}

extension SidebarItem {
    /// The topic the view's help button opens.
    var helpTopic: String {
        switch self {
        case .overview: return HelpTopics.overview
        case .fileSearch: return HelpTopics.fileSearch
        case .duplicates: return HelpTopics.duplicates
        case .backupGrade: return HelpTopics.backupGrade
        case .providers: return HelpTopics.providers
        case .history: return HelpTopics.history
        case .settings: return HelpTopics.settings
        }
    }
}
