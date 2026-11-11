import CloudpaneCore
import Foundation

/// One account in the Providers view: a folder the catalog finds now or the latest complete
/// scan walked, or a provider with no folder on this Mac at all.
struct AccountRow: Identifiable, Sendable {
    /// The provider id plus the folder name, or the provider id alone for a provider with no
    /// folder.
    let id: String
    let provider: String
    let providerName: String
    /// The account folder's name, such as "OneDrive-Personal". Nil when not installed.
    let folderName: String?
    /// The account root's path, for excluding or forgetting it. Nil with no folder.
    let path: String?
    /// The account part of the folder name, when the provider puts one there.
    let account: String?
    let state: RootState
    /// Why the account is partial or unavailable, in the catalog's words.
    let reason: String?
    /// Logical bytes in the latest complete scan, for an account found on this Mac now.
    let usedBytes: Int64?
    /// The latest complete scan walked this folder, but the catalog no longer finds it.
    let isGone: Bool
    /// What that scan saw in a folder that is gone now.
    let lastSeenBytes: Int64?
    /// The user excluded this account from scans.
    let isExcluded: Bool
    /// A plan the user added with no folder on this Mac.
    let isCostOnly: Bool
    /// Other accounts of the same provider. Plans are one per provider, so they share it.
    let siblings: Int

    /// The account as the folder names it ("Personal", an email address). A provider with a
    /// fixed folder name and one account needs no label; with several, the folder name is it.
    var accountLabel: String? { account ?? (siblings > 0 ? folderName : nil) }
}

/// A provider and its accounts: built in, added by the user, or the folders under
/// Library/CloudStorage that match no provider ("Other cloud folders", which have no plan).
struct ProviderGroup: Identifiable, Sendable {
    let id: String
    let name: String
    /// Nil for other cloud folders: they have no plan.
    let provider: String?
    /// Set for a provider the user added.
    let custom: CustomProvider?
    let accounts: [AccountRow]

    var hasPlan: Bool { provider != nil }
    /// Space used by every account found now, in the latest complete scan.
    var usedBytes: Int64? {
        let used = accounts.compactMap(\.usedBytes)
        return used.isEmpty ? nil : used.reduce(0, +)
    }
}

extension AppModel {
    /// Every provider and account Cloudpane knows about: the built-in providers in table
    /// order (one with no folder still gets a row), then the providers the user added, then
    /// "Other cloud folders" for folders under Library/CloudStorage that match no provider
    /// and have no name, when there are any. A missing account the user chose to forget is
    /// left out until it is found again.
    var providerGroups: [ProviderGroup] {
        var groups = ProviderRule.defaultTable.map { rule in
            ProviderGroup(id: rule.id, name: rule.displayName, provider: rule.id, custom: nil,
                          accounts: accounts(for: rule))
        }
        for custom in scanChoices.customProviders {
            groups.append(ProviderGroup(id: custom.providerID, name: custom.name, provider: custom.providerID,
                                        custom: custom, accounts: accounts(for: custom)))
        }
        let other = otherFolders
        if !other.isEmpty {
            groups.append(ProviderGroup(id: ScanRoot.unrecognizedProvider, name: AppModel.unrecognizedName,
                                        provider: nil, custom: nil, accounts: other))
        }
        return groups
    }

    /// All account rows, in group order.
    var accountRows: [AccountRow] { providerGroups.flatMap(\.accounts) }

    private func accounts(for rule: ProviderRule) -> [AccountRow] {
        let status = report?.providers.first { $0.rule.id == rule.id }
        let detected = status?.roots ?? []
        let scanned = latestCompleteRoots.filter { $0.root.provider == rule.id && $0.root.kind == .provider }
        let names = visibleNames(detected: detected.map { ($0.folderName, $0.path) },
                                 scanned: scanned.map { ($0.root.name, $0.root.path) })
        guard !names.isEmpty else {
            return [AccountRow(id: rule.id, provider: rule.id, providerName: rule.displayName, folderName: nil,
                               path: nil, account: nil, state: status?.state ?? .missing,
                               reason: status.flatMap { $0.state == .installed ? nil : displayReason($0) },
                               usedBytes: nil, isGone: false, lastSeenBytes: nil, isExcluded: false,
                               isCostOnly: false, siblings: 0)]
        }
        return names.map { name in
            row(id: "\(rule.id)/\(name)", provider: rule.id, providerName: rule.displayName, name: name,
                detected: detected.first { $0.folderName == name }, scanned: scanned.first { $0.root.name == name },
                siblings: names.count - 1)
        }
    }

    private func accounts(for custom: CustomProvider) -> [AccountRow] {
        guard let folder = custom.folderName else {
            return [AccountRow(id: custom.providerID, provider: custom.providerID, providerName: custom.name,
                               folderName: nil, path: nil, account: nil, state: .missing, reason: nil,
                               usedBytes: nil, isGone: false, lastSeenBytes: nil, isExcluded: false,
                               isCostOnly: true, siblings: 0)]
        }
        let detected = report?.unrecognized.first { $0.folderName == folder }
        // Before the next scan the folder's numbers are still filed under other cloud folders.
        let scanned = latestCompleteRoots.first {
            $0.root.name == folder && ($0.root.provider == custom.providerID || $0.root.kind == .unrecognized)
        }
        if detected == nil, let path = scanned?.root.path, scanChoices.forgottenRoots.contains(path) { return [] }
        return [row(id: "\(custom.providerID)/\(folder)", provider: custom.providerID, providerName: custom.name,
                    name: folder, detected: detected, scanned: scanned, siblings: 0)]
    }

