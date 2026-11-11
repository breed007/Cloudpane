import CloudpaneCore
import SwiftUI

/// Add provider: how a supported service shows up, a plan with no folder, or a name for a
/// folder under Library/CloudStorage that matches no provider. Cloudpane only records what
/// the user enters; it installs nothing and signs in to nothing.
struct AddProviderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Called after the sheet closes, with a provider id whose plan form should open.
    let onDone: (String?) -> Void

    enum Choice: String, CaseIterable, Identifiable {
        case supported, planOnly, nameFolder
        var id: String { rawValue }
        var title: String {
            switch self {
            case .supported: return "Supported service"
            case .planOnly: return "Plan without a folder"
            case .nameFolder: return "Name a folder"
            }
        }
    }

    @State private var choice: Choice

    init(startingWith choice: Choice = .supported, onDone: @escaping (String?) -> Void) {
        _choice = State(initialValue: choice)
        self.onDone = onDone
    }
    @State private var name = ""
    @State private var folder: String?
    @State private var message: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add provider").font(.title2.weight(.semibold))
            Picker("Add", selection: $choice) {
                ForEach(Choice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: choice) { message = nil }

            Group {
                switch choice {
                case .supported: supported
                case .planOnly: planOnly
                case .nameFolder: nameFolder
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let message {
                Text(message).font(.callout).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                LearnMoreLink(topic: HelpTopics.addProvider)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                action
            }
        }
        .padding(20)
        // Sized to its content: the sheet grows with the longest tab's text and never clips.
        .frame(width: 540)
        .frame(minHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - A supported service that isn't showing

    private var missing: [ProviderRule] {
        (model.report?.providers ?? []).filter { $0.state == .missing }.map(\.rule)
    }

    private var supported: some View {
        VStack(alignment: .leading, spacing: 12) {
            if missing.isEmpty {
                Text("All five supported services are on this Mac.")
            } else {
                Text("These supported services are not on this Mac. Each appears once its app has a folder here:")
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(missing, id: \.id) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.displayName).font(.headline)
                        Text(AddProviderSheet.howToShow(rule))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("Cloudpane installs nothing and signs in to nothing. It reads only the folders these apps keep on your Mac.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// How a provider's folder comes to be on this Mac. Vendor names appear here as data.
    static func howToShow(_ rule: ProviderRule) -> String {
        switch rule.id {
        case ProviderRule.iCloudDrive.id:
            return "iCloud Drive is a switch, not an app: turn it on in System Settings, under your name, then iCloud. Its folder is ~/Library/Mobile Documents/com~apple~CloudDocs."
        case "dropbox":
            return "Install the Dropbox app for Mac and sign in. Its folder appears in ~/Library/CloudStorage as Dropbox."
        case "google-drive":
            return "Install Google Drive for desktop and sign in. Its folder appears in ~/Library/CloudStorage as GoogleDrive- followed by your account."
        case "onedrive":
            return "Install the OneDrive app for Mac and sign in. Each account gets a folder in ~/Library/CloudStorage named OneDrive- followed by the account."
        case "box":
            return "Install Box Drive and sign in. Its folder appears in ~/Library/CloudStorage as Box-Box."
        default:
            return "Install its Mac app and sign in, so its folder appears in ~/Library/CloudStorage."
        }
    }

    // MARK: - Track a plan without a folder

    private var planOnly: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For storage you pay for that has no folder on this Mac, such as a service you use only in a browser. Its cost counts toward the monthly total. It has no space used, room left, months to full or backup grade, and no consolidation option moves files into it.")
                .fixedSize(horizontal: false, vertical: true)
            TextField("Provider name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
        }
    }

    // MARK: - Name an other cloud folder

    private var unnamedFolders: [String] {
        let named = Set(model.scanChoices.customProviders.compactMap(\.folderName))
        return (model.report?.unrecognized ?? []).map(\.folderName).filter { !named.contains($0) }.sorted()
    }

    private var nameFolder: some View {
        VStack(alignment: .leading, spacing: 12) {
            if unnamedFolders.isEmpty {
                Text("There are no other cloud folders in ~/Library/CloudStorage to name. Folders of the five supported services are named already.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Give a folder in ~/Library/CloudStorage that Cloudpane does not recognize a provider name. It becomes its own provider, can have a plan, and its files show under that name everywhere after the next scan. Cloudpane does not know whether it keeps file history, so its backup grade never counts history as a pass.")
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Folder", selection: $folder) {
                    Text("Choose a folder").tag(String?.none)
                    ForEach(unnamedFolders, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(maxWidth: 360)
                TextField("Provider name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }
        }
    }

    // MARK: - The action button

    @ViewBuilder
    private var action: some View {
        switch choice {
        case .supported:
            Button("Scan again") {
                model.checkFolders()
                model.scan()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        case .planOnly:
            Button("Add and enter plan") { Task { await add() } }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || working)
        case .nameFolder:
            Button("Name folder") { Task { await add() } }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || folder == nil || working)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() async {
        working = true
        defer { working = false }
        let result = choice == .planOnly
            ? await model.addCostOnlyProvider(named: trimmedName)
            : await model.nameFolder(folder ?? "", as: trimmedName)
        switch result {
        case .success(let provider):
            onDone(choice == .planOnly ? provider : nil)
            dismiss()
        case .failure(let error):
            message = error.description
        }
    }
}
