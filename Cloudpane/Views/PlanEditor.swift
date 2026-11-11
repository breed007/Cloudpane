import CloudpaneCore
import SwiftUI

/// The plan form, shaped after Wallos's entry form, plus plan size and a bundle flag.
struct PlanEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let original: Subscription
    @State private var plan: Subscription
    @State private var sizeValue: Double
    @State private var sizeUnit: SizeUnit
    @State private var hasPlanSize: Bool
    @State private var hasNextPayment: Bool
    @State private var nextPayment: Date
    /// The catalog tier the price came from, while the price still matches it.
    @State private var filledFrom: PriceTier?
    @State private var saveError: String?
    @State private var confirmingDelete = false

    enum SizeUnit: String, CaseIterable, Identifiable {
        case gb = "GB"
        case tb = "TB"
        var id: String { rawValue }
        var bytes: Double { self == .gb ? 1e9 : 1e12 }
    }

    init(original: Subscription) {
        self.original = original
        _plan = State(initialValue: original)
        let bytes = Double(original.planBytes ?? 0)
        let unit: SizeUnit = bytes >= 1e12 ? .tb : .gb
        _sizeUnit = State(initialValue: unit)
        _sizeValue = State(initialValue: bytes / unit.bytes)
        _hasPlanSize = State(initialValue: original.planBytes != nil)
        _hasNextPayment = State(initialValue: original.nextPayment != nil)
        _nextPayment = State(initialValue: original.nextPayment ?? Date())
    }

    private var providerName: String { model.providerName(for: plan.provider) }
    private var tiers: [PriceTier] { model.priceCatalog?.tiers(for: plan.provider) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Provider", value: providerName)
                    if !tiers.isEmpty {
                        Picker("Fill from catalog", selection: catalogSelection) {
                            Text("Choose a plan").tag(String?.none)
                            ForEach(tiers) { tier in
                                Text(tierLabel(tier)).tag(String?.some(tier.id))
                            }
                        }
                    }
                    TextField("Name", text: $plan.name, prompt: Text("Plan name"))
                }

                Section("Price") {
                    TextField("Price", value: $plan.price, format: .number.precision(.fractionLength(0...4)))
                    if let filledFrom, !filledFrom.verified, filledFrom.priceAmount == plan.price {
                        Label("Price not confirmed. Check the provider's page.", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(Theme.warning)
                    }
                    TextField("Currency", text: currency, prompt: Text("USD"))
                    Picker("Billing cycle", selection: $plan.cycle) {
                        ForEach(BillingCycle.allCases, id: \.self) { cycle in
                            Text(cycleName(cycle)).tag(cycle)
                        }
                    }
                    Stepper(value: $plan.frequency, in: 1...36) {
                        LabeledContent("Every", value: frequencyText)
                    }
                    LabeledContent("Per month", value: plan.validationProblems().isEmpty
                                   ? Format.money(plan.monthly) : "")
                    Toggle("Next payment", isOn: $hasNextPayment)
                    if hasNextPayment {
                        DatePicker("Date", selection: $nextPayment, displayedComponents: .date)
                    }
                    TextField("Payment method", text: $plan.paymentMethod)
                    Toggle("Renews automatically", isOn: $plan.autoRenew)
                }

                Section("Plan") {
                    Toggle("Plan size", isOn: $hasPlanSize)
                    if hasPlanSize {
                        HStack {
                            TextField("Size", value: $sizeValue, format: .number.precision(.fractionLength(0...3)))
                            Picker("Unit", selection: $sizeUnit) {
                                ForEach(SizeUnit.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 80)
                        }
                    }
                    Picker("Bundle", selection: $plan.bundle) {
                        Text("Not part of a bundle").tag(BundleKind?.none)
                        ForEach(BundleKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(BundleKind?.some(kind))
                        }
                    }
                    if plan.bundle != nil {
                        Text("Bundle plans are shown but not added to your monthly cost.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Inactive", isOn: $plan.inactive)
                }

                Section("Details") {
                    TextField("Category", text: $plan.category)
                    TextField("URL", text: $plan.url)
                    TextField("Notes", text: $plan.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                let problems = draft.validationProblems() + [sizeProblem].compactMap { $0 }
                if !problems.isEmpty || saveError != nil {
                    Section {
                        ForEach(problems, id: \.self) { Text($0).foregroundStyle(Theme.warning) }
                        if let saveError { Text(saveError).foregroundStyle(Theme.warning) }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if original.id != nil {
                    Button("Delete plan", role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.validationProblems().isEmpty || sizeProblem != nil)
            }
            .padding(16)
        }
        .frame(width: 520, height: 640)
        .confirmationDialog("Delete the \(providerName) plan?", isPresented: $confirmingDelete) {
            Button("Delete plan", role: .destructive) {
                Task {
                    await model.deleteSubscription(original)
                    dismiss()
                }
            }
        }
    }

    /// The plan size in bytes, or nil when the field holds something no plan could be
    /// (negative, not a number, or past the 10,000 TB limit). Checked with Int64(exactly:)
    /// so a huge entry never traps while the form redraws.
    private var planBytes: Int64? {
        let bytes = (sizeValue * sizeUnit.bytes).rounded()
        guard bytes.isFinite, bytes > 0, bytes <= Double(Subscription.maximumPlanBytes) else { return nil }
        return Int64(exactly: bytes)
    }

    private var sizeProblem: String? {
        guard hasPlanSize, planBytes == nil else { return nil }
        return "Enter a plan size above zero and no more than 10,000 TB."
    }

    /// The plan as it would be saved.
    private var draft: Subscription {
        var value = plan
        value.planBytes = hasPlanSize ? planBytes : nil
        value.nextPayment = hasNextPayment ? nextPayment : nil
        value.currency = value.currency.uppercased()
        return value
    }

    private func save() {
        Task {
            if let error = await model.save(draft) {
                saveError = error
            } else {
                dismiss()
            }
        }
    }

    private var catalogSelection: Binding<String?> {
        Binding(get: { filledFrom?.id }, set: { id in
            guard let tier = tiers.first(where: { $0.id == id }) else { return }
            filledFrom = tier
            let filled = tier.prefill()
            plan.name = filled.name
            plan.price = filled.price
            plan.currency = filled.currency
            plan.cycle = filled.cycle
            plan.frequency = filled.frequency
            plan.url = filled.url
            plan.bundle = filled.bundle
            hasPlanSize = true
            sizeUnit = tier.planBytes >= 1_000_000_000_000 ? .tb : .gb
            sizeValue = Double(tier.planBytes) / sizeUnit.bytes
        })
    }

    private var currency: Binding<String> {
        Binding(get: { plan.currency }, set: { plan.currency = String($0.uppercased().prefix(3)) })
    }

    private func tierLabel(_ tier: PriceTier) -> String {
        let price = Format.money(Money(amount: tier.priceAmount, currency: tier.currency))
        let per = tier.cycle == .year ? "a year" : "a month"
        return "\(tier.tier), \(price) \(per)" + (tier.verified ? "" : " (price not confirmed)")
    }

    private func cycleName(_ cycle: BillingCycle) -> String {
        switch cycle {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Yearly"
        }
    }

    private var frequencyText: String {
        let unit: String
        switch plan.cycle {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        }
        return plan.frequency == 1 ? "1 \(unit)" : "\(plan.frequency) \(unit)s"
    }
}
