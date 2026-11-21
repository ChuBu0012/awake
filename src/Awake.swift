import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timer: Timer?
    private let model = AwakePopoverModel()
    private var statusObservation: AnyCancellable?
    private var lastPopoverCloseTime: TimeInterval = 0
    private var globalEventMonitor: Any?

    // Windows
    private let settingsState = AwakeSettingsModel()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureMainMenu()
        configureStatusItem()
        configurePopover()

        statusObservation = model.$status.sink { [weak self] status in
            self?.updateStatusItem(for: status)
        }

        model.refresh()
        let refreshTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.model.refresh()
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        self.timer = refreshTimer
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        stopEventMonitor()
        model.endSession()
    }

    // MARK: - Native macOS Edit & Window Menus for Accessory App
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Awake", action: #selector(openAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Awake", action: #selector(quitApp), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Edit Menu (vital for Copy, Paste, Select All in textfields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func openPreferences() {
        showSettingsWindow()
    }

    @objc private func openAbout() {
        showSettingsWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Menu Bar Fixed-Canvas Icon Generator
    static func makeMenuBarIcon(symbolName: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            let fallback = NSImage(size: NSSize(width: 18, height: 18))
            fallback.isTemplate = true
            return fallback
        }
        let targetSize = NSSize(width: 18, height: 18)
        let finalImage = NSImage(size: targetSize, flipped: false) { _ in
            let symSize = base.size
            let scale = min(targetSize.width / max(symSize.width, 1), targetSize.height / max(symSize.height, 1), 1.0)
            let drawSize = NSSize(width: round(symSize.width * scale), height: round(symSize.height * scale))
            let origin = NSPoint(
                x: round((targetSize.width - drawSize.width) / 2.0),
                y: round((targetSize.height - drawSize.height) / 2.0)
            )
            base.draw(in: NSRect(origin: origin, size: drawSize))
            return true
        }
        finalImage.isTemplate = true
        return finalImage
    }

    // MARK: - Status Bar Item
    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.image = AppDelegate.makeMenuBarIcon(symbolName: "moon.zzz")
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("Awake")
        button.setAccessibilityHelp("Show Awake status and controls")
        button.toolTip = "Awake"
    }

    // MARK: - Popover Configuration
    final class PopoverHostingController<Content: View>: NSHostingController<Content> {
        var onFittingSizeChange: ((NSSize) -> Void)?

        override func viewDidLayout() {
            super.viewDidLayout()
            let fitting = view.fittingSize
            if fitting.width > 0 && fitting.height > 0 {
                let target = NSSize(width: 340, height: ceil(fitting.height))
                preferredContentSize = target
                onFittingSizeChange?(target)
            }
        }
    }

    private func configurePopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false // Disabled to avoid position jumps and arrow clipping
        popover.delegate = self

        let controller = PopoverHostingController(
            rootView: AwakePopoverView(
                model: model,
                onOpenSettings: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.showSettingsWindow(tab: .general)
                },
                onAddApp: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.showSettingsWindow(tab: .automations, openAddRuleType: 0)
                },
                onAddProcess: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.showSettingsWindow(tab: .automations, openAddRuleType: 1)
                },
                onAddSchedule: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.showSettingsWindow(tab: .automations, openAddRuleType: 2)
                },
                onDismiss: { [weak self] in self?.popover.performClose(nil) }
            )
        )
        controller.onFittingSizeChange = { [weak self] size in
            guard let self = self, self.popover.isShown else { return }
            let current = self.popover.contentSize
            if abs(current.height - size.height) >= 2.0 || current.width != 340 {
                self.popover.contentSize = NSSize(width: 340, height: size.height)
            }
        }
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 340, height: 420)
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseTime = ProcessInfo.processInfo.systemUptime
        stopEventMonitor()
    }

    private func updateStatusItem(for status: AwakeStatus?) {
        let active = status?.active == true
        let suppressed = status?.batterySuppressed == true

        let iconName: String
        if suppressed {
            iconName = "pause.circle.fill"
        } else if active {
            iconName = "eye.fill"
        } else {
            iconName = "moon.zzz"
        }

        let image = AppDelegate.makeMenuBarIcon(symbolName: iconName)
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel(active ? "Awake active" : "Awake inactive")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        let now = ProcessInfo.processInfo.systemUptime

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // Avoid re-opening immediately if popover just closed from clicking status item
        if now - lastPopoverCloseTime < 0.25 {
            return
        }

        model.refresh()
        if let controller = popover.contentViewController {
            let fitting = controller.view.fittingSize
            if fitting.width > 0 && fitting.height > 0 {
                popover.contentSize = NSSize(width: 340, height: ceil(fitting.height))
            }
        }
        showPopover(relativeTo: button)
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startEventMonitor()
    }

    private func startEventMonitor() {
        if globalEventMonitor != nil { return }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }
            DispatchQueue.main.async {
                self.popover.performClose(nil)
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    // MARK: - Windows Management
    func showSettingsWindow(tab: AwakeSettingsModel.SettingsTab = .general, openAddRuleType: Int? = nil) {
        settingsState.selectedTab = tab
        if let type = openAddRuleType {
            settingsState.addRuleType = type
            settingsState.showingAddRuleSheet = true
            if type == 1 {
                settingsState.scanRunningProcesses()
            }
        }

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = AwakeSettingsView(
            model: model,
            settingsState: settingsState,
            onAddApp: { [weak self] in self?.addAppRule() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Awake Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        if closedWindow === settingsWindow {
            settingsWindow = nil
        }
    }

    // MARK: - Rules Actions
    private func addAppRule() {
        let wasPopoverShown = popover.isShown
        popover.performClose(nil)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch App"

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else {
            if panel.url != nil {
                model.errorMessage = "The selected application does not have a valid bundle identifier."
            }
            if wasPopoverShown, let button = statusItem.button {
                showPopover(relativeTo: button)
            }
            return
        }
        let appName = FileManager.default.displayName(atPath: url.path)
        model.addAppRule(name: appName, bundleID: bundleID)
        if wasPopoverShown, let button = statusItem.button {
            showPopover(relativeTo: button)
        }
    }
}

@main
struct AwakeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
