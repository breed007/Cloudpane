import CloudpaneCore
import SwiftUI

/// The Help window: topics in a sidebar, a search field, and the page. Opened from the Help
/// menu (⌘?), from each view's help button, and from Learn more links.
struct HelpView: View {
    @Bindable var library: HelpLibrary
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search help")
        .navigationTitle("Cloudpane Help")
        .frame(minWidth: 720, minHeight: 500)
        #if DEBUG
        .onAppear { if let search = DemoData.helpSearch { query = search } }
        #endif
    }

    @ViewBuilder
    private var sidebar: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            List(library.topics, selection: $library.selection) { topic in
                Text(topic.title).tag(topic.id)
            }
        } else {
            let results = library.catalog?.search(trimmed) ?? []
            if results.isEmpty {
                ContentUnavailableView("No topics match \u{201C}\(trimmed)\u{201D}", systemImage: "magnifyingglass",
                                       description: Text("Try another word, or fewer words."))
            } else {
                List(results, selection: $library.selection) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.topic.title)
                        Text(result.excerpt ?? result.topic.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                    .tag(result.topic.id)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let error = library.loadError {
            ContentUnavailableView("Help is not available", systemImage: "questionmark.circle",
                                   description: Text(error))
        } else if let topic = library.topic(library.selection) {
            ScrollViewReader { proxy in
                ScrollView {
                    MarkdownView(markdown: topic.body) { link in
                        if link.hasPrefix("#") {
                            library.anchor = String(link.dropFirst())
                        } else if let next = library.catalog?.topic(forLink: link) {
                            library.selection = next.id
                            library.anchor = HelpCatalog.anchor(forLink: link)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: library.anchor) { scroll(proxy) }
            }
            .id(topic.id)
        } else {
            Text("Choose a topic").foregroundStyle(.secondary)
        }
    }
}

extension HelpView {
    /// Scrolls to the pending heading, once the page has laid out.
    fileprivate func scroll(_ proxy: ScrollViewProxy) {
        guard let anchor = library.anchor else { return }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
            library.anchor = nil
        }
    }
}

/// Opens the Help window at "topic" or "topic#anchor".
@MainActor
func openHelp(_ destination: String, with openWindow: OpenWindowAction) {
    HelpLibrary.shared.show(destination)
    openWindow(id: HelpLibrary.windowID)
}

/// Help > Cloudpane Help (⌘?).
struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Cloudpane Help") {
            if HelpLibrary.shared.selection == nil { HelpLibrary.shared.selection = HelpLibrary.shared.topics.first?.id }
            openWindow(id: HelpLibrary.windowID)
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}

/// The small help button in a view's toolbar or header.
struct HelpButton: View {
    let topic: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openHelp(topic, with: openWindow)
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .help("Help")
        .accessibilityLabel("Help")
    }
}

/// A "Learn more" link that opens the Help window at a topic.
struct LearnMoreLink: View {
    let topic: String
    var title = "Learn more"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) { openHelp(topic, with: openWindow) }
            .buttonStyle(.link)
    }
}
