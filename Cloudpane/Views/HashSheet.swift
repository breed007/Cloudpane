import CloudpaneCore
import SwiftUI

/// The confirmation before hashing a folder: exactly what will download, and what it costs.
struct HashSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let folder: HashFolder
    let title: String
    @State private var plan: HashPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hash \(title)").font(.title2.weight(.semibold))
            Text("Hashing reads each file's contents to find exact duplicates and to confirm backup copies. It is the only time Cloudpane reads what is inside a file. Nothing is changed, moved or uploaded.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let plan {
                if plan.files == 0 {
                    Text(plan.alreadyHashed > 0 ? "Every file in this folder is already hashed." : "This folder has no files to hash.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        line("\(Format.count(plan.files, "file")), \(Format.bytes(plan.bytes)) in all.")
                        line(plan.downloadFiles == 0
                             ? "Nothing needs to download: every file is already on this Mac."
                             : "\(Format.count(plan.downloadFiles)) \(plan.downloadFiles == 1 ? "file is" : "files are") only in the cloud. This will download \(Format.bytes(plan.downloadBytes)).",
                             emphasis: plan.downloadFiles > 0)
                        if plan.localFiles > 0 {
                            line(plan.localFiles == 1
                                 ? "1 is already on this Mac (\(Format.bytes(plan.localBytes))) and is read without downloading."
                                 : "\(Format.count(plan.localFiles)) already on this Mac (\(Format.bytes(plan.localBytes))) are read without downloading.")
                        }
                    }
                    if plan.downloadFiles > 0 {
                        Text("Downloaded files take space on this Mac until macOS removes the local copies again, which it does when it needs the space or when you choose Remove Download.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        LearnMoreLink(topic: HelpTopics.hashing).font(.callout)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(plan?.downloadFiles ?? 0 > 0 ? "Download and hash" : "Hash") {
                    if let plan { model.startHashing(folder, confirmed: plan) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled((plan?.files ?? 0) == 0 || model.isHashing)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { plan = await model.hashPlan(for: folder) }
    }

    private func line(_ text: String, emphasis: Bool = false) -> some View {
        Text(text)
            .fontWeight(emphasis ? .semibold : .regular)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A thin bar above the detail view while hashing runs.
struct HashStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            if let progress = model.hashProgress {
                Text("Hashing \(Format.count(progress.filesDone)) of \(Format.count(progress.filesTotal, "file")), \(Format.bytes(progress.bytesDone)) of \(Format.bytes(progress.bytesTotal))")
                    .font(.callout.monospacedDigit())
            } else {
                Text("Starting to hash").font(.callout)
            }
            Spacer()
            Button("Stop hashing") { model.stopHashing() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
