import SwiftUI

@main
struct CloudpaneApp: App {
    static let mainWindowID = "main"
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = CloudpaneApp.makeModel()

    @MainActor
    private static func makeModel() -> AppModel {
        #if DEBUG
        // Screenshot demo data; compiled out of Release. See DemoData.swift.
        if let demo = DemoData.modelIfRequested() { return demo }
        #endif
        return AppModel()
    }

    var body: some Scene {
        Window("Cloudpane", id: CloudpaneApp.mainWindowID) {
            RootView()
                .environment(model)
                .defaultAppStorage(model.defaults)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    #if DEBUG
                    await DemoData.prepare()
                    #endif
                    await model.start()
                }
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(before: .windowList) { MainWindowMenuItem() }
            CommandGroup(replacing: .help) { HelpMenuButton() }
            CommandMenu("Scan") {
                Button("Scan now") { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.isScanning || !model.onboardingComplete)
                Button("Stop scan") { model.cancelScan() }
                    .keyboardShortcut(".")
                    .disabled(!model.isScanning)
            }
        }

        // Help (⌘?): the pages in docs/help, read by HelpCatalog.
        Window("Cloudpane Help", id: HelpLibrary.windowID) {
            HelpView(library: HelpLibrary.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .defaultSize(width: 900, height: 640)
    }
}
