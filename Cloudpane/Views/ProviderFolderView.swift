import CloudpaneCore
import SwiftUI

/// One provider's top-level folders as a sortable table.
struct ProviderFolderView: View {
    @Environment(AppModel.self) private var model
    let provider: String
    @State private var rows: [FolderRow] = []
    @State private var order = [KeyPathComparator(\FolderRow.size, order: .reverse)]
    @State private var loaded = false
    @State private var selection: FolderRow.ID?
    @State private var hashing: FolderRow?

    struct FolderRow: Identifiable {
        let id: String
        let rootID: String
        let account: String
        let name: String
        let files: Int
        let size: Int64
        let cloudOnly: Int64
        var onMac: Int64 { size - cloudOnly }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            issues
            Table(rows, selection: $selection, sortOrder: $order) {
                // Always present: a conditional column needs macOS 14.4.
                TableColumn("Account", value: \.account)
                    .width(min: 90, ideal: 140)
                TableColumn("Folder", value: \.name) { row in
                    Text(row.name.isEmpty ? "Files at the top level" : row.name)
                        .foregroundStyle(row.name.isEmpty ? .secondary : .primary)
                }
                TableColumn("Files", value: \.files) { row in
                    Text(Format.count(row.files)).monospacedDigit()
                }
                .width(min: 60, ideal: 80)
                TableColumn("Size", value: \.size) { row in
                    Text(Format.bytes(row.size)).monospacedDigit()
                }
                .width(min: 70, ideal: 90)
                TableColumn("On this Mac", value: \.onMac) { row in
                    Text(Format.bytes(row.onMac)).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("Only in the cloud", value: \.cloudOnly) { row in
                    Text(Format.bytes(row.cloudOnly)).monospacedDigit()
                }
                .width(min: 100, ideal: 120)
            }
            .contextMenu(forSelectionType: FolderRow.ID.self) { ids in
                if let row = rows.first(where: { ids.contains($0.id) }) {
                    Button("Hash this folder") { hashing = row }
                        .disabled(model.isHashing)
                }
            }
            .overlay {
                if loaded && rows.isEmpty {
                    ContentUnavailableView("No folders", systemImage: "folder",
                                           description: Text("The last scan found nothing here."))
                }
            }
        }
        .navigationTitle(model.providerName(for: provider))
        .toolbar {
            Button("Hash this folder") { hashing = rows.first { $0.id == selection } }
                .disabled(selection == nil || model.isHashing)
                .help("Read the selected folder's files to find exact duplicates. Shows what will download first.")
        }
        .sheet(item: $hashing) { row in
            HashSheet(folder: HashFolder(rootID: row.rootID, folder: row.name),
                      title: row.name.isEmpty ? "the files at the top level" : row.name)
        }
        .onChange(of: order) { _, newOrder in rows.sort(using: newOrder) }
        .task(id: model.snapshot?.id) {
            let totals = await model.folderTotals(provider: provider)
            rows = totals.map {
                FolderRow(id: "\($0.rootID)/\($0.folder)", rootID: $0.rootID, account: model.accountName(forRoot: $0.rootID),
                          name: $0.folder, files: $0.files, size: $0.logicalBytes,
                          cloudOnly: $0.placeholderBytes)
            }
            rows.sort(using: order)
            loaded = true
        }
    }

    @ViewBuilder
    private var issues: some View {
        let affected = model.roots.filter { $0.root.provider == provider && ($0.errors > 0 || $0.wasInterrupted) }
        if !affected.isEmpty {
            VStack(spacing: 8) {
                ForEach(affected, id: \.root.id) { summary in
                    Banner(symbol: "eye.slash", tint: Theme.warning, title: summary.root.name,
                           message: message(for: summary))
                }
            }
            .padding(12)
        }
    }

    private func message(for summary: RootSummary) -> String {
        var parts: [String] = []
        if summary.errors > 0 {
            parts.append(summary.errors == 1 ? "1 item could not be read and is left out."
                         : "\(summary.errors) items could not be read and are left out.")
        }
        if summary.wasInterrupted { parts.append("The scan stopped before it finished this account.") }
        return parts.joined(separator: " ")
    }
}
