import CloudpaneCore
import SwiftUI

/// Overview: the headline total, one bar per provider, the file-type breakdown, and banners
/// for anything the scan could not fully see. Read-only apart from each provider's plan
/// button, which opens the plan in Providers.
struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    banners
                    headline
                    providers
                    types
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Overview")
            .navigationDestination(for: String.self) { provider in
                ProviderFolderView(provider: provider)
            }
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var banners: some View {
        if let snapshot = model.snapshot, snapshot.status != .complete {
            Banner(symbol: "exclamationmark.triangle", tint: Theme.warning,
                   title: "This scan did not finish",
                   message: unfinishedMessage(snapshot.status))
        }
        ForEach(model.providerRows.filter { $0.state == .partial || $0.state == .unavailable }) { row in
            Banner(symbol: row.state == .partial ? "circle.lefthalf.filled" : "lock",
                   tint: Theme.warning,
                   title: row.state == .partial ? "\(row.name): partial view" : "\(row.name): unavailable",
                   message: row.reason ?? "", learnMore: HelpTopics.partialView)
        }
        let missing = model.providerRows.filter { $0.state == .missing }.map(\.name)
        if !missing.isEmpty {
            Banner(symbol: "minus.circle", tint: .secondary,
                   title: "Not installed: \(missing.joined(separator: ", "))",
                   message: "Cloudpane found no folder for these on this Mac. When you add one, scan again.")
        }
        let unreadable = model.roots.reduce(0) { $0 + $1.errors }
        if unreadable > 0 {
            Banner(symbol: "eye.slash", tint: Theme.warning,
                   title: unreadable == 1 ? "1 item could not be read" : "\(unreadable) items could not be read",
                   message: "The totals leave them out. Open a provider to see which account they belong to.")
        }
    }

    private func unfinishedMessage(_ status: SnapshotStatus) -> String {
        let cause: String
        switch status {
        case .canceled: cause = "The last scan was stopped before it finished."
        case .interrupted: cause = "The last scan was interrupted, most likely because Cloudpane quit while it ran."
        case .failed: cause = "The last scan stopped because of an error."
        case .running, .complete: cause = "The last scan is still in progress."
        }
        return cause + " The totals cover only what it reached. Scan again for the full picture."
    }

    // MARK: - Headline

    private var headline: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total in cloud storage")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(model.snapshot == nil ? "No scan yet" : Format.bytes(model.footprintBytes))
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                if model.snapshot != nil {
                    Text("\(Format.bytes(model.cloudOnlyBytes)) of it is only in the cloud")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly cost")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let personal = model.planReport?.personalTotal, !personal.isEmpty {
                    Text(Format.totals(personal))
                        .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    Text(personal.isMixed ? "Each currency totaled on its own, not converted"
                                          : "Bundled and inactive plans not included")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not set")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("Add your plans in Providers")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let snapshot = model.snapshot {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Last scan")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(Format.date(snapshot.finishedAt ?? snapshot.startedAt))
                        .font(.callout)
                }
            }
        }
    }

    // MARK: - Providers

    private var providers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By provider").font(.headline)
            let rows = model.providerRows
            let largest = max(rows.map(\.logicalBytes).max() ?? 0, 1)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        if row.hasData {
                            NavigationLink(value: row.id) {
                                ProviderBarRow(row: row, largest: largest,
                                               planBytes: model.subscription(for: row.id)?.planBytes)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ProviderBarRow(row: row, largest: largest,
                                           planBytes: model.subscription(for: row.id)?.planBytes)
                        }
                        // The one action here: plans are managed in Providers.
                        if row.id != ScanRoot.unrecognizedProvider {
                            Button(model.subscription(for: row.id) == nil ? "Add plan" : "Edit plan") {
                                model.editPlanFromOverview(row.id)
                            }
                            .controlSize(.small)
                            .frame(width: 78, alignment: .trailing)
                        } else {
                            Color.clear.frame(width: 78, height: 1)
                        }
                    }
                    if row.id != rows.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 16) {
                legend(color: Theme.accent, text: "On this Mac")
                legend(color: Theme.cloudOnly, text: "Only in the cloud")
                Text("A bar shows use against the plan size when one is set, and compares providers otherwise.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(text)
        }
    }

    // MARK: - Types

    @ViewBuilder
    private var types: some View {
        if !model.types.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("By file type").font(.headline)
                let largest = max(model.types.map(\.logicalBytes).max() ?? 0, 1)
                VStack(spacing: 8) {
                    ForEach(model.types, id: \.key) { type in
                        HStack(spacing: 12) {
                            Text(TypeNames.name(for: type.key))
                                .frame(width: 120, alignment: .leading)
                            UsageBar(total: type.logicalBytes, cloudOnly: 0, scale: largest)
                                .frame(height: 8)
                            Text(Format.bytes(type.logicalBytes))
                                .font(.callout.monospacedDigit())
                                .frame(width: 90, alignment: .trailing)
                            Text(Format.count(type.files, "file"))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .trailing)
                        }
                    }
                }
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct ProviderBarRow: View {
    let row: ProviderRow
    let largest: Int64
    var planBytes: Int64?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 200, alignment: .leading)
            if row.hasData {
                UsageBar(total: row.logicalBytes, cloudOnly: row.cloudOnlyBytes, scale: planBytes ?? largest)
                    .frame(height: 10)
            } else {
                Text(stateText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.hasData ? Format.bytes(row.logicalBytes) : "")
                    .font(.callout.monospacedDigit())
                Text(planLabel)
                    .font(.caption)
                    .foregroundStyle(isOverPlan ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(.tertiary))
            }
            .frame(width: 110, alignment: .trailing)
            // Only rows with data open a folder list.
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(row.hasData ? 1 : 0)
                .accessibilityHidden(!row.hasData)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Rows without data show their state once, in the bar's place, so the subtitle stays empty.
    private var subtitle: String {
        if !row.hasData { return "" }
        let accounts = row.accounts > 1 ? "\(row.accounts) accounts, " : ""
        let excluded = row.excludedAccounts > 0 ? ", \(row.excludedAccounts) excluded" : ""
        return accounts + Format.count(row.files, "file") + excluded
    }

    private var isOverPlan: Bool { planBytes.map { row.logicalBytes > $0 } ?? false }

    private var planLabel: String {
        // Folders that match no provider have no plan to set.
        if row.id == ScanRoot.unrecognizedProvider { return "" }
        if row.isCostOnly { return "" }
        guard let planBytes else { return "Plan size not set" }
        return isOverPlan ? "Over the \(Format.bytes(planBytes)) plan" : "of \(Format.bytes(planBytes)) plan"
    }

    private var stateText: String {
        if row.isCostOnly { return "Plan only, not on this Mac" }
        if row.isExcluded { return "Excluded from scans" }
        switch row.state {
        case .missing: return "Not installed"
        case .unavailable: return "Unavailable"
        case .partial: return "Partial view"
        case .installed: return "Empty"
        }
    }
}

