import CloudpaneCore
import XCTest

/// The help pages in docs/help, as bundled and as written.
final class HelpTests: XCTestCase {
    private var helpFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/help")
    }

    private var bundle: Bundle { Bundle(for: HelpTests.self) }

    private func sourceFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: helpFolder.path).filter { $0.hasSuffix(".md") }.sorted()
    }

    func testEveryHelpFileHasValidFrontMatterAndIsBundled() throws {
        let files = try sourceFiles()
        XCTAssertGreaterThan(files.count, 10)
        let bundled = (bundle.urls(forResourcesWithExtension: "md", subdirectory: "help") ?? [])
            .map(\.lastPathComponent).sorted()
        XCTAssertEqual(bundled, files.filter { $0 != "README.md" },
                       "the bundle has every topic in docs/help, and not the README")

        var texts: [String: String] = [:]
        for file in files { texts[file] = try String(contentsOf: helpFolder.appendingPathComponent(file), encoding: .utf8) }
        let mac = try HelpCatalog(files: texts, platform: .macOS)
        XCTAssertEqual(mac.topics.count, files.count - 1, "every file but README is a topic")
        XCTAssertEqual(mac.topic(id: "privacy")?.title, "Privacy")
        XCTAssertEqual(Set(mac.topics.map(\.order)).count, mac.topics.count, "no two topics share an order")
        for topic in mac.topics {
            XCTAssertFalse(topic.body.isEmpty, topic.id)
            XCTAssertTrue(topic.body.hasPrefix("# \(topic.title)"), "\(topic.id) starts with its title")
        }
    }

    func testEveryLinkResolvesOnBothPlatforms() throws {
        for platform in HelpPlatform.allCases {
            let catalog = try HelpCatalog(bundle: bundle, platform: platform)
            let broken = catalog.unresolvedLinks()
            XCTAssertTrue(broken.isEmpty, "\(platform): \(broken)")
        }
    }

    func testEveryHelpButtonAndLearnMoreLinkHasATopic() throws {
        let catalog = try HelpCatalog(bundle: bundle, platform: .macOS)
        for item in SidebarItem.allCases {
            XCTAssertNotNil(catalog.topic(id: item.helpTopic), "\(item) points at \(item.helpTopic)")
        }
        for destination in HelpTopics.all {
            // "topic" or "topic#anchor", as a link from another page would write it.
            let parts = destination.split(separator: "#", maxSplits: 1).map(String.init)
            let link = parts[0] + ".md" + (parts.count == 2 ? "#" + parts[1] : "")
            XCTAssertTrue(catalog.resolves(link), "\(destination) does not resolve")
        }
        XCTAssertTrue(HelpTopics.all.filter { $0.contains("#") }.count >= 5, "Learn more links target sections")
    }

    func testMacOnlyMaterialIsDroppedForIOS() throws {
        let mac = try HelpCatalog(bundle: bundle, platform: .macOS)
        let iOS = try HelpCatalog(bundle: bundle, platform: .iOS)
        XCTAssertNotNil(mac.topic(id: "keyboard-shortcuts"))
        XCTAssertNil(iOS.topic(id: "keyboard-shortcuts"), "a Mac-only topic")
        XCTAssertNil(iOS.topic(id: "settings"))
        let macStart = try XCTUnwrap(mac.topic(id: "getting-started")).body
        let iOSStart = try XCTUnwrap(iOS.topic(id: "getting-started")).body
        XCTAssertTrue(macStart.contains("Grant access"))
        XCTAssertFalse(iOSStart.contains("Grant access"), "the folder grants are Mac-only")
        XCTAssertTrue(iOSStart.contains("What each provider needs"), "the shared part stays")
        for topic in iOS.topics {
            for word in ["Finder", "⌘", "Dock", "open panel"] {
                XCTAssertFalse(topic.body.contains(word), "\(topic.id) mentions \(word) on iOS")
            }
        }
    }

    func testSearchFindsAKnownTerm() throws {
        let catalog = try HelpCatalog(bundle: bundle, platform: .macOS)
        let placeholder = catalog.search("placeholder").map(\.id)
        XCTAssertTrue(placeholder.contains("duplicates"), "\(placeholder)")
        XCTAssertEqual(catalog.search("backup grade").first?.id, "backup-grade", "the title match comes first")
        XCTAssertTrue(catalog.search("OneNote").map(\.id).contains("privacy"))
    }

    /// House style for shipped prose.
    func testHelpProseFollowsTheHouseStyle() throws {
        let banned = ["delve", "robust", "seamless", "crucial", "leverage", "comprehensive", "enhance",
                      "showcase", "highlight", "notably", "moreover", "furthermore", "additionally", "serves as"]
        for file in try sourceFiles() where file != "README.md" {
            // Platform markers are HTML comments, not prose.
            let text = try String(contentsOf: helpFolder.appendingPathComponent(file), encoding: .utf8)
                .replacingOccurrences(of: "<!--", with: "")
            XCTAssertFalse(text.contains("—"), "\(file) has an em dash")
            XCTAssertFalse(text.contains("!"), "\(file) has an exclamation mark")
            XCTAssertFalse(text.contains("**"), "\(file) has bold")
            for word in banned { XCTAssertFalse(text.lowercased().contains(word), "\(file) uses \(word)") }
            // Outside code spans a tilde would render as strikethrough: paths go in backticks.
            let outsideCode = text.components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            XCTAssertFalse(outsideCode.joined().contains("~"), "\(file) has a tilde outside a code span")
        }
    }
}
