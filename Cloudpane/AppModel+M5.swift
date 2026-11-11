import AppKit
import CloudpaneCore
import Foundation
import UniformTypeIdentifiers

/// The iCloud figures a scan cannot read, and the PDF report.
extension AppModel {
    static let reportHidesPathsKey = "reportHidesPaths"

    // MARK: - iCloud

    /// Whether the Subscriptions view shows the iCloud section: iCloud Drive is on this Mac,
    /// or the user has already entered something for it.
    var showsICloud: Bool {
        let installed = report?.providers.contains { $0.rule.id == ProviderRule.iCloudDrive.id && $0.state != .missing }
        return installed == true || subscription(for: ProviderRule.iCloudDrive.id) != nil
            || iCloudUsage?.reportedTotal != nil || photosLibrary != nil
    }

    func refreshPhotosLibrary() async {
        guard let inventory else { return }
        photosLibrary = try? await inventory.photosLibrary()
    }

    /// Saves the total the user read from System Settings. Returns a message when it could
    /// not be saved.
    func setICloudTotal(bytes: Int64) async -> String? {
        guard let inventory else { return "The inventory is not open." }
        do {
            try await inventory.setReportedUsage(ReportedUsage(provider: ProviderRule.iCloudDrive.id, bytes: bytes))
            await refreshPlans()
            return nil
        } catch let error as PlanError {
            return error.description
        } catch {
            return "Cloudpane could not save the total. \(error)"
        }
    }

    func clearICloudTotal() async {
        guard let inventory else { return }
        try? await inventory.clearReportedUsage(provider: ProviderRule.iCloudDrive.id)
        await refreshPlans()
    }

    /// Asks the user for the Photos library with an open panel, keeps a read-only bookmark
    /// to it, and measures it. The panel is the only way the app gets access; nothing is
    /// read until the user picks the library.
    func choosePhotosLibrary() async {
        guard let inventory else { return }
        if FolderAccess.panelsDisabled {
            photosMessage = FolderAccess.panelsDisabledMessage
            return
        }
        let panel = NSOpenPanel()
        panel.message = "Choose your Photos library. Cloudpane reads only the size of the files inside it."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if let type = UTType("com.apple.photos.library") { panel.allowedContentTypes = [type] }
        panel.directoryURL = URL(fileURLWithPath: access.homePath + "/Pictures", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == PhotosLibrary.pathExtension else {
            photosMessage = PhotosLibraryError.notAPhotosLibrary.description
            return
        }
        do {
            let bookmark = try FolderAccess.bookmark(for: url)
            try await inventory.setPhotosLibrary(path: url.path, bookmark: bookmark)
            await refreshPhotosLibrary()
        } catch {
            photosMessage = "Cloudpane could not keep access to the Photos library. \(error.localizedDescription)"
            return
        }
        await measurePhotosLibrary()
    }

    /// Measures the chosen library again through its bookmark, off the main thread.
    func measurePhotosLibrary() async {
        guard let inventory, let record = photosLibrary, !isMeasuringPhotos else { return }
        guard let (url, stale) = FolderAccess.startAccess(bookmark: record.bookmark) else {
            photosMessage = "Cloudpane can no longer reach the Photos library. Choose it again."
            return
        }
        isMeasuringPhotos = true
        photosMessage = nil
        defer { isMeasuringPhotos = false }
        let result: Result<PhotosLibraryEstimate, Error> = await Task.detached(priority: .utility) {
            defer { url.stopAccessingSecurityScopedResource() }
            return Result { try PhotosLibrary.estimate(at: url) }
        }.value
        if stale, let fresh = try? FolderAccess.bookmark(for: url) {
            try? await inventory.setPhotosLibrary(path: url.path, bookmark: fresh)
        }
        switch result {
        case .success(let estimate):
            try? await inventory.recordPhotosEstimate(estimate)
            if estimate.unreadableCount > 0 {
                photosMessage = estimate.unreadableCount == 1
                    ? "1 item in the library could not be read and is left out of the estimate."
                    : "\(Format.count(estimate.unreadableCount)) items in the library could not be read and are left out of the estimate."
            }
        case .failure(let error as PhotosLibraryError):
            photosMessage = error.description
        case .failure(let error):
            photosMessage = "Cloudpane could not measure the Photos library. \(error.localizedDescription)"
        }
        await refreshPhotosLibrary()
        await refreshPlans()
    }

    func forgetPhotosLibrary() async {
        guard let inventory else { return }
        try? await inventory.clearPhotosLibrary()
        photosMessage = nil
        await refreshPhotosLibrary()
        await refreshPlans()
    }

    // MARK: - Report

    /// Builds the report for the latest complete scan and saves it as a PDF in ~/Downloads,
    /// under a name that never replaces an existing file.
    func exportReport(hidePaths: Bool) async {
        guard let inventory, !isExportingReport else { return }
        isExportingReport = true
        defer { isExportingReport = false }
        let document: ReportDocument
        do {
            document = ReportDocument.build(try await reportInput(inventory), options: ReportOptions(hidePaths: hidePaths))
        } catch {
            errorMessage = "Cloudpane could not gather the report. \(error)"
            return
        }
        let data = ReportPDF.render(document)
        let downloads = URL(fileURLWithPath: access.homePath + "/Downloads", isDirectory: true)
        let base = "Cloudpane report \(AppModel.fileStamp(Date()))"
        for _ in 0..<20 {
            let target = AppModel.unusedURL(in: downloads, base: base, ext: "pdf")
            do {
                try writeNewFile(data, to: target)
                lastExport = ExportResult(url: target, message: "Saved \(target.lastPathComponent) to Downloads.")
                return
            } catch ExportError.destinationExists {
                continue
            } catch {
                errorMessage = "Cloudpane could not save the report to Downloads. \(error.localizedDescription)"
                return
            }
        }
        errorMessage = "Cloudpane could not find a free name for the report in Downloads."
    }

    /// Everything the report needs, from the latest complete scan. Grade and duplicates
    /// already on screen are reused when they belong to that scan.
    func reportInput(_ inventory: Inventory) async throws -> ReportInput {
        refreshCatalog()
        var input = ReportInput(catalog: report, plans: planReport, iCloud: showsICloud ? iCloudUsage : nil)
        input.customProviders = scanChoices.customProviders
        guard let latest = try await inventory.snapshots().last(where: { $0.status == .complete }) else {
            return input
        }
        input.snapshot = latest
        input.totals = try await inventory.providerTotals(snapshotID: latest.id)
        input.roots = try await inventory.rootSummaries(snapshotID: latest.id)
        if let grade, grade.snapshotID == latest.id {
            input.grade = grade
        } else if let providerFacts {
            input.grade = try await inventory.grade(snapshotID: latest.id, facts: providerFacts, subscriptions: subscriptions)
        }
        if let duplicates, duplicates.snapshotID == latest.id {
            input.duplicates = duplicates
        } else {
            input.duplicates = try await inventory.duplicates(snapshotID: latest.id)
        }
        input.history = try await inventory.totalsHistory()
        return input
    }
}
