import CloudpaneCore
import SwiftUI

/// The 3-2-1 grade: one letter overall, one per top-level folder, every letter explained.
struct BackupGradeView: View {
    @Environment(AppModel.self) private var model
    @State private var order = [KeyPathComparator(\FolderRow.bytes, order: .reverse)]
    @State private var rows: [FolderRow] = []
    @State private var shown: String?
    @State private var singleSelection: String?

    struct FolderRow: Identifiable {
        let id: String
        let provider: String
        let account: String
        let folder: String
        let bytes: Int64
        let files: Int
        let letter: GradeLetter
        let letterOrder: Int
        let grade: FolderGrade
    }

    var body: some View {
        Group {
            if model.isRegrading && model.grade == nil {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Grading").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = model.grade, !report.folders.isEmpty {
                content(report)
            } else if model.grade != nil {
                ContentUnavailableView("Nothing to grade", systemImage: "checkmark.shield",
                                       description: Text("The last complete scan found no files with content in any provider."))
            } else {
                ContentUnavailableView("No grade yet", systemImage: "checkmark.shield",
                                       description: Text(model.gradeNote ?? "The grade appears after a complete scan."))
            }
        }
        .navigationTitle("Backup grade")
        .onChange(of: order) { _, newOrder in rows.sort(using: newOrder) }
        .task(id: model.grade?.snapshotID) { rebuildRows() }
    }

    private func rebuildRows() {
        rows = (model.grade?.folders ?? []).map { grade in
            FolderRow(id: grade.id, provider: grade.providerName, account: grade.account,
                      folder: grade.folder.isEmpty ? "Files at the top level" : grade.folder,
                      bytes: grade.bytes, files: grade.files, letter: grade.letter,
                      letterOrder: grade.letter.score, grade: grade)
        }
        rows.sort(using: order)
    }

    private func content(_ report: GradeReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.isRegrading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Regrading with your latest changes. The grade below is from before them.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let note = model.gradeNote {
                        Banner(symbol: "clock", tint: Theme.warning, title: "Graded from an earlier scan", message: note)
                    }
                    if report.backupRoots.isEmpty {
                        Banner(symbol: "externaldrive.badge.plus", tint: Theme.warning,
                               title: "No backup locations",
                               message: "Sync is not backup: a file deleted in the cloud is deleted on every synced copy. Without a backup location, no folder can score above C, and folders in iCloud Drive, or in Box without a paid plan, no higher than D. Add a Time Machine disk, an external drive or a NAS share in Settings, then scan again.")
                    }
                    overall(report)
                    folders
                    singlePoint(report.singlePoint)
                    Text("How Cloudpane grades: a file counts as copied to another location when a downloaded file there has the same name, the same size, and a modification date within 2 seconds. A folder counts as copied when at least 90% of it, by size, is found. Only one sync cloud ever counts: another cloud holding the same files adds no copy, because sync is not backup. Version history comes from each provider's own documentation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
        }
    }

    // MARK: - Overall

