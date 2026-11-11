import CloudpaneCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppModel.scanOnLaunchKey) private var scanOnLaunch = true
    @AppStorage(AppModel.watchKey) private var watch = true
    @AppStorage(AppModel.reportHidesPathsKey) private var reportHidesPaths = true
    @State private var confirmingReset = false
    @State private var exporting = false
    @State private var pendingBackup: PendingBackup?
    @State private var backupMessage: String?
    @State private var removing: BackupLocation?

    var body: some View {
        Form {
            Section("Scanning") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last scan")
                        Text(lastScan)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isScanning {
                        Button("Stop scan") { model.cancelScan() }
                    } else {
                        Button("Scan now") { model.scan() }
                    }
                }
                Toggle("Scan when Cloudpane opens", isOn: $scanOnLaunch)
                Toggle("Watch for changes and update the inventory", isOn: $watch)
                    .onChange(of: watch) { _, _ in model.updateWatching() }
                UpdateStatusLine()
            }

            Section {
                ForEach(GrantedFolder.allCases) { folder in
                    FolderGrantRow(folder: folder)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
                HStack {
                    Text("Forget both folders and return to the first-run screens. Past scans are kept.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset folder access") { confirmingReset = true }
                }
            } header: {
                Text("Folder access")
            } footer: {
                Text("Access is read-only. Cloudpane asks for these two folders and nothing else in your Library.")
            }

            Section {
                if model.hashFolders.isEmpty {
                    Text("No folders are hashed. To hash one, open a provider in Overview, select a folder and choose Hash this folder.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(model.hashFolders) { folder in
                        HStack {
                            Text("\(model.accountName(forRoot: folder.rootID)): \(folder.folder.isEmpty ? "files at the top level" : folder.folder)")
                            Spacer()
                            Button("Stop hashing this folder") { Task { await model.stopHashingFolder(folder) } }
                        }
                    }
                }
                if let message = model.hashMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Hashing")
            } footer: {
                Text("In a hashed folder, new or changed files already on this Mac are hashed automatically. Files only in the cloud are hashed only when you choose Hash this folder again and confirm the download.")
            }

            Section {
                ForEach(model.backupLocations) { location in
                    BackupLocationRow(location: location,
                                      connected: location.id.map { model.backupAccess[$0] != nil } ?? false) {
                        removing = location
                    }
                }
                HStack {
                    Text(model.backupLocations.isEmpty
                         ? "No backup locations yet. Without one, no folder can grade above C."
                         : "Scan again after adding or connecting a backup location.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add a backup location") { chooseBackup() }
                }
                if let backupMessage {
                    Text(backupMessage)
                        .font(.callout)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Backup locations")
            } footer: {
                Text("A backup location is a Time Machine backup, a folder on an external drive, or a NAS share. Cloudpane reads it, read-only, to see which cloud files have a real backup. A folder inside a cloud provider's synced folder cannot be one: sync is not backup.")
            }

            Section {
                HStack {
                    Text("Export the last scan")
                    Spacer()
                    ForEach(ExportFormat.allCases) { format in
                        Button("Export \(format.title)") {
                            exporting = true
                            Task {
                                await model.export(format)
                                exporting = false
                            }
                        }
                    }
                }
                .disabled(model.snapshot == nil || exporting)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Report")
                        Text("A PDF summary: footprint, plans, the backup grade, single points of failure, duplicates and history.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Export PDF") {
                        Task { await model.exportReport(hidePaths: reportHidesPaths) }
                    }
                    .disabled(model.isExportingReport || model.inventory == nil)
                }
                Toggle(isOn: $reportHidesPaths) {
                    Text("Hide file paths and names in the report")
                    Text("Plan names you typed are included.")
                }
                .help("Leaves out file paths, file and folder names, account names and backup labels. Plan names you typed are included.")
                LearnMoreLink(topic: HelpTopics.pdfExport, title: "Learn more about reports").font(.callout)
                if let export = model.lastExport {
                    HStack {
                        Text(export.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reveal in Finder") { FileActions.revealInFinder(export.url.path) }
                    }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Exports and reports go to your Downloads folder and never replace an existing file. With names hidden, the report keeps the figures and leaves out file paths, file and folder names, account names and backup labels; plan names you typed are included. A CSV file adds an apostrophe in front of names that start with =, +, - or @, so a spreadsheet cannot run them as formulas.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(item: $pendingBackup) { pending in
            BackupLabelSheet(url: pending.url) { message in backupMessage = message }
        }
        .confirmationDialog("Remove \(removing?.label ?? "this backup location")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove backup location", role: .destructive) {
                if let location = removing { Task { await model.removeBackupLocation(location) } }
                removing = nil
            }
        } message: {
            Text("Cloudpane forgets this location and its access. Your backup is not touched. Past scans keep what they saw.")
        }
        .confirmationDialog("Reset folder access?", isPresented: $confirmingReset) {
            Button("Reset folder access", role: .destructive) { model.resetAccess() }
        } message: {
            Text("Cloudpane will stop reading both folders until you grant them again.")
        }
    }

    private func chooseBackup() {
        backupMessage = nil
        guard let url = FolderAccess.chooseBackupFolder() else { return }
        if let refusal = model.backupRefusal(for: url) {
            backupMessage = refusal
        } else {
            pendingBackup = PendingBackup(url: url)
        }
    }

    private var lastScan: String {
        guard let snapshot = model.snapshot else { return "No scan yet" }
        let when = Format.date(snapshot.finishedAt ?? snapshot.startedAt)
        switch snapshot.status {
        case .complete: return when
        case .canceled: return "\(when), stopped before it finished"
        case .interrupted: return "\(when), interrupted"
        case .failed: return "\(when), failed"
        case .running: return "Running"
        }
    }
}

/// A folder chosen in the open panel, waiting for its label.
struct PendingBackup: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct BackupLocationRow: View {
    let location: BackupLocation
    let connected: Bool
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: connected ? "externaldrive.fill" : "externaldrive.badge.xmark")
                .foregroundStyle(connected ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(location.label).font(.headline)
                Text("\(location.kind.displayName), \(location.isOffsite ? "off-site" : "on-site")"
                     + (connected ? "" : ". Not connected, so the next scan leaves it out."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(location.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Remove", action: remove)
        }
        .padding(.vertical, 4)
    }
}

/// Labels a chosen backup folder: a name, what it is, and whether it is kept off-site.
/// Cloudpane cannot tell where a disk or a NAS physically sits, so the user says.
struct BackupLabelSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let report: (String?) -> Void
    @State private var label = ""
    @State private var kind = BackupKind.externalDrive
    @State private var offsite = false
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a backup location").font(.title2.weight(.semibold))
            Text(url.path)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Form {
                TextField("Name", text: $label, prompt: Text(url.lastPathComponent))
                Picker("Kind", selection: $kind) {
                    ForEach(BackupKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Where it is kept", selection: $offsite) {
                    Text("On-site, in the home").tag(false)
                    Text("Off-site, away from the home").tag(true)
                }
                .pickerStyle(.radioGroup)
            }
            Text("A disk you take to an office or a relative's home counts as off-site. A NAS on your home network does not.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add backup location") {
                    saving = true
                    Task {
                        let message = await model.addBackupLocation(url: url, label: label, kind: kind, offsite: offsite)
                        report(message)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saving)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if url.path.contains("Backups.backupdb") || url.lastPathComponent.hasSuffix(".backup") { kind = .timeMachine }
        }
    }
}
