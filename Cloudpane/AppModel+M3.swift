import AppKit
import CloudpaneCore
import Foundation

/// Subscriptions, the backup grade and backup locations.
extension AppModel {
    // MARK: - Plans

    func refreshPlans() async {
        guard let inventory else { return }
        do {
            subscriptions = try await inventory.subscriptions()
            let usage = try await inventory.usageHistory()
            let reported = try await inventory.reportedUsage()
            planReport = PlanReport.build(subscriptions: subscriptions, usage: usage, reported: reported,
                                          costOnly: scanChoices.costOnlyProviders)
            iCloudUsage = try await inventory.iCloudUsage()
            await refreshLatestCompleteRoots()
        } catch {
            errorMessage = "Cloudpane could not read your plans. \(error)"
        }
    }

    /// Saves a plan. Returns a message for the user when it could not be saved.
    func save(_ subscription: Subscription) async -> String? {
        guard let inventory else { return "The inventory is not open." }
        do {
            try await inventory.save(subscription)
            await refreshPlans()
            // A paid Box plan changes whether Box counts as versioned. Regrade in the
            // background so the plan sheet closes at once.
            regrade()
            return nil
        } catch let error as PlanError {
            return error.description
        } catch {
            return "Cloudpane could not save the plan. \(error)"
        }
    }

    func deleteSubscription(_ subscription: Subscription) async {
        guard let inventory, let id = subscription.id else { return }
        do {
            try await inventory.deleteSubscription(id: id)
            await refreshPlans()
            regrade()
        } catch {
            errorMessage = "Cloudpane could not delete the plan. \(error)"
        }
    }

    func subscription(for provider: String) -> Subscription? {
        subscriptions.first { $0.provider == provider }
    }

    func planRow(for provider: String) -> PlanRow? {
        planReport?.rows.first { $0.id == provider }
    }

    // MARK: - Grade

    /// Grades the latest complete scan. A canceled or interrupted scan is never graded:
    /// files it did not reach would read as missing copies.
    /// Starts a grade in the background. Any grade still running is canceled, and only the
    /// newest one's result is shown, so quick plan edits cannot leave a stale grade behind.
    func regrade() {
        Task { await refreshGrade() }
    }

    func refreshGrade() async {
        guard let inventory else { return }
        guard let facts = providerFacts else {
            grade = nil
            gradeNote = "The provider facts bundled with Cloudpane could not be read."
            return
        }
        let plans = subscriptions
        let current = snapshot?.id
        isRegrading = true
        do {
            let result = try await gradeRuns.run { () async throws -> GradeReport? in
                guard let latest = try await inventory.snapshots().last(where: { $0.status == .complete }) else {
                    return nil
                }
                return try await inventory.grade(snapshotID: latest.id, facts: facts, subscriptions: plans)
            }
            // Outer nil: a newer grade started meanwhile and will publish its own result.
            guard let outcome = result else { return }
            isRegrading = false
            if let report = outcome {
                grade = report
                gradeNote = report.snapshotID == current ? nil
                    : "The last scan did not finish, so this grade comes from the last complete scan."
            } else {
                grade = nil
                gradeNote = "The grade appears after a complete scan."
            }
        } catch {
            isRegrading = false
            grade = nil
            gradeNote = "Cloudpane could not grade the last scan. \(error)"
        }
    }

    // MARK: - Backup locations

    /// Backup roots for the next scan: connected locations, at the path their bookmark
    /// resolves to now (a disk can mount under a different name), with the user's labels.
    var connectedBackupRoots: [ScanRoot] {
        backupLocations.compactMap { location in
            guard let id = location.id, let url = backupAccess[id] else { return nil }
            return .backup(url, label: location.label, kind: location.kind, offsite: location.isOffsite)
        }
    }

    func restoreBackupLocations() async {
        guard let inventory else { return }
        do {
            backupLocations = try await inventory.backupLocations()
        } catch {
            errorMessage = "Cloudpane could not read its backup locations. \(error)"
            return
        }
        for location in backupLocations {
            guard let id = location.id, backupAccess[id] == nil else { continue }
            guard let (url, stale) = FolderAccess.startAccess(bookmark: location.bookmark) else {
                disconnectedBackups.insert(id)
                continue
            }
            backupAccess[id] = url
            disconnectedBackups.remove(id)
            // A stale bookmark still resolved; save a fresh one, as the folder grants do.
            if stale, let fresh = try? FolderAccess.bookmark(for: url) {
                var refreshed = location
                refreshed.bookmark = fresh
                _ = try? await inventory.save(refreshed)
            }
        }
    }

    /// Why a chosen folder cannot be a backup location, or nil when it can.
    func backupRefusal(for url: URL) -> String? {
        let root = ScanRoot.backup(url)
        if backupLocations.contains(where: { $0.path == root.path }) {
            return "\(root.name) is already a backup location."
        }
        refreshCatalog()
        return report?.backupRejectionReason(for: root)
    }

    /// Saves a read-only bookmark for the folder and adds it as a backup location.
    func addBackupLocation(url: URL, label: String, kind: BackupKind, offsite: Bool) async -> String? {
        guard let inventory else { return "The inventory is not open." }
        if let refusal = backupRefusal(for: url) { return refusal }
        do {
            let bookmark = try FolderAccess.bookmark(for: url)
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = BackupLocation(path: ScanRoot.backup(url).path,
                                          label: trimmed.isEmpty ? url.lastPathComponent : trimmed,
                                          kind: kind, isOffsite: offsite, bookmark: bookmark)
            let saved = try await inventory.save(location)
            if let id = saved.id, url.startAccessingSecurityScopedResource() {
                backupAccess[id] = url
            }
            backupLocations = try await inventory.backupLocations()
            updateWatching()
            return nil
        } catch {
            return "Cloudpane could not add this backup location. \(error.localizedDescription)"
        }
    }

    /// Stops access and deletes the location with its bookmark. Past scans keep what they saw.
    func removeBackupLocation(_ location: BackupLocation) async {
        guard let inventory, let id = location.id else { return }
        backupAccess.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        disconnectedBackups.remove(id)
        do {
            try await inventory.removeBackupLocation(id: id)
            backupLocations = try await inventory.backupLocations()
            updateWatching()
        } catch {
            errorMessage = "Cloudpane could not remove the backup location. \(error)"
        }
    }
}
