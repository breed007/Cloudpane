import CloudpaneCore
import SwiftUI

/// Column widths of the accounts and plans table in its wide layout. The account column
/// takes what is left, never less than `account`. When the wide layout does not fit, the
/// table switches to the compact one (ProvidersView).
enum PlanColumns {
    static let account: CGFloat = 116
    static let status: CGFloat = 80
    static let used: CGFloat = 72
    static let plan: CGFloat = 128
    static let month: CGFloat = 80
    static let room: CGFloat = 92
    static let button: CGFloat = 72
    static let menu: CGFloat = 26
    static let spacing: CGFloat = 8
}

struct PlanTableHeader: View {
    var body: some View {
        HStack(spacing: PlanColumns.spacing) {
            Text("Account").frame(minWidth: PlanColumns.account, maxWidth: .infinity, alignment: .leading)
            Text("Status").frame(width: PlanColumns.status, alignment: .leading)
            Text("Used").frame(width: PlanColumns.used, alignment: .trailing)
            Text("Plan").frame(width: PlanColumns.plan, alignment: .leading)
            Text("Per month").frame(width: PlanColumns.month, alignment: .trailing)
            Text("Room left").frame(width: PlanColumns.room, alignment: .trailing)
            Color.clear.frame(width: PlanColumns.button, height: 1)
            Color.clear.frame(width: PlanColumns.menu, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.vertical, 8)
    }
}

/// A provider's rows. One account: a single row with the plan. Several accounts: a provider
/// row that carries the plan once, with an indented row per account under it. Other cloud
/// folders have no plan and no button.
struct ProviderGroupRows: View {
    let group: ProviderGroup
    let compact: Bool
    let plan: PlanRow?
    let subscription: Subscription?
    let edit: () -> Void
    let act: (ProviderRowAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if group.hasPlan, group.accounts.count == 1, let account = group.accounts.first {
                line(name: group.name, caption: account.accountLabel, account: account,
                     used: account.usedBytes, showsPlan: true)
            } else {
                line(name: group.name, caption: accountCount, account: nil, used: group.usedBytes,
                     showsPlan: group.hasPlan)
                ForEach(group.accounts) { account in
                    line(name: account.accountLabel ?? account.folderName ?? group.name, caption: nil,
                         account: account, used: account.usedBytes, showsPlan: false)
                        .padding(.leading, 18)
                }
            }
        }
    }

    private var accountCount: String {
        group.hasPlan ? Format.count(group.accounts.count, "account") : Format.count(group.accounts.count, "folder")
    }

