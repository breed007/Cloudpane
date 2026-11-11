import CloudpaneCore
import Darwin
import PDFKit
import XCTest

/// The model as a first-time user with only Google Drive sees it: GoogleDrive-<email>
/// exists, every other provider is missing, and the inventory is empty. Each test has its
/// own fake home folder, database and defaults, so nothing touches the app's container.
@MainActor
final class GoogleDriveOnlyAppTests: XCTestCase {
    private var base: String!
    private var home: String { base + "/home" }
    private var suite: String!
    private var defaults: UserDefaults!
    private let account = "GoogleDrive-only.user@example.com"

    override func setUp() async throws {
        let created = NSTemporaryDirectory() + "cloudpane-app-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: created, withIntermediateDirectories: true)
        base = URL(fileURLWithPath: created).resolvingSymlinksInPath().path
        for folder in ["Library/CloudStorage/\(account)/My Drive", "Library/CloudStorage/\(account)/Shared drives",
                       "Downloads"] {
            try FileManager.default.createDirectory(atPath: home + "/" + folder, withIntermediateDirectories: true)
        }
        suite = "cloudpane-tests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suite)
        if let base { try? FileManager.default.removeItem(atPath: base) }
    }

    private func makeModel() -> AppModel {
        AppModel(defaults: defaults, homePath: home, databasePath: base + "/inventory.sqlite")
    }

    private func waitForScan(_ model: AppModel) async throws {
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(model.isScanning, "the scan did not finish in 10 seconds")
    }

    private func pdfText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        let attributes = document.documentAttributes ?? [:]
        XCTAssertEqual(attributes[PDFDocumentAttribute.producerAttribute] as? String, "Cloudpane")
        XCTAssertEqual(attributes[PDFDocumentAttribute.creatorAttribute] as? String, "Cloudpane",
                       "the test bundle is not the app, so no version is added")
        XCTAssertNil(attributes[PDFDocumentAttribute.authorAttribute])
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(raw.contains("Quartz") || raw.contains("macOS"), "the PDF names the system that made it")
        return try XCTUnwrap(document.string)
    }

    func testFreshInstallShowsOnlyGoogleDriveAndNoData() async throws {
        let model = makeModel()
        await model.start()
        XCTAssertNil(model.startupError)
        XCTAssertFalse(model.onboardingComplete)
        XCTAssertNil(model.snapshot, "an empty inventory has no scan, and none starts before onboarding")
        XCTAssertFalse(model.isScanning)

        let states = Dictionary(uniqueKeysWithValues: model.providerRows.map { ($0.id, $0.state) })
        XCTAssertEqual(states, ["google-drive": .installed, "icloud-drive": .missing, "dropbox": .missing,
                                "onedrive": .missing, "box": .missing])
        XCTAssertEqual(model.footprintBytes, 0)
        XCTAssertTrue(model.subscriptions.isEmpty)
        XCTAssertNil(model.grade)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertFalse(model.showsICloud, "no iCloud section on a Mac without iCloud Drive")

        await model.exportReport(hidePaths: true)
        XCTAssertNil(model.errorMessage)
        let export = try XCTUnwrap(model.lastExport)
        XCTAssertEqual(export.url.deletingLastPathComponent().path, home + "/Downloads")
        let text = try pdfText(export.url)
        XCTAssertTrue(text.contains("No complete scan yet"))
        XCTAssertFalse(text.contains("only.user"))
    }

    func testTheFirstScanAndItsReport() async throws {
        let drive = home + "/Library/CloudStorage/\(account)/My Drive/Projects"
        try FileManager.default.createDirectory(atPath: drive, withIntermediateDirectories: true)
        // A placeholder: logical size, nothing allocated.
        let path = drive + "/plan.key"
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: nil))
        XCTAssertEqual(truncate(path, 5_000_000), 0)

        let model = makeModel()
        await model.start()
        model.completeOnboarding()
        model.scan()
        try await waitForScan(model)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.snapshot?.status, .complete)
        XCTAssertEqual(model.totals.map(\.provider), ["google-drive"])
        XCTAssertEqual(model.cloudOnlyBytes, 5_000_000)
        await model.refreshGrade()
        XCTAssertEqual(model.grade?.overall?.letter, .F)

        await model.exportReport(hidePaths: true)
        let first = try XCTUnwrap(model.lastExport?.url)
        let hidden = try pdfText(first)
        XCTAssertTrue(hidden.contains("Google Drive folder 1"))
        for secret in ["only.user", "example.com", "Projects", "plan.key", home] {
            XCTAssertFalse(hidden.contains(secret), "the shared report contains \(secret)")
        }

        await model.exportReport(hidePaths: false)
        let second = try XCTUnwrap(model.lastExport?.url)
        XCTAssertNotEqual(first, second, "a second report never replaces the first")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(try pdfText(second).contains("Projects"))
    }
}
