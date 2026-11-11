import CloudpaneCore
import SwiftUI

/// Search by name across every provider. The only actions are Reveal in Finder and Copy
/// path; Cloudpane never opens, moves or downloads a file.
struct FileSearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [ResultRow] = []
    @State private var selection: ResultRow.ID?
    @State private var order = [KeyPathComparator(\ResultRow.name)]
    @State private var searched = false

    struct ResultRow: Identifiable {
        var id: String { path }
        let name: String
        let provider: String
        let path: String
        let displayPath: String
        let size: Int64
        let modified: Date
        let cloudOnly: Bool
        var status: String { cloudOnly ? "Only in the cloud" : "On this Mac" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(results, selection: $selection, sortOrder: $order) {
                TableColumn("Name", value: \.name)
                TableColumn("Provider", value: \.provider)
                    .width(min: 90, ideal: 110)
                TableColumn("Path", value: \.displayPath) { row in
                    Text(row.displayPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.path)
                }
                TableColumn("Size", value: \.size) { row in
                    Text(Format.bytes(row.size)).monospacedDigit()
                }
                .width(min: 70, ideal: 80)
                TableColumn("Modified", value: \.modified) { row in
                    Text(row.modified == .distantPast ? "Unknown" : Format.date(row.modified))
                }
                .width(min: 120, ideal: 150)
                TableColumn("Where the data is", value: \.status) { row in
                    Label(row.status, systemImage: row.cloudOnly ? "icloud" : "laptopcomputer")
                        .foregroundStyle(row.cloudOnly ? .secondary : .primary)
                }
                .width(min: 120, ideal: 140)
            }
            .contextMenu(forSelectionType: ResultRow.ID.self) { ids in
                if let path = ids.first {
                    Button("Reveal in Finder") { FileActions.revealInFinder(path) }
                    Button("Copy path") { FileActions.copyPath(path) }
                }
            }
            .overlay { emptyState }
            Divider()
            HStack {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reveal in Finder") { if let selection { FileActions.revealInFinder(selection) } }
                    .disabled(selection == nil)
                Button("Copy path") { if let selection { FileActions.copyPath(selection) } }
                    .disabled(selection == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .navigationTitle("File search")
        .searchable(text: $query, placement: .toolbar, prompt: "Search file names")
        .onChange(of: order) { _, newOrder in results.sort(using: newOrder) }
        .task(id: "\(query)|\(model.snapshot?.id ?? 0)") {
            // Wait for typing to pause before querying.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let records = await model.search(query)
            let home = model.access.homePath
            results = records.map { record in
                ResultRow(name: record.name, provider: model.providerName(for: record.provider),
                          path: record.path, displayPath: Format.path(record.path, home: home),
                          size: record.logicalSize ?? 0, modified: record.modified ?? .distantPast,
                          cloudOnly: record.isPlaceholder)
            }
            results.sort(using: order)
            searched = !query.trimmingCharacters(in: .whitespaces).isEmpty
            if let selection, !results.contains(where: { $0.id == selection }) { self.selection = nil }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.snapshot == nil {
            ContentUnavailableView("No scan yet", systemImage: "magnifyingglass",
                                   description: Text("Scan from Settings, then search here."))
        } else if !searched {
            ContentUnavailableView("Find a file", systemImage: "magnifyingglass",
                                   description: Text("Type part of a name to see every provider that holds it."))
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private var footer: String {
        guard searched else { return "" }
        let providers = Set(results.map(\.provider)).count
        let files = results.count == 1 ? "1 file" : "\(Format.count(results.count)) files"
        let where_ = providers == 1 ? "1 provider" : "\(providers) providers"
        return results.count >= 1_000 ? "Showing the first 1,000 matches" : "\(files) in \(where_)"
    }
}
