import AppKit
import SwiftUI

/// Makes sure the main window can always be brought up: a moment after launch, and on every
/// reopen (a Dock click, or `open` on the app) when no window is visible.
///
/// What was found (2026-10-26): every "no window" report checked with System Events while the
/// screen was locked. While the session is locked, System Events lists no windows for any
/// app (Finder and the browser included) and macOS refuses to activate an app opened from a
/// script, so the window stays behind whatever is in front. WindowServer showed Cloudpane's
/// window on screen and drawing all along. The earlier development cases, where
/// WindowServer itself listed no main window, could not be reproduced with the same bundle
/// id or a separate one, and there is no saved window state in the container.
///
/// So this keeps one reliable route to the window that does not depend on AppKit's
/// restoration: SwiftUI's own openWindow action, captured by the Window menu's "Cloudpane"
/// item (Command-0), which the user can also choose by hand.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DispatchQueue.main.async { DemoData.keepWindowStateOutOfRealDefaults() }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            AppDelegate.ensureMainWindow()
            #if DEBUG
            DemoData.keepWindowStateOutOfRealDefaults()
            DemoData.applyWindowSize()
            #endif
        }
    }

    /// A Dock click or `open` while the app runs. With no visible window, bring it up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppDelegate.ensureMainWindow(unhide: true) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        DemoData.restoreRealWindowState()
        #endif
    }

    /// unhide is true for a reopen, which asks for the window; at launch an app started
    /// hidden on purpose (open -j) stays hidden.
    @MainActor
    static func ensureMainWindow(unhide: Bool = false) {
        if NSApp.isHidden {
            guard unhide else { return }
            NSApp.unhide(nil)
        }
        // The main window only: the Help window being open does not count.
        let titled = NSApp.windows.filter {
            $0.styleMask.contains(.titled) && $0.canBecomeMain
                && $0.identifier?.rawValue.hasPrefix(CloudpaneApp.mainWindowID) == true
        }
        if titled.contains(where: { $0.isVisible && !$0.isMiniaturized }) { return }
        if let window = titled.first {
            if window.isMiniaturized { window.deminiaturize(nil) }
            clampToVisibleScreen(window)
            window.makeKeyAndOrderFront(nil)
            return
        }
        // No window object at all: ask SwiftUI to open the scene.
        MainWindowOpener.shared.open()
    }

    /// Moves a window whose title bar is off every screen back onto the main screen.
    @MainActor
    static func clampToVisibleScreen(_ window: NSWindow) {
        let titleBar = NSRect(x: window.frame.minX, y: window.frame.maxY - 28, width: window.frame.width, height: 28)
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(titleBar) }),
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = NSSize(width: min(window.frame.width, screen.visibleFrame.width),
                          height: min(window.frame.height, screen.visibleFrame.height))
        window.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2,
                               y: screen.visibleFrame.midY - size.height / 2,
                               width: size.width, height: size.height), display: true)
    }
}

/// Holds SwiftUI's openWindow action for the main window, captured from the Window menu,
/// so AppKit-side code can open the scene when no window exists.
@MainActor
final class MainWindowOpener {
    static let shared = MainWindowOpener()
    private var action: OpenWindowAction?

    func capture(_ action: OpenWindowAction) { self.action = action }

    func open() {
        action?(id: CloudpaneApp.mainWindowID)
        NSApp.activate()
    }
}

/// Window > Cloudpane (Command-0): opens or brings forward the main window. Its view is
/// built with the main menu at launch, which is when the openWindow action is captured.
struct MainWindowMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = MainWindowOpener.shared.capture(openWindow)
        Button("Cloudpane") { openWindow(id: CloudpaneApp.mainWindowID) }
            .keyboardShortcut("0")
    }
}
