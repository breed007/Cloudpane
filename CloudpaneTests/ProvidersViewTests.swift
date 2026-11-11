import CloudpaneCore
import XCTest

/// The sidebar renames and the Providers view's account rows.
@MainActor
final class ProvidersViewTests: XCTestCase {
    private var base: String!
    private var home: String { base + "/home" }
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        let created = NSTemporaryDirectory() + "cloudpane-providers-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: created, withIntermediateDirectories: true)
        base = URL(fileURLWithPath: created).resolvingSymlinksInPath().path
        suite = "cloudpane-tests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suite)
        if let base { try? FileManager.default.removeItem(atPath: base) }
    }

    private func file(_ relative: String, size: Int) throws {
        let path = home + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data(count: size)))
    }

    func testOldSidebarValuesMapToTheirNewViews() {
        XCTAssertEqual(SidebarItem(stored: "footprint"), .overview)
        XCTAssertEqual(SidebarItem(stored: "whereIsIt"), .fileSearch)
        XCTAssertEqual(SidebarItem(stored: "grade"), .backupGrade)
        XCTAssertEqual(SidebarItem(stored: "subscriptions"), .providers)
        for unknown in ["", "nonsense", "Overview"] {
            XCTAssertEqual(SidebarItem(stored: unknown), .overview, unknown)
        }
        XCTAssertEqual(SidebarItem(stored: "providers"), .providers)
        XCTAssertEqual(SidebarItem(stored: "backupGrade"), .backupGrade)
        XCTAssertEqual(SidebarItem.allCases.map(\.title),
                       ["Overview", "File search", "Duplicates", "Backup grade", "Providers", "History", "Settings"])
    }

    func testEveryAccountGetsARowAndAccountsShareTheProvidersPlan() async throws {
        try file("Library/CloudStorage/OneDrive-Personal/Documents/a.docx", size: 3_000)
        try file("Library/CloudStorage/OneDrive-Contoso/Shared/b.pptx", size: 5_000)
        try file("Library/CloudStorage/Dropbox/c.txt", size: 1_000)
        try file("Library/CloudStorage/SomeCloud-x/d.bin", size: 700)
        let model = AppModel(defaults: defaults, homePath: home, databasePath: base + "/inventory.sqlite")
        await model.start()
        model.completeOnboarding()
        model.scan()
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(model.isScanning)
        let message = await model.save(Subscription(provider: "onedrive", name: "Microsoft 365 Personal",
                                                    price: Decimal(string: "9.99")!, currency: "USD",
                                                    planBytes: 1_000_000_000_000))
        XCTAssertNil(message)

        let groups = model.providerGroups
        XCTAssertEqual(groups.map(\.id), ["icloud-drive", "dropbox", "google-drive", "onedrive", "box", "unrecognized"])
        XCTAssertEqual(model.accountRows.map(\.id),
                       ["icloud-drive", "dropbox/Dropbox", "google-drive", "onedrive/OneDrive-Contoso",
                        "onedrive/OneDrive-Personal", "box", "unrecognized/SomeCloud-x"])
        let oneDrive = try XCTUnwrap(groups.first { $0.id == "onedrive" })
        XCTAssertEqual(oneDrive.usedBytes, 8_000, "the provider row shows the plan once, for both accounts")
        let contoso = try XCTUnwrap(oneDrive.accounts.first { $0.folderName == "OneDrive-Contoso" })
        XCTAssertEqual(contoso.accountLabel, "Contoso")
        XCTAssertEqual(contoso.state, .installed)
        XCTAssertEqual(contoso.usedBytes, 5_000)
        XCTAssertEqual(contoso.siblings, 1)
        let dropbox = try XCTUnwrap(groups.first { $0.id == "dropbox" }?.accounts.first)
        XCTAssertNil(dropbox.accountLabel, "a single fixed-name folder needs no label")
        XCTAssertEqual(groups.first { $0.id == "box" }?.accounts.first?.state, .missing)

        // Other cloud folders: listed with their size, and no plan.
        let other = try XCTUnwrap(groups.last)
        XCTAssertFalse(other.hasPlan)
        XCTAssertEqual(other.name, "Other cloud folders")
        XCTAssertEqual(other.accounts.first?.accountLabel, "SomeCloud-x")
        XCTAssertEqual(other.accounts.first?.usedBytes, 700)

        XCTAssertEqual(model.planRow(for: "onedrive")?.usedBytes, 8_000)
        XCTAssertNil(model.subscription(for: "dropbox"), "a row with no plan offers Add plan")

        // An account the last scan walked but that is gone now: no stale size as current.
        try FileManager.default.removeItem(atPath: home + "/Library/CloudStorage/OneDrive-Contoso")
        model.refreshCatalog()
        let gone = try XCTUnwrap(model.accountRows.first { $0.id == "onedrive/OneDrive-Contoso" })
        XCTAssertTrue(gone.isGone)
        XCTAssertNil(gone.usedBytes)
        XCTAssertEqual(gone.lastSeenBytes, 5_000)
    }

    private func scanned(_ model: AppModel) async throws {
        model.scan()
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(model.isScanning)
    }

    func testAddedProvidersExclusionsAndForgottenAccounts() async throws {
        try file("Library/CloudStorage/OneDrive-Personal/Documents/a.docx", size: 3_000)
        try file("Library/CloudStorage/OneDrive-Contoso/Shared/b.pptx", size: 5_000)
        try file("Library/CloudStorage/Dropbox/c.txt", size: 1_000)
        try file("Library/CloudStorage/SomeCloud-x/d.bin", size: 700)
        let model = AppModel(defaults: defaults, homePath: home, databasePath: base + "/inventory.sqlite")
        await model.start()
        model.completeOnboarding()
        try await scanned(model)

        // A plan with no folder: its cost counts, and nothing else about it.
        guard case .success(let vault) = await model.addCostOnlyProvider(named: "Photo vault") else {
            return XCTFail("not added")
        }
        let saved = await model.save(Subscription(provider: vault, name: "Vault", price: 8, currency: "USD",
                                                  planBytes: 5_000_000_000_000))
        XCTAssertNil(saved)
        let vaultRow = try XCTUnwrap(model.accountRows.first { $0.provider == vault })
        XCTAssertTrue(vaultRow.isCostOnly)
        XCTAssertNil(vaultRow.usedBytes)
        XCTAssertEqual(model.planRow(for: vault)?.isCostOnly, true)
        XCTAssertNil(model.planRow(for: vault)?.headroomBytes)
        XCTAssertEqual(model.planReport?.personalTotal.totals, [Money(amount: 8, currency: "USD")])
        XCTAssertEqual(model.providerName(for: vault), "Photo vault")
        XCTAssertTrue(model.providerRows.contains { $0.id == vault && $0.isCostOnly }, "listed in Overview too")

        // A named folder becomes its own provider after the scan that follows.
        guard case .success(let sync) = await model.nameFolder("SomeCloud-x", as: "SomeCloud") else {
            return XCTFail("not named")
        }
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
        let syncGroup = try XCTUnwrap(model.providerGroups.first { $0.id == sync })
        XCTAssertEqual(syncGroup.name, "SomeCloud")
        XCTAssertEqual(syncGroup.usedBytes, 700)
        XCTAssertNil(model.providerGroups.first { $0.id == ScanRoot.unrecognizedProvider }, "no longer an other folder")
        XCTAssertEqual(model.totals.first { $0.provider == sync }?.providerName, "SomeCloud")

        // Excluding an account rescans without it; its row stays, marked.
        let contosoPath = try XCTUnwrap(model.accountRows.first { $0.folderName == "OneDrive-Contoso" }?.path)
        await model.setExcluded(true, rootPath: contosoPath)
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
        let excluded = try XCTUnwrap(model.accountRows.first { $0.folderName == "OneDrive-Contoso" })
        XCTAssertTrue(excluded.isExcluded)
        XCTAssertNil(excluded.usedBytes)
        XCTAssertEqual(model.totals.first { $0.provider == "onedrive" }?.logicalBytes, 3_000, "left out of the totals")
        await model.setExcluded(false, rootPath: contosoPath)
        for _ in 0..<200 where model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(model.totals.first { $0.provider == "onedrive" }?.logicalBytes, 8_000, "scanned again on include")

        // A missing account can be forgotten, and comes back when found again.
        let personal = home + "/Library/CloudStorage/OneDrive-Personal"
        try FileManager.default.moveItem(atPath: personal, toPath: base + "/parked")
        model.refreshCatalog()
        let gone = try XCTUnwrap(model.accountRows.first { $0.folderName == "OneDrive-Personal" })
        XCTAssertTrue(gone.isGone)
        await model.forget(rootPath: try XCTUnwrap(gone.path))
        XCTAssertNil(model.accountRows.first { $0.folderName == "OneDrive-Personal" })
        try FileManager.default.moveItem(atPath: base + "/parked", toPath: personal)
        await model.refreshScanChoices()
        XCTAssertNotNil(model.accountRows.first { $0.folderName == "OneDrive-Personal" && !$0.isGone })
        XCTAssertTrue(model.scanChoices.forgottenRoots.isEmpty)

        // Removing a provider the user added removes its plan too.
        let custom = try XCTUnwrap(model.scanChoices.customProviders.first { $0.providerID == vault })
        await model.removeCustomProvider(custom)
        XCTAssertNil(model.subscription(for: vault))
        XCTAssertNil(model.providerGroups.first { $0.id == vault })
    }

    /// A scan asked for while one runs (as excluding or naming does) runs right after it.
    func testAScanAskedForDuringAScanRunsAfterIt() async throws {
        try file("Library/CloudStorage/Dropbox/c.txt", size: 1_000)
        let model = AppModel(defaults: defaults, homePath: home, databasePath: base + "/inventory.sqlite")
        await model.start()
        model.completeOnboarding()
        model.scan()
        XCTAssertTrue(model.isScanning)
        model.scan()
        XCTAssertTrue(model.pendingFullRescan, "queued, not dropped")
        for _ in 0..<400 where model.isScanning || model.pendingFullRescan {
            try await Task.sleep(for: .milliseconds(50))
        }
        let snapshots = try await XCTUnwrap(model.inventory).snapshots()
        XCTAssertEqual(snapshots.count, 2, "the queued scan ran after the first")

        // Stopping a scan also drops a queued one.
        model.scan()
        model.scan()
        model.cancelScan()
        XCTAssertFalse(model.pendingFullRescan)
        for _ in 0..<400 where model.isScanning { try await Task.sleep(for: .milliseconds(50)) }
    }

    func testOverviewOpensTheEditorInProviders() async throws {
        let model = AppModel(defaults: defaults, homePath: home, databasePath: base + "/inventory.sqlite")
        model.editPlanFromOverview("dropbox")
        XCTAssertEqual(model.pendingPlanProvider, "dropbox")
        XCTAssertEqual(defaults.string(forKey: SidebarItem.storageKey), "providers")
    }
}
