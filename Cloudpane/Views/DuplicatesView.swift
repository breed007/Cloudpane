import CloudpaneCore
import SwiftUI

/// Duplicate groups in three tiers, largest reclaimable first. Nothing is ever deleted or
/// merged; the only actions are Reveal in Finder and Copy path.
struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @State private var tier: DuplicateTier?
    @State private var expanded: Set<String> = []

    var body: some View {
        Group {
            if let report = model.duplicates {
                content(report)
            } else if model.isFindingDuplicates {
                ProgressView("Looking for duplicates")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No scan yet", systemImage: "doc.on.doc",
                                       description: Text("Duplicates appear after a complete scan."))
            }
        }
        .navigationTitle("Duplicates")
    }

    private func content(_ report: DuplicateReport) -> some View {
        let groups = report.groups.filter { tier == nil || $0.tier == tier }
        // A ScrollView like the other views: a List of disclosure groups inside the split
        // view's detail blanked the whole window, sidebar included.
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(report)
                    .padding(20)
                Divider()
                if groups.isEmpty {
                    ContentUnavailableView("No duplicates", systemImage: "checkmark.circle",
                                           description: Text("No files in your cloud folders match each other in this tier."))
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                toggle(group.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: expanded.contains(group.id) ? "chevron.down" : "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 12)
                                    GroupRow(group: group)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(group.name), \(expanded.contains(group.id) ? "collapse" : "expand")")
                            if expanded.contains(group.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(group.copies) { CopyRow(copy: $0) }
                                    if !group.backupCopies.isEmpty {
                                        Text("Also in backups, not counted")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .padding(.top, 4)
                                        ForEach(group.backupCopies) { CopyRow(copy: $0) }
                                    }
                                }
                                .padding(.leading, 20)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        Divider().padding(.leading, 20)
                    }
                    if report.totalGroups > report.groups.count {
                        Text("Showing the \(Format.count(report.groups.count)) groups with the most to reclaim of \(Format.count(report.totalGroups)).")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ report: DuplicateReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 28) {
                ForEach(report.totals, id: \.tier) { total in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(total.tier.title).font(.callout).foregroundStyle(.secondary)
                        Text(Format.bytes(total.reclaimableBytes))
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text("\(Format.count(total.groups)) \(total.groups == 1 ? "group" : "groups")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("Tier", selection: $tier) {
                    Text("All tiers").tag(DuplicateTier?.none)
                    ForEach(DuplicateTier.allCases, id: \.self) { Text($0.title).tag(DuplicateTier?.some($0)) }
                }
                .frame(width: 160)
            }
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isFindingDuplicates {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private var explanation: String {
        "Exact groups have identical contents, which needs hashing. Strong groups share a name, a size and a date within 2 seconds. Weak groups share only a size of at least 1 MB, so check them before acting. Cloudpane never deletes or merges anything; reveal the copies in Finder and decide yourself."
    }

}

private struct GroupRow: View {
    let group: DuplicateGroup

    var body: some View {
        HStack(spacing: 12) {
            Text(group.tier.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.accent.opacity(group.tier == .exact ? 0.45 : group.tier == .strong ? 0.25 : 0.12),
                            in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).lineLimit(1)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(group.reclaimableBytes)).monospacedDigit()
                Text("could be reclaimed").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        var parts = ["\(group.copies.count) copies of \(Format.bytes(group.size))"]
        let locations = Set(group.copies.map(\.locationName)).sorted()
        parts.append("in " + locations.joined(separator: ", "))
        if group.placeholderCount > 0 {
            parts.append(group.placeholderCount == group.copies.count ? "all only in the cloud"
                         : "\(group.placeholderCount) only in the cloud")
        }
        return parts.joined(separator: ", ")
    }
}

private struct CopyRow: View {
    @Environment(AppModel.self) private var model
    let copy: DuplicateCopy

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: copy.isBackup ? "externaldrive" : copy.record.isPlaceholder ? "icloud" : "laptopcomputer")
                .foregroundStyle(.secondary)
                .help(copy.isBackup ? "In a backup" : copy.record.isPlaceholder ? "Only in the cloud" : "On this Mac")
            VStack(alignment: .leading, spacing: 1) {
                Text(copy.locationName).font(.callout)
                Text(Format.path(copy.record.path, home: model.access.homePath))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(copy.record.isPlaceholder ? "Only in the cloud" : "On this Mac")
                .font(.caption).foregroundStyle(.secondary)
            Button("Reveal in Finder") { FileActions.revealInFinder(copy.record.path) }
                .buttonStyle(.borderless)
            Button("Copy path") { FileActions.copyPath(copy.record.path) }
                .buttonStyle(.borderless)
        }
        .contextMenu {
            Button("Reveal in Finder") { FileActions.revealInFinder(copy.record.path) }
            Button("Copy path") { FileActions.copyPath(copy.record.path) }
        }
    }
}