    @ViewBuilder
    private func line(name: String, caption: String?, account: AccountRow?, used: Int64?, showsPlan: Bool) -> some View {
        let cells = PlanCells(plan: showsPlan ? plan : nil, subscription: showsPlan ? subscription : nil,
                              hasPlan: showsPlan, sharedBy: showsPlan && group.accounts.count > 1 ? group : nil)
        VStack(alignment: .leading, spacing: 4) {
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: PlanColumns.spacing) {
                    nameCell(name, caption).frame(maxWidth: .infinity, alignment: .leading)
                    statusCell(account).frame(width: PlanColumns.status, alignment: .leading)
                    usedCell(used).frame(width: PlanColumns.used, alignment: .trailing)
                    button(showsPlan).frame(width: PlanColumns.button, alignment: .trailing)
                    menu(account: account, providerLine: showsPlan || account == nil)
                        .frame(width: PlanColumns.menu, alignment: .trailing)
                }
                if showsPlan {
                    cells.summary
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: PlanColumns.spacing) {
                    nameCell(name, caption)
                        .frame(minWidth: PlanColumns.account, maxWidth: .infinity, alignment: .leading)
                    statusCell(account).frame(width: PlanColumns.status, alignment: .leading)
                    usedCell(used).frame(width: PlanColumns.used, alignment: .trailing)
                    cells.planCell.frame(width: PlanColumns.plan, alignment: .leading)
                    cells.monthCell.frame(width: PlanColumns.month, alignment: .trailing)
                    cells.roomCell.frame(width: PlanColumns.room, alignment: .trailing)
                    button(showsPlan).frame(width: PlanColumns.button, alignment: .trailing)
                    menu(account: account, providerLine: showsPlan || account == nil)
                        .frame(width: PlanColumns.menu, alignment: .trailing)
                }
            }
            if let note = account.flatMap(note) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .padding(.vertical, 8)
    }

    private func nameCell(_ name: String, _ caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.body.weight(.medium)).lineLimit(1).truncationMode(.tail)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .help(caption.map { "\(name), \($0)" } ?? name)
    }

    @ViewBuilder
    private func statusCell(_ account: AccountRow?) -> some View {
        if let account {
            Text(status(account))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(statusStyle(account))
        } else {
            Text("")
        }
    }

    private func usedCell(_ used: Int64?) -> some View {
        Text(used.map(Format.bytes) ?? "").monospacedDigit().lineLimit(1)
    }

    @ViewBuilder
    private func button(_ showsPlan: Bool) -> some View {
        if showsPlan {
            Button(subscription == nil ? "Add plan" : "Edit plan", action: edit)
                .controlSize(.small)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    /// The ⋯ menu. A provider line offers the plan and, for a provider the user added,
    /// removing it; an account line offers excluding, including or forgetting the account.
    @ViewBuilder
    private func menu(account: AccountRow?, providerLine: Bool) -> some View {
        let items = menuItems(account: account, providerLine: providerLine)
        if items.isEmpty {
            Color.clear.frame(height: 1)
        } else {
            Menu {
                ForEach(items, id: \.title) { item in
                    Button(item.title, role: item.destructive ? .destructive : nil) { act(item.action) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions for \(account?.accountLabel ?? group.name)")
            .accessibilityLabel("More actions for \(account?.accountLabel ?? group.name)")
        }
    }

    private struct MenuItem {
        let title: String
        let action: ProviderRowAction
        var destructive = false
    }

    private func menuItems(account: AccountRow?, providerLine: Bool) -> [MenuItem] {
        var items: [MenuItem] = []
        if providerLine, let subscription {
            items.append(MenuItem(title: "Remove plan…", action: .removePlan(subscription), destructive: true))
        }
        if let account, let path = account.path, !account.isCostOnly {
            if account.isGone {
                items.append(MenuItem(title: "Forget", action: .forget(path)))
            } else if account.isExcluded {
                items.append(MenuItem(title: "Include in scans", action: .exclude(path, false)))
            } else {
                items.append(MenuItem(title: "Exclude from scans", action: .exclude(path, true)))
            }
        }
        if providerLine, let custom = group.custom {
            items.append(MenuItem(title: "Remove from Cloudpane…", action: .removeCustom(custom), destructive: true))
        }
        return items
    }

    private func statusStyle(_ account: AccountRow) -> AnyShapeStyle {
        if account.isExcluded || account.isCostOnly || account.state == .missing { return AnyShapeStyle(.secondary) }
        if account.isGone || account.state != .installed { return AnyShapeStyle(Theme.warning) }
        return AnyShapeStyle(.primary)
    }

    private func status(_ account: AccountRow) -> String {
        if account.isCostOnly { return "Not on this Mac" }
        if account.isExcluded { return "Excluded from scans" }
        if account.isGone { return "Not found" }
        switch account.state {
        case .installed: return "Installed"
        case .partial: return "Partial view"
        case .missing: return "Not installed"
        case .unavailable: return "Unavailable"
        }
    }

    /// A sentence under the row: why it is partial or unavailable, or that it is gone.
    private func note(_ account: AccountRow) -> String? {
        if account.isGone {
            let seen = account.lastSeenBytes.map { "; the last complete scan saw \(Format.bytes($0)) there" } ?? ""
            return "Not found on this Mac now\(seen). Scan again if you moved or removed it."
        }
        guard account.state == .partial || account.state == .unavailable else { return nil }
        return account.reason
    }
}

/// The plan's cells, shown once per provider.
struct PlanCells {
    let plan: PlanRow?
    let subscription: Subscription?
    let hasPlan: Bool
    /// Set on a provider row whose plan several accounts share.
    let sharedBy: ProviderGroup?

    private var shared: String? {
        guard let sharedBy, subscription != nil else { return nil }
        return sharedBy.accounts.count == 2 ? "Shared by both \(sharedBy.name) accounts"
            : "Shared by all \(sharedBy.accounts.count) \(sharedBy.name) accounts"
    }

    @ViewBuilder
    var planCell: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let subscription {
                Text(subscription.name).lineLimit(1).truncationMode(.tail)
                Text(subscription.planBytes.map { "\(Format.bytes($0)) plan" } ?? "Size not set")
                    .font(.caption).foregroundStyle(.secondary)
                if let shared {
                    Text(shared).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if hasPlan {
                Text("No plan").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var monthCell: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let plan {
                Text(Format.money(plan.monthly)).monospacedDigit()
                    .foregroundStyle(plan.subscription.countsTowardPersonalTotal ? .primary : .secondary)
                if let detail = monthDetail(plan) {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    var roomCell: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let plan, let headroom = plan.headroomBytes {
                Text(roomText(headroom)).monospacedDigit().lineLimit(1)
                    .foregroundStyle(headroom < 0 ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(.primary))
                if let detail = roomDetail(plan) {
                    Text(detail).font(.caption)
                        .foregroundStyle(plan.isDeadWeight ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
        }
    }

    /// Everything above in one line, for the compact layout.
    var summary: Text {
        guard let subscription else { return Text(hasPlan ? "No plan" : "") }
        var parts = [subscription.name + (subscription.planBytes.map { ", \(Format.bytes($0))" } ?? "")]
        if let plan {
            parts.append("\(Format.money(plan.monthly)) a month" + (monthDetail(plan).map { " (\($0))" } ?? ""))
            if let headroom = plan.headroomBytes {
                parts.append(roomText(headroom) + (headroom >= 0 ? " left" : "")
                             + (roomDetail(plan).map { ", \($0.lowercased())" } ?? ""))
            }
        }
        if let shared { parts.append(shared) }
        return Text(parts.joined(separator: " · "))
    }

    private func monthDetail(_ plan: PlanRow) -> String? {
        if let bundle = plan.subscription.bundle { return bundle.displayName }
        if plan.subscription.inactive { return "Inactive" }
        return plan.costPerTB.map { "\(Format.money($0)) per TB" }
    }

    private func roomText(_ headroom: Int64) -> String {
        headroom < 0 ? "Over by \(Format.bytes(-headroom))" : Format.bytes(headroom)
    }

    private func roomDetail(_ plan: PlanRow) -> String? {
        if plan.isDeadWeight { return "Under 5% used" }
        if let months = plan.monthsToFull {
            return months <= 0 ? "Full" : "Full in \(Format.months(months).lowercased())"
        }
        if plan.reportedTotal != nil { return "From your entered total" }
        return nil
    }
}

/// What a row's ⋯ menu asks Providers to do.
enum ProviderRowAction {
    case removePlan(Subscription)
    case exclude(String, Bool)
    case forget(String)
    case removeCustom(CustomProvider)
}