    private var otherFolders: [AccountRow] {
        let named = Set(scanChoices.customProviders.compactMap(\.folderName))
        let detected = (report?.unrecognized ?? []).filter { !named.contains($0.folderName) }
        let scanned = latestCompleteRoots.filter { $0.root.kind == .unrecognized && !named.contains($0.root.name) }
        let names = visibleNames(detected: detected.map { ($0.folderName, $0.path) },
                                 scanned: scanned.map { ($0.root.name, $0.root.path) })
        return names.map { name in
            row(id: "\(ScanRoot.unrecognizedProvider)/\(name)", provider: ScanRoot.unrecognizedProvider,
                providerName: AppModel.unrecognizedName, name: name,
                detected: detected.first { $0.folderName == name }, scanned: scanned.first { $0.root.name == name },
                // Each folder is its own label; none shares a plan.
                siblings: 1)
        }
    }

    /// Folder names found now, plus ones the last scan walked that are not forgotten.
    private func visibleNames(detected: [(String, String)], scanned: [(String, String)]) -> [String] {
        var names = detected.map(\.0)
        for (name, path) in scanned where !names.contains(name) && !scanChoices.forgottenRoots.contains(path) {
            names.append(name)
        }
        return names.sorted()
    }

    private func row(id: String, provider: String, providerName: String, name: String, detected: DetectedRoot?,
                     scanned: RootSummary?, siblings: Int) -> AccountRow {
        // Walked by the last scan but not found now: say so, and do not show its old size
        // as if it were current.
        let gone = detected == nil && scanned != nil
        let state = detected?.state ?? .missing
        let path = detected?.path ?? scanned?.root.path
        let excluded = path.map { scanChoices.isExcluded($0) } ?? false
        return AccountRow(id: id, provider: provider, providerName: providerName, folderName: name, path: path,
                          account: detected?.account ?? scanned?.root.account, state: state,
                          reason: state == .installed || gone ? nil : detected?.reason,
                          usedBytes: gone || excluded ? nil : scanned?.logicalBytes, isGone: gone,
                          lastSeenBytes: gone ? scanned?.logicalBytes : nil, isExcluded: excluded,
                          isCostOnly: false, siblings: siblings)
    }

    // MARK: - Loading

    /// Loads the per-account totals of the latest complete scan, for the Providers view.
    func refreshLatestCompleteRoots() async {
        guard let inventory else { return }
        guard let latest = try? await inventory.snapshots().last(where: { $0.status == .complete }) else {
            latestCompleteRoots = []
            return
        }
        latestCompleteRoots = (try? await inventory.rootSummaries(snapshotID: latest.id)) ?? []
    }

    /// Reloads the user's scan choices. A forgotten account found again is shown again.
    func refreshScanChoices() async {
        guard let inventory else { return }
        refreshCatalog()
        let found = Set((report?.providers.flatMap(\.roots) ?? []).map(\.path)
                        + (report?.unrecognized ?? []).map(\.path))
        _ = try? await inventory.reconcileForgotten(detectedRoots: found)
        if let choices = try? await inventory.scanChoices() { scanChoices = choices }
    }

    // MARK: - Actions

    /// From Overview: switches the sidebar to Providers and opens the plan editor there.
    func editPlanFromOverview(_ provider: String) {
        pendingPlanProvider = provider
        defaults.set(SidebarItem.providers.rawValue, forKey: SidebarItem.storageKey)
    }

    func removePlan(for provider: String) async {
        guard let plan = subscription(for: provider) else { return }
        await deleteSubscription(plan)
    }

    /// Excludes an account from scans, or includes it again, then scans so the latest
    /// snapshot matches. Older snapshots keep what they recorded.
    func setExcluded(_ excluded: Bool, rootPath: String) async {
        guard let inventory else { return }
        do {
            try await inventory.setExcluded(excluded, rootPath: rootPath)
        } catch {
            errorMessage = "Cloudpane could not change the account. \(error)"
            return
        }
        await choicesChanged(rescan: true)
    }

    /// Hides a missing account until it is found again.
    func forget(rootPath: String) async {
        guard let inventory else { return }
        try? await inventory.forget(rootPath: rootPath)
        await choicesChanged(rescan: false)
    }

    /// Adds a plan with no folder on this Mac. Returns the provider id, so its plan editor
    /// can open, or a message for the user.
    func addCostOnlyProvider(named name: String) async -> Result<String, PlanError> {
        await saveCustom(CustomProvider(name: name), rescan: false)
    }

    /// Names a folder under Library/CloudStorage that matches no provider, then scans so its
    /// files are filed under the name.
    func nameFolder(_ folderName: String, as name: String) async -> Result<String, PlanError> {
        await saveCustom(CustomProvider(name: name, folderName: folderName), rescan: true)
    }

    private func saveCustom(_ provider: CustomProvider, rescan: Bool) async -> Result<String, PlanError> {
        guard let inventory else { return .failure(.invalid(["The inventory is not open."])) }
        do {
            let saved = try await inventory.save(provider)
            await choicesChanged(rescan: rescan)
            return .success(saved.providerID)
        } catch let error as PlanError {
            return .failure(error)
        } catch {
            return .failure(.invalid(["Cloudpane could not save it. \(error)"]))
        }
    }

    /// Deletes a provider the user added and its plan. A named folder goes back to other
    /// cloud folders at the scan that follows.
    func removeCustomProvider(_ provider: CustomProvider) async {
        guard let inventory, let id = provider.id else { return }
        do {
            try await inventory.removeCustomProvider(id: id)
        } catch {
            errorMessage = "Cloudpane could not remove \(provider.name). \(error)"
            return
        }
        await choicesChanged(rescan: !provider.isCostOnly)
    }

    private func choicesChanged(rescan: Bool) async {
        await refreshScanChoices()
        await refreshPlans()
        regrade()
        updateWatching()
        if rescan && onboardingComplete { scan() }
    }
}
