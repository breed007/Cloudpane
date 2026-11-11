import AppKit
import CloudpaneCore
import SwiftUI

enum Theme {
    /// A clear-sky blue, the one accent color, used the way the other 404 Tools apps use
    /// theirs: tint, selection and bars. Everything else is the system's dark appearance.
    static let accent = Color(red: 0.36, green: 0.66, blue: 0.96)
    /// The part of a bar that is only in the cloud.
    static let cloudOnly = Color(red: 0.36, green: 0.66, blue: 0.96).opacity(0.35)
    static let warning = Color.orange
}

enum Format {
    /// "0 bytes" rather than "Zero KB".
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
    }

    static func count(_ value: Int) -> String { value.formatted() }

    /// "1 file", "2 files". Shares Core's report formatting, which is tested there.
    static func count(_ value: Int, _ noun: String) -> String { ReportFormat().counted(value, noun) }

    static func money(_ value: Money) -> String {
        value.amount.formatted(.currency(code: value.currency))
    }

    /// "$23.97", or "$13.98 + €10.00" when currencies are mixed. Never converted.
    static func totals(_ value: CurrencyTotals) -> String {
        value.totals.map(money).joined(separator: " + ")
    }

    static func months(_ value: Double) -> String {
        if value <= 0 { return "Full" }
        if value < 1 { return "Under a month" }
        if value >= 120 { return "Over 10 years" }
        let rounded = Int(value.rounded())
        return rounded == 1 ? "About 1 month" : "About \(rounded) months"
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "Unknown" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    /// A path with the home folder shown as "~".
    static func path(_ path: String, home: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// The only two things Cloudpane does with a file.
enum FileActions {
    @MainActor
    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @MainActor
    static func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}
