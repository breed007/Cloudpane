import SwiftUI

/// First run: what Cloudpane does and never does, the two folder grants, then the first
/// scan. Onboarding completes even when neither folder exists on this Mac.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = Step.welcome

    enum Step { case welcome, folders, scanning }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Group {
                switch step {
                case .welcome: welcome
                case .folders: folders
                case .scanning: scanning
                }
            }
            .frame(maxWidth: 560)
            Spacer(minLength: 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cloudpane")
                .font(.largeTitle.weight(.semibold))
            Text("See how much you keep in cloud storage, where each file lives, and which files exist only in the cloud. Everything is read from folders already on this Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Text("What Cloudpane never does")
                    .font(.headline)
                promise("Open, change, move, copy, delete or upload a file.")
                promise("Download a file's contents on its own.")
                promise("Sign in to an account or connect to the internet.")
                promise("Collect or send anything about you or your files.")
            }
            Text("It reads names, sizes, dates and types, and keeps what it finds on this Mac. Reading a folder may make the cloud app fetch that folder's list of files, and the cloud app may then download items it keeps on this Mac by its own settings, as it would after you open the folder in Finder.")
                .fixedSize(horizontal: false, vertical: true)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Continue") { step = .folders }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
    }

    private func promise(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "xmark.circle")
                .foregroundStyle(Theme.accent)
        }
    }

    // MARK: - Folders

    private var folders: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Two folders to read")
                .font(.title.weight(.semibold))
            Text("Cloud storage apps keep their files in two places on your Mac. macOS asks you to approve each one. Cloudpane gets read-only access to these two folders and nothing else in your Library.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                ForEach(GrantedFolder.allCases) { folder in
                    FolderGrantRow(folder: folder)
                }
            }

            Text("A folder that is not on this Mac is fine to skip. It usually means no app uses it yet; you can grant it later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LearnMoreLink(topic: HelpTopics.folderAccess, title: "Learn more about folder access")
                .font(.callout)

            HStack {
                Button("Back") { step = .welcome }
                Spacer()
                Button("Scan now") {
                    step = .scanning
                    model.scan()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Scanning

    private var scanning: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.isScanning ? "Scanning" : "Scan finished")
                .font(.title.weight(.semibold))
            if model.isScanning {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    ScanProgressText(progress: model.progress)
                }
                Text("Cloudpane reads each file's details without downloading it. A first scan can take a few minutes while each cloud app sends the lists of folders it has not shown on this Mac yet.")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if model.isScanning {
                    Button("Stop scan") { model.cancelScan() }
                }
                Spacer()
                Button("Show my footprint") { model.completeOnboarding() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(model.isScanning)
            }
        }
    }

    private var summary: String {
        let found = model.providerRows.filter(\.hasData)
        if found.isEmpty {
            return "No cloud storage folders were found on this Mac. Overview shows each provider as not installed. When you add one, scan again from Settings."
        }
        let names = found.map(\.name).joined(separator: ", ")
        return "Found \(Format.bytes(model.footprintBytes)) in \(names)."
    }
}

/// One folder: whether it exists, whether access is granted, and the button to grant it.
struct FolderGrantRow: View {
    @Environment(AppModel.self) private var model
    let folder: GrantedFolder
    @State private var message: String?

    var body: some View {
        let presence = model.access.presence(of: folder)
        let granted = model.access.isGranted(folder)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol(presence: presence, granted: granted))
                    .foregroundStyle(granted ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.title).font(.headline)
                    Text(folder.displayPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(status(presence: presence, granted: granted))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if presence == .absent {
                    Button("Check again") { model.checkFolders() }
                } else if granted {
                    Text("Granted").foregroundStyle(.secondary)
                } else {
                    Button("Grant access") {
                        message = model.access.requestGrant(folder)
                        model.checkFolders()
                    }
                }
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { model.access.refreshPresence() }
    }

    private func symbol(presence: FolderPresence, granted: Bool) -> String {
        if granted { return "checkmark.circle.fill" }
        return presence == .absent ? "minus.circle" : "folder"
    }

    private func status(presence: FolderPresence, granted: Bool) -> String {
        if granted { return "Cloudpane can read this folder." }
        switch presence {
        case .absent: return "Not on this Mac. \(folder.purpose)"
        case .present: return folder.purpose
        case .unknown(let why): return "Cloudpane cannot check this folder. \(why)"
        }
    }
}
