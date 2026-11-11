import CloudpaneCore
import SwiftUI

/// iCloud in Subscriptions: iCloud Drive from the scan, Photos as an estimate, the total the
/// user reads from System Settings, and what this build cannot see.
struct ICloudSection: View {
    @Environment(AppModel.self) private var model
    @State private var amount: Double?
    @State private var unit: Unit = .gigabytes
    @State private var editingTotal = false
    @State private var totalMessage: String?

    enum Unit: String, CaseIterable, Identifiable {
        case gigabytes = "GB"
        case terabytes = "TB"
        var id: String { rawValue }
        var bytes: Double { self == .gigabytes ? 1e9 : 1e12 }
    }

    var body: some View {
        let usage = model.iCloudUsage
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud").font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("iCloud Drive")
                    Text(usage?.driveBytes.map(Format.bytes) ?? "Not scanned").monospacedDigit()
                    Text("Measured by the last complete scan.").foregroundStyle(.secondary)
                }
                GridRow(alignment: .top) {
                    Text("Photos")
                    Text(usage?.photos.map { Format.bytes($0.logicalBytes) } ?? "Not measured").monospacedDigit()
                    photos
                }
                GridRow(alignment: .top) {
                    Text("Total in iCloud")
                    Text(usage?.reportedTotal.map { Format.bytes($0.bytes) } ?? "Not entered").monospacedDigit()
                    total
                }
                if let other = usage?.otherBytes {
                    GridRow {
                        Text("Everything else")
                        Text(Format.bytes(other)).monospacedDigit()
                        Text("The total minus iCloud Drive and the Photos estimate: device backups, Messages, Mail and other apps.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(ICloudUnavailable.all) { item in
                    GridRow {
                        Text(item.title)
                        Text("Not available in this build").foregroundStyle(.secondary)
                        Text(item.reason).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            Text("Apple One tiers in the plan form are bundles: they are shown, but stay out of the monthly cost.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Photos

    @ViewBuilder
    private var photos: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let record = model.photosLibrary {
                if let estimate = record.estimate {
                    Text("An estimate from the size of \((record.path as NSString).lastPathComponent) on this Mac, measured \(Format.date(estimate.measuredAt)).")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\((record.path as NSString).lastPathComponent) is chosen but not measured yet.")
                }
                HStack {
                    Button("Measure again") { Task { await model.measurePhotosLibrary() } }
                    Button("Forget library") { Task { await model.forgetPhotosLibrary() } }
                    if model.isMeasuringPhotos { ProgressView().controlSize(.small) }
                }
                .disabled(model.isMeasuringPhotos)
            } else {
                Text("Cloudpane can estimate Photos from the size of your Photos library. It reads only file sizes, never the photos.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose Photos library…") { Task { await model.choosePhotosLibrary() } }
            }
            if let message = model.photosMessage {
                Text(message).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("With Optimize Mac Storage turned on in Photos settings, this Mac keeps smaller versions and the originals stay in iCloud, so iCloud holds more than this estimate. Files in the library that share space on disk (copies made as clones) are counted in full, so the estimate can be larger than the size Finder shows. A library that does not use iCloud Photos is not in iCloud at all.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Entered total

    @ViewBuilder
    private var total: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let total = model.iCloudUsage?.reportedTotal, !editingTotal {
                Text("Entered \(Format.date(total.enteredAt)). The iCloud plan uses this figure instead of the scan.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Change") {
                        unit = total.bytes >= 1_000_000_000_000 ? .terabytes : .gigabytes
                        amount = Double(total.bytes) / unit.bytes
                        editingTotal = true
                    }
                    Button("Clear") { Task { await model.clearICloudTotal() } }
                }
            } else {
                Text("Enter your total iCloud usage from System Settings, under your name, then iCloud.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("Total", value: $amount, format: .number)
                        .frame(width: 90)
                        .onSubmit(saveTotal)
                    Picker("Unit", selection: $unit) {
                        ForEach(Unit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 70)
                    Button("Save", action: saveTotal).disabled(amount == nil)
                    if editingTotal {
                        Button("Cancel") { editingTotal = false; totalMessage = nil }
                    }
                }
            }
            if let totalMessage {
                Text(totalMessage).foregroundStyle(Theme.warning)
            }
        }
    }

    private func saveTotal() {
        guard let amount else { return }
        guard amount.isFinite, amount >= 0, amount * unit.bytes <= Double(Subscription.maximumPlanBytes) else {
            totalMessage = amount < 0 ? "The total cannot be negative." : "Enter a total of 10,000 TB or less."
            return
        }
        let bytes = Int64((amount * unit.bytes).rounded())
        Task {
            totalMessage = await model.setICloudTotal(bytes: bytes)
            if totalMessage == nil {
                editingTotal = false
                self.amount = nil
            }
        }
    }
}
