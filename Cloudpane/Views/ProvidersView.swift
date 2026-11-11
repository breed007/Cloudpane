import CloudpaneCore
import SwiftUI

/// Every provider account with its status and space used, the plan each provider has (one
/// per provider, shared by its accounts), the totals and the guidance lines.
struct ProvidersView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Subscription?
    @State private var addingProvider = false
    @State private var planAfterAdding: String?
    @State private var removingPlan: Subscription?
    @State private var removingProvider: CustomProvider?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                totals
                accounts
                if model.showsICloud {
                    ICloudSection()
                }
                guidance
                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Providers")
        .sheet(item: $editing) { plan in
            PlanEditor(original: plan)
        }
        .sheet(isPresented: $addingProvider, onDismiss: {
            // A plan with no folder goes straight to its plan form, once the sheet is gone.
            if let provider = planAfterAdding {
                planAfterAdding = nil
                openEditor(for: provider)
            }
        }) {
            AddProviderSheet(startingWith: startingTab) { provider in planAfterAdding = provider }
        }
        .confirmationDialog(removingPlan.map { "Remove the plan \($0.name.isEmpty ? model.providerName(for: $0.provider) : $0.name)?" } ?? "",
                            isPresented: Binding(get: { removingPlan != nil }, set: { if !$0 { removingPlan = nil } }),
                            presenting: removingPlan) { plan in
            Button("Remove plan", role: .destructive) { Task { await model.removePlan(for: plan.provider) } }
        } message: { plan in
            Text("Cloudpane forgets the price and size you entered for \(model.providerName(for: plan.provider)). Nothing changes with the provider.")
        }
        .confirmationDialog(removingProvider.map { "Remove \($0.name) from Cloudpane?" } ?? "",
                            isPresented: Binding(get: { removingProvider != nil }, set: { if !$0 { removingProvider = nil } }),
                            presenting: removingProvider) { provider in
            Button("Remove", role: .destructive) { Task { await model.removeCustomProvider(provider) } }
        } message: { provider in
            Text(provider.isCostOnly
                 ? "Cloudpane deletes \(provider.name) and its plan. Nothing changes with the provider."
                 : "Cloudpane deletes the name \(provider.name) and its plan. The folder \(provider.folderName ?? "") goes back to other cloud folders at the next scan. No file changes.")
        }
        .onAppear(perform: openPendingEditor)
        #if DEBUG
        .onAppear { if DemoData.opensAddProvider { addingProvider = true } }
        #endif
        .onChange(of: model.pendingPlanProvider) { openPendingEditor() }
    }

    // MARK: - Totals

    private var totals: some View {
        let report = model.planReport
        return HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly cost").font(.callout).foregroundStyle(.secondary)
                if let personal = report?.personalTotal, !personal.isEmpty {
                    Text(Format.totals(personal))
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    if personal.isMixed {
                        Text("Plans are in more than one currency. Each is totaled on its own; Cloudpane does not convert between them.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Not set")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("Add a plan to see what your storage costs.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let bundled = report?.bundledTotal, !bundled.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Covered by bundles").font(.callout).foregroundStyle(.secondary)
                    Text(Format.totals(bundled))
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("Shown for reference, not added to the monthly cost.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Accounts

    private var accounts: some View {
        let groups = model.providerGroups
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Accounts and plans").font(.headline)
                Spacer()
                Button("Add provider…") { addingProvider = true }
            }
            // The columns need about 720 points. Where they do not fit, each row puts its
            // plan on a second line instead of squeezing the account name. ViewThatFits
            // keeps the whole table in one layout, so the columns always line up.
            ViewThatFits(in: .horizontal) {
                table(groups, compact: false)
                table(groups, compact: true)
            }
            Text("One plan per provider. Accounts of the same provider share it, and its used space, room left and months to full count all of them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }



    private func table(_ groups: [ProviderGroup], compact: Bool) -> some View {
        VStack(spacing: 0) {
            if !compact {
                PlanTableHeader()
                Divider()
            }
            ForEach(groups) { group in
                ProviderGroupRows(group: group, compact: compact,
                                  plan: group.provider.flatMap { model.planRow(for: $0) },
                                  subscription: group.provider.flatMap { model.subscription(for: $0) },
                                  edit: { if let provider = group.provider { openEditor(for: provider) } },
                                  act: perform)
                if group.id != groups.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var startingTab: AddProviderSheet.Choice {
        #if DEBUG
        return DemoData.addProviderTab.flatMap(AddProviderSheet.Choice.init(rawValue:)) ?? .supported
        #else
        return .supported
        #endif
    }

    private func perform(_ action: ProviderRowAction) {
        switch action {
        case .removePlan(let plan): removingPlan = plan
        case .removeCustom(let provider): removingProvider = provider
        case .exclude(let path, let excluded): Task { await model.setExcluded(excluded, rootPath: path) }
        case .forget(let path): Task { await model.forget(rootPath: path) }
        }
    }

    private func openEditor(for provider: String) {
        editing = model.subscription(for: provider)
            ?? Subscription(provider: provider, name: "", price: 0,
                            currency: Locale.current.currency?.identifier ?? "USD")
    }

    /// Opens the editor Overview asked for, once.
    private func openPendingEditor() {
        guard let provider = model.pendingPlanProvider else { return }
        model.pendingPlanProvider = nil
        openEditor(for: provider)
    }

    // MARK: - Guidance

    @ViewBuilder
    private var guidance: some View {
        let report = model.planReport
        let deadWeight = report?.rows.filter(\.isDeadWeight) ?? []
        let notes = Set(report?.rows.compactMap { $0.subscription.planBytes == nil ? nil : $0.growthNote } ?? [])
        VStack(alignment: .leading, spacing: 12) {
            Text("Guidance").font(.headline)
            if let window = report?.growthWindow {
                Text("Growth is measured between the scans on \(Format.date(window.from)) and \(Format.date(window.to)).")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let note = notes.first {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(deadWeight) { row in
                Banner(symbol: "scalemass", tint: Theme.warning,
                       title: "\(model.providerName(for: row.id)) is under 5% used",
                       message: "It held less than 5% of its plan in each of the last two complete scans, while costing \(Format.money(row.monthly)) a month.")
            }
            options
        }
    }

    @ViewBuilder
    private var options: some View {
        let options = model.planReport?.options ?? []
        if model.subscriptions.isEmpty {
            EmptyView()
        } else if options.isEmpty {
            Text("No consolidation options: no paid plan has room for everything in another one in the same currency.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Consolidation options")
                    .font(.subheadline.weight(.semibold))
                Text("These are options, not advice, and they can be taken together: no two count the same free space. Canceling a provider removes a copy of its files, so each option shows that provider's backup grade. Make sure the files have a real backup first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(options) { option in
                    ConsolidationRow(option: option)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let catalog = model.priceCatalog {
                Text("Prices in the plan form come from Cloudpane's built-in catalog of US prices as of \(catalogDate(catalog.asOf)). Check the provider's page before relying on them.")
            } else {
                Text("The built-in price catalog could not be read, so the plan form has no suggested prices.")
            }
            Text("Plan sizes use decimal units, as providers sell them: 1 TB is 1,000,000,000,000 bytes.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func catalogDate(_ iso: String) -> String {
        guard let date = try? Date(iso, strategy: Date.ISO8601FormatStyle().year().month().day()) else { return iso }
        // The catalog date is a calendar date; format it in UTC so it never shifts a day.
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt))
    }
}

/// One consolidation option, always beside the backup grade of the provider it would cancel.
struct ConsolidationRow: View {
    @Environment(AppModel.self) private var model
    let option: ConsolidationOption

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Option: move \(name(option.cancel)) (\(Format.bytes(option.movedBytes))) into \(name(option.into)) and cancel \(name(option.cancel)).")
                Text("Saves \(Format.money(option.monthlySaving)) a month. With the options above it, \(name(option.into)) would have \(Format.bytes(option.headroomAfter)) left.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(name(option.cancel)) grade")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let rollup = model.grade?.byProvider[option.cancel] {
                    LetterBadge(letter: rollup.letter)
                } else {
                    Text("Not graded").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func name(_ provider: String) -> String { model.providerName(for: provider) }
}