/// A bar scaled against the largest value in its group, split into the part on this Mac
/// and the part only in the cloud.
struct UsageBar: View {
    let total: Int64
    let cloudOnly: Int64
    let scale: Int64

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Capped at the full width: a provider over its plan fills the bar.
            let full = width * CGFloat(min(Double(total) / Double(max(scale, 1)), 1))
            let cloud = full * CGFloat(Double(cloudOnly) / Double(max(total, 1)))
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.accent).frame(width: max(full - cloud, 0))
                    Rectangle().fill(Theme.cloudOnly).frame(width: cloud)
                }
                .frame(width: max(full, total > 0 ? 3 : 0), alignment: .leading)
                .clipShape(Capsule())
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(Format.bytes(total)), \(Format.bytes(cloudOnly)) only in the cloud")
    }
}

struct Banner: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    /// A help topic for a Learn more link under the message.
    var learnMore: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let learnMore {
                    LearnMoreLink(topic: learnMore).font(.callout)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

enum TypeNames {
    static func name(for key: String) -> String {
        switch FileCategory(rawValue: key) {
        case .application: return "Apps"
        case .image: return "Images"
        case .video: return "Video"
        case .audio: return "Audio"
        case .archive: return "Archives"
        case .code: return "Code"
        case .document: return "Documents"
        case .other, .none: return "Other"
        }
    }
}