    @ViewBuilder
    private func overall(_ report: GradeReport) -> some View {
        if let rollup = report.overall {
            HStack(alignment: .top, spacing: 20) {
                LetterBadge(letter: rollup.letter, size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overall grade").font(.headline)
                    Text(rollup.explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DistributionBar(rollup: rollup)
                        .frame(height: 12)
                    HStack(spacing: 14) {
                        ForEach(GradeLetter.allCases, id: \.self) { letter in
                            if let entry = rollup.distribution[letter] {
                                Text("\(letter.rawValue): \(entry.folders) \(entry.folders == 1 ? "folder" : "folders"), \(Format.bytes(entry.bytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 16) {
                        ForEach(report.byProvider.keys.sorted(), id: \.self) { provider in
                            if let letter = report.byProvider[provider]?.letter {
                                HStack(spacing: 6) {
                                    Text(model.providerName(for: provider)).font(.callout)
                                    LetterBadge(letter: letter, size: 20)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Text("No folders to grade. The last complete scan found no files in any provider.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Folders

    private var folders: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By folder").font(.headline)
            Text("Click a letter to see the checks behind it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Table(rows, sortOrder: $order) {
                TableColumn("Grade", value: \.letterOrder) { row in
                    Button {
                        shown = row.id
                    } label: {
                        LetterBadge(letter: row.letter, size: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Grade \(row.letter.rawValue), show checks")
                    .popover(isPresented: Binding(get: { shown == row.id }, set: { if !$0 { shown = nil } }),
                             arrowEdge: .trailing) {
                        GradeDetail(grade: row.grade)
                    }
                }
                .width(min: 50, ideal: 56, max: 60)
                TableColumn("Provider", value: \.provider)
                    .width(min: 90, ideal: 110)
                TableColumn("Account", value: \.account)
                    .width(min: 90, ideal: 140)
                TableColumn("Folder", value: \.folder)
                TableColumn("Size", value: \.bytes) { row in
                    Text(Format.bytes(row.bytes)).monospacedDigit()
                }
                .width(min: 70, ideal: 90)
                TableColumn("Files", value: \.files) { row in
                    Text(Format.count(row.files)).monospacedDigit()
                }
                .width(min: 50, ideal: 70)
            }
            .frame(minHeight: 260)
        }
    }

    // MARK: - Single point

    private func singlePoint(_ list: SinglePointList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exists only in one place").font(.headline)
            if list.totalFiles == 0 {
                Text("Every file Cloudpane saw is in more than one place.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(Format.count(list.totalFiles)) \(list.totalFiles == 1 ? "file" : "files"), \(Format.bytes(list.totalBytes)), are only in their provider's cloud: not downloaded on this Mac, and not found in another cloud or a backup."
                     + (list.files.count < list.totalFiles ? " The largest \(Format.count(list.files.count)) are listed." : ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Table(list.files, selection: $singleSelection) {
                    TableColumn("Name") { Text($0.name) }
                    TableColumn("Provider") { Text(model.providerName(for: $0.provider)) }
                        .width(min: 90, ideal: 110)
                    TableColumn("Path") { record in
                        Text(Format.path(record.path, home: model.access.homePath))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn("Size") { Text(Format.bytes($0.logicalSize ?? 0)).monospacedDigit() }
                        .width(min: 70, ideal: 90)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let path = ids.first {
                        Button("Reveal in Finder") { FileActions.revealInFinder(path) }
                        Button("Copy path") { FileActions.copyPath(path) }
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }
}

/// The checks behind one letter.
struct GradeDetail: View {
    let grade: FolderGrade

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LetterBadge(letter: grade.letter, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(grade.providerName): \(grade.folder.isEmpty ? "files at the top level" : grade.folder)")
                        .font(.headline)
                    Text(grade.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            ForEach(grade.checks, id: \.kind) { check in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol(check.status))
                        .foregroundStyle(color(check.status))
                        .accessibilityLabel(check.status.rawValue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.kind.title).font(.callout.weight(.medium))
                        Text(check.reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            Text("Where it is").font(.callout.weight(.medium))
            ForEach(grade.copies + grade.partial, id: \.self) { copy in
                HStack {
                    Text(copy.name)
                    Text(kindName(copy)).foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.percent(copy.coverage)).monospacedDigit()
                        .foregroundStyle(copy.coverage >= 0.9 ? .primary : .secondary)
                }
                .font(.callout)
            }
            if let fix = grade.fix {
                Divider()
                Label(fix, systemImage: "lightbulb")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func symbol(_ status: CheckStatus) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func color(_ status: CheckStatus) -> Color {
        switch status {
        case .pass: return .green
        case .fail: return .red
        case .unknown: return .secondary
        }
    }

    private func kindName(_ copy: CopyLocation) -> String {
        switch copy.kind {
        case .cloud: return "cloud"
        case .localSync: return "downloaded, synced"
        case .backup:
            let kind = copy.backupKind?.displayName.lowercased() ?? "backup"
            return copy.isOffsite ? "\(kind), off-site" : kind
        }
    }
}

struct LetterBadge: View {
    let letter: GradeLetter
    var size: CGFloat = 24

    var body: some View {
        Text(letter.rawValue)
            .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
            .frame(width: size, height: size)
            .background(Self.color(letter).opacity(0.85), in: RoundedRectangle(cornerRadius: size * 0.22))
            .foregroundStyle(.white)
            .accessibilityLabel("Grade \(letter.rawValue)")
    }

    static func color(_ letter: GradeLetter) -> Color {
        switch letter {
        case .A: return .green
        case .B: return Color(red: 0.45, green: 0.75, blue: 0.3)
        case .C: return .yellow.opacity(0.9)
        case .D: return .orange
        case .F: return .red
        }
    }
}

/// Bytes per letter, A to F, left to right.
struct DistributionBar: View {
    let rollup: GradeRollup

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(GradeLetter.allCases, id: \.self) { letter in
                    if let entry = rollup.distribution[letter], share > 0 {
                        Rectangle()
                            .fill(LetterBadge.color(letter))
                            .frame(width: geometry.size.width * width(entry))
                    }
                }
            }
            .clipShape(Capsule())
        }
    }

    private var share: Double { Double(max(rollup.bytes, 1)) }

    private func width(_ entry: (folders: Int, bytes: Int64)) -> CGFloat {
        if rollup.bytes > 0 { return CGFloat(Double(entry.bytes) / Double(rollup.bytes)) }
        return CGFloat(Double(entry.folders) / Double(max(rollup.folders, 1)))
    }
}
