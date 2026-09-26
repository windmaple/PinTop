import Cocoa
import SwiftUI

@main
@MainActor
struct PinTopMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = PinManager.shared

        setupStatusItem()
        setupPopover()
        setupMainWindow()

        manager.onPinnedCountChanged = { [weak self] count in
            self?.updateStatusItemBadge(count: count)
        }

        // Show the main control center window on launch so it is immediately accessible
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar even if the main dashboard window is closed
        return false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "PinTop")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = " PinTop"
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func updateStatusItemBadge(count: Int) {
        guard let button = statusItem.button else { return }
        if count > 0 {
            button.title = " \(count)"
        } else {
            button.title = " PinTop"
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 560, height: 580)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(manager: .shared, isPopover: true)
        )
    }

    private func setupMainWindow() {
        let contentView = DashboardView(manager: .shared, isPopover: false)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PinTop — Always on Top Window Manager"
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        self.mainWindow = window
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "🎯 Pick Window on Screen (⌃⌥K)", action: #selector(menuPickWindow), keyEquivalent: "")
            menu.addItem(withTitle: "📌 Pin Active Window (⌃⌥P)", action: #selector(menuPinActive), keyEquivalent: "")
            menu.addItem(withTitle: "👻 Toggle Ghost Click-Through (⌃⌥G)", action: #selector(menuToggleGhost), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Open PinTop Dashboard", action: #selector(showMainWindow), keyEquivalent: "")
            menu.addItem(withTitle: "Unpin All Windows (⌃⌥U)", action: #selector(menuUnpinAll), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Quit PinTop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

            for item in menu.items {
                if item.target == nil && item.action != #selector(NSApplication.terminate(_:)) {
                    item.target = self
                }
            }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSView) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            PinManager.shared.refreshWindows()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func showMainWindow() {
        PinManager.shared.refreshWindows()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuPickWindow() {
        popover.performClose(nil)
        PinManager.shared.startInteractiveWindowPicker()
    }

    @objc private func menuPinActive() {
        PinManager.shared.togglePinForActiveWindow()
    }

    @objc private func menuToggleGhost() {
        PinManager.shared.toggleGhostModeForAll()
    }

    @objc private func menuUnpinAll() {
        PinManager.shared.unpinAll()
    }
}
