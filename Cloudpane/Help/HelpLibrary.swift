import CloudpaneCore
import Foundation
import Observation

/// The bundled help, read once, and which topic the Help window shows. The pages are the
/// Markdown files in docs/help, bundled as the "help" folder; HelpCatalog in CloudpaneCore
/// reads them, so an iOS app could share both.
@MainActor
@Observable
final class HelpLibrary {
    static let shared = HelpLibrary()
    static let windowID = "help"

    let catalog: HelpCatalog?
    let loadError: String?
    /// The topic the Help window shows.
    var selection: String?
    /// A heading in that topic to scroll to, once.
    var anchor: String?

    /// Shows "topic" or "topic#anchor".
    func show(_ destination: String) {
        let parts = destination.split(separator: "#", maxSplits: 1).map(String.init)
        selection = parts.first
        anchor = parts.count == 2 ? parts[1] : nil
    }

    init(bundle: Bundle = .main) {
        do {
            let catalog = try HelpCatalog(bundle: bundle, platform: .macOS)
            self.catalog = catalog
            loadError = catalog.topics.isEmpty ? "No help topics were found in the app." : nil
            selection = catalog.topics.first?.id
        } catch {
            catalog = nil
            loadError = "Help could not be read. \(error)"
        }
    }

    var topics: [HelpTopic] { catalog?.topics ?? [] }

    func topic(_ id: String?) -> HelpTopic? { id.flatMap { catalog?.topic(id: $0) } }
}
