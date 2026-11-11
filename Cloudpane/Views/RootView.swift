import CloudpaneCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    /// Remembered between launches, so Cloudpane reopens on the view last used. A value
    /// saved by an earlier version opens the view that replaced it (SidebarItem(stored:)).
    @AppStorage(SidebarItem.storageKey) private var stored = SidebarItem.overview.rawValue
    private var selection: Binding<SidebarItem?> {
        Binding(get: { SidebarItem(stored: stored) }, set: { stored = ($0 ?? .overview).rawValue })
    }

    var body: some View {
        if let error = model.startupError {
            ContentUnavailableView("Cloudpane could not start", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if !model.onboardingComplete {
            OnboardingView()
        } else {
            NavigationSplitView {
                List(selection: selection) {
                    ForEach(SidebarItem.allCases) { item in
                        sidebarRow(item)
                    }
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .bottom) { UpdateStatusLine().padding(12) }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            } detail: {
                VStack(spacing: 0) {
                    if model.isScanning {
                        ScanStatusBar()
                        Divider()
                    }
                    if model.isHashing {
                        HashStatusBar()
                        Divider()
                    }
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .toolbar {
                            // Each view's help button opens its own topic.
                            ToolbarItem(placement: .primaryAction) {
                                HelpButton(topic: (selection.wrappedValue ?? .overview).helpTopic)
                            }
                        }
                }
            }
            #if DEBUG
            .onAppear { if let topic = DemoData.helpTopic { openHelp(topic, with: openWindow) } }
            #endif
            .alert("Something went wrong", isPresented: errorShown) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem) -> some View {
        if item.isAvailable {
            Label(item.title, systemImage: item.symbol)
                .tag(item)
        } else {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    Text("Coming in a later release")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                // Set on the image itself; the sidebar would otherwise tint it with the accent.
                Image(systemName: item.symbol)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .selectionDisabled()
            .help("\(item.title) arrives in a later release.")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection.wrappedValue ?? .overview {
        case .overview: OverviewView()
        case .fileSearch: FileSearchView()
        case .settings: SettingsView()
        case .backupGrade: BackupGradeView()
        case .providers: ProvidersView()
        case .duplicates: DuplicatesView()
        case .history: HistoryView()
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// A thin bar above the detail view while a scan runs.
struct ScanStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            ScanProgressText(progress: model.progress)
            Spacer()
            Button("Stop scan") { model.cancelScan() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ScanProgressText: View {
    let progress: ScanProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let progress {
                Text("\(Format.count(progress.filesSeen, "file")), \(Format.bytes(progress.bytesSeen))")
                    .font(.callout.monospacedDigit())
                if let root = progress.currentRoot {
                    // A first scan waits on the provider for each folder it has not listed on
                    // this Mac yet; that can take most of the scan's time.
                    Text(progress.gettingFolderList
                         ? "Getting the folder list from \(root.providerName)"
                         : "Scanning \(root.providerName): \(root.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Starting the scan")
                    .font(.callout)
            }
        }
    }
}

/// When the inventory last changed, and whether it is watching for more.
struct UpdateStatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 2) {
                Text(updated).font(.caption).foregroundStyle(.secondary)
                Text(model.isUpdating ? "Recording changes" : model.isWatching ? "Watching for changes" : "Not watching for changes")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var updated: String {
        guard let date = model.snapshot?.finishedAt ?? model.snapshot?.startedAt else { return "No scan yet" }
        return "Updated " + date.formatted(.relative(presentation: .named))
    }
}
