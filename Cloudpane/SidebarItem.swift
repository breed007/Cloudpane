import Foundation

/// The sidebar's views, in order. The raw value is what the sidebar remembers between
/// launches.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview
    case fileSearch
    case duplicates
    case backupGrade
    case providers
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .fileSearch: return "File search"
        case .duplicates: return "Duplicates"
        case .backupGrade: return "Backup grade"
        case .providers: return "Providers"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .fileSearch: return "magnifyingglass"
        case .duplicates: return "doc.on.doc"
        case .backupGrade: return "checkmark.shield"
        case .providers: return "creditcard"
        case .history: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }

    static let storageKey = "sidebarSelection"

    /// The item for a stored raw value. Names from earlier versions map to the view that
    /// replaced them; anything else unknown falls back to Overview.
    init(stored: String) {
        switch stored {
        case "footprint": self = .overview
        case "whereIsIt": self = .fileSearch
        case "grade": self = .backupGrade
        case "subscriptions": self = .providers
        default: self = SidebarItem(rawValue: stored) ?? .overview
        }
    }

    /// Views that arrive in a later release. All are available now.
    var isAvailable: Bool { true }
}
