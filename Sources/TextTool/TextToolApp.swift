import AppKit
import SwiftUI
import TextToolCore

@main
@MainActor
enum TextToolMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSDraggingDestination, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = ClipboardModel()
    private let updater = Updater()
    private var eventMonitors: [Any] = []
    private var draggedSinceMouseDown = false
    /// True between an outside mouse-down and its mouse-up. The mouse-up of the click that
    /// opened the popover has no matching mouse-down here, so it never closes the popover.
    private var outsideMouseIsDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Text Tool")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Text Tool"
            // Accept images and text dropped onto the menu bar icon. The status item's
            // window forwards drag events to its delegate.
            button.window?.registerForDraggedTypes([.fileURL, .png, .tiff, .string])
            button.window?.delegate = self
        }

        let hosting = NSHostingController(rootView: PopoverView(model: model, updater: updater))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        // Closed manually (see startMonitors) so it can stay open while you drag a file into it.
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.animates = true

        installEditMenu()
        model.startWatching()
        TextRecognizer.warmUp()
        updater.scheduleAutomaticChecks()

        // `--show` opens the popover at launch (handy for testing).
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePopover(nil) }
        }
    }

    /// Menu bar apps have no visible menu, but key equivalents like ⌘C and ⌘A are
    /// only delivered through the main menu, so install a (hidden) Edit menu.
    private func installEditMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let paste = editMenu.addItem(withTitle: "Paste into Text Tool", action: #selector(pasteIntoTextTool(_:)), keyEquivalent: "v")
        paste.target = self
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem(title: "Text Tool", action: nil, keyEquivalent: ""))
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func pasteIntoTextTool(_ sender: Any?) {
        model.pasteFromClipboard()
        showPopover()
    }

    // MARK: - Dropping onto the menu bar icon

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        statusItem.button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        statusItem.button?.highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(false)
        guard model.ingest(from: sender.draggingPasteboard) else { return false }
        showPopover()
        return true
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        model.refresh()
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startMonitors()
    }

    /// Closes the popover on a plain click elsewhere, but keeps it open when the mouse is
    /// dragged in another app (so a file can be dragged from Finder into the popover). Esc closes it.
    private func startMonitors() {
        stopMonitors()
        outsideMouseIsDown = false
        draggedSinceMouseDown = false
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleOutsideMouse(type) }
        }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            let closed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.popover.isShown else { return false }
                self.popover.performClose(nil)
                return true
            }
            return closed ? nil : event
        }) {
            eventMonitors.append(local)
        }
    }

    private func handleOutsideMouse(_ type: NSEvent.EventType) {
        // Clicks on our own menu bar icon are handled by togglePopover.
        if let frame = statusItem.button?.window?.frame, frame.contains(NSEvent.mouseLocation) { return }
        switch type {
        case .leftMouseDown:
            outsideMouseIsDown = true
            draggedSinceMouseDown = false
        case .leftMouseDragged:
            draggedSinceMouseDown = true
        case .leftMouseUp:
            let wasClick = outsideMouseIsDown && !draggedSinceMouseDown
            outsideMouseIsDown = false
            if wasClick { popover.performClose(nil) }
        case .rightMouseDown:
            popover.performClose(nil)
        default:
            break
        }
    }

    private func stopMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitors()
    }
}
