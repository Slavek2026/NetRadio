import SwiftUI
import AppKit

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var isQuitting = false
    private var isMinimizedToMenuBar = false

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "NetRadio")
            button.image?.isTemplate = true
            button.toolTip = AppLanguage.saved.text("NetRadio — kliknutím zobrazíte přehrávač", "NetRadio — click to show the player")
            button.target = self
            button.action = #selector(showMainWindow)
        }
        statusItem = item
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isQuitting else { return }
                NSApp.terminate(nil)
            }
        }
    }

    func markQuitting() {
        isQuitting = true
    }

    func updateLanguage(_ language: AppLanguage) {
        statusItem?.button?.toolTip = language.text(
            "NetRadio — kliknutím zobrazíte přehrávač",
            "NetRadio — click to show the player"
        )
    }

    func minimizeToMenuBar(_ window: NSWindow) {
        install()
        mainWindow = window
        isMinimizedToMenuBar = true
        window.orderOut(nil)
    }

    func restoreIfMinimizedToMenuBar() {
        guard isMinimizedToMenuBar else { return }
        showMainWindow()
    }

    @objc func showMainWindow() {
        isMinimizedToMenuBar = false
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows
        let window = mainWindow.flatMap { registered in
            windows.contains(where: { $0 === registered }) ? registered : nil
        } ?? windows.first(where: { $0.isMiniaturized && $0.canBecomeMain })
          ?? windows.first(where: { $0.canBecomeMain })
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

final class NetRadioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }
        MenuBarController.shared.install()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MenuBarController.shared.markQuitting()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MenuBarController.shared.showMainWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MenuBarController.shared.restoreIfMinimizedToMenuBar()
    }
}

@main
struct NetRadioApp: App {
    @NSApplicationDelegateAdaptor(NetRadioAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(AppLanguage.saved.text("Ukončit NetRadio", "Quit NetRadio")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
