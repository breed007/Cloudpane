import Charts
import CloudpaneCore
import SwiftUI

/// Per-provider totals over time, and what changed between any two complete scans.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var from: Int64?
    @State private var to: Int64?
    @State private var diff: SnapshotDiff?
    @State private var comparing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                chart
                compare
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("History")
        .task {
            await model.refreshHistory()
            selectLatest()
        }
        .onChange(of: model.snapshotList.map(\.id)) { _, _ in selectLatest() }
    }

    @ViewBuilder
    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Totals over time").font(.headline)
            if model.snapshotList.count < 2 {
                Text("The chart appears after two complete scans.")
                    .foregroundStyle(.secondary)
            } else if Set(model.history.map(\.snapshotID)).count < 2 {
                Text("No cloud storage folders were found in the scans so far, so there is nothing to chart yet.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(model.history) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Size", point.logicalBytes))
                        .foregroundStyle(by: .value("Provider", name(point)))
                    PointMark(x: .value("Date", point.date), y: .value("Size", point.logicalBytes))
                        .foregroundStyle(by: .value("Provider", name(point)))
                        .symbolSize(20)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let bytes = value.as(Int64.self) { Text(Format.bytes(bytes)) } }
                    }
                }
                .frame(height: 260)
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func name(_ point: HistoryPoint) -> String {
        point.provider == ScanRoot.unrecognizedProvider ? AppModel.unrecognizedName : point.providerName
    }

    @ViewBuilder
    private var compare: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What changed").font(.headline)
            if model.snapshotList.count < 2 || from == nil || to == nil {
                Text("Comparing needs two complete scans.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Picker("From", selection: $from) {
                        ForEach(model.snapshotList) { Text(label($0)).tag(Int64?.some($0.id)) }
                    }
                    Picker("To", selection: $to) {
                        ForEach(model.snapshotList) { Text(label($0)).tag(Int64?.some($0.id)) }
                    }
                    Button("Compare") { runCompare() }
                        .disabled(from == nil || to == nil || from == to || comparing)
                }
                if comparing { ProgressView().controlSize(.small) }
                if let diff { DiffSummary(diff: diff) }
            }
        }
    }

    /// From and To start at the two latest complete scans, and move on when the selected
    /// ones are gone.
    private func selectLatest() {
        let ids = model.snapshotList.map(\.id)
        if to == nil || !ids.contains(to ?? -1) { to = ids.last }
        if from == nil || !ids.contains(from ?? -1) || from == to { from = ids.dropLast().last }
    }

    private func label(_ snapshot: Snapshot) -> String {
        Format.date(snapshot.finishedAt ?? snapshot.startedAt) + (snapshot.isIncremental ? " (update)" : "")
    }

    private func runCompare() {
        guard let from, let to else { return }
        comparing = true
        Task {
            diff = await model.diff(from: min(from, to), to: max(from, to))
            comparing = false
        }
    }
}

private struct DiffSummary: View {
    @Environment(AppModel.self) private var model
    let diff: SnapshotDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                stat("Added", diff.addedCount, Format.bytes(diff.addedBytes))
                stat("Removed", diff.removedCount, Format.bytes(diff.removedBytes))
                stat("Changed", diff.changedCount, (diff.changedByteDelta >= 0 ? "+" : "-") + Format.bytes(abs(diff.changedByteDelta)))
                stat("Moved or renamed", diff.movedCount, "")
            }
            section("Moved or renamed", diff.moved.map { move in
                "\(Format.path(move.before.path, home: model.access.homePath)) to \(Format.path(move.after.path, home: model.access.homePath))"
            })
            section("Added", diff.added.map { "\(Format.path($0.path, home: model.access.homePath)), \(Format.bytes($0.logicalSize ?? 0))" })
            section("Removed", diff.removed.map { "\(Format.path($0.path, home: model.access.homePath)), \(Format.bytes($0.logicalSize ?? 0))" })
            section("Changed", diff.changed.map { change in
                "\(Format.path(change.after.path, home: model.access.homePath)), \(Format.bytes(change.before.logicalSize ?? 0)) to \(Format.bytes(change.after.logicalSize ?? 0))"
            })
        }
    }

    private func stat(_ title: String, _ count: Int, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(Format.count(count)).font(.title3.weight(.semibold).monospacedDigit())
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            DisclosureGroup("\(title) (\(Format.count(lines.count)) shown)") {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
