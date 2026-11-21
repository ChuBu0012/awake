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

    // Windows
    private var settingsWindow: NSWindow?
    private var getStartedWindow: NSWindow?

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

        // First launch Get Started onboarding
        if !UserDefaults.standard.bool(forKey: "hasCompletedGetStarted") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showGetStartedWindow(force: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        model.endSession()
    }

    // MARK: - Native macOS Edit & Window Menus for Accessory App
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Awake", action: #selector(openAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Get Started Guide…", action: #selector(openGetStarted), keyEquivalent: "")
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

    @objc private func openGetStarted() {
        showGetStartedWindow(force: true)
    }

    @objc private func openAbout() {
        showSettingsWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Status Bar Item
    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        let image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Awake")
        image?.isTemplate = true
        button.image = image
        button.setAccessibilityLabel("Awake")
        button.setAccessibilityHelp("Show Awake status and controls")
        button.toolTip = "Awake"
    }

    // MARK: - Popover Configuration
    final class PopoverHostingController<Content: View>: NSHostingController<Content> {
        override func viewDidLayout() {
            super.viewDidLayout()
            let fitting = view.fittingSize
            if fitting.width > 0 && fitting.height > 0 {
                preferredContentSize = fitting
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
                    self?.showSettingsWindow()
                },
                onOpenGetStarted: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.showGetStartedWindow(force: true)
                },
                onAddApp: { [weak self] in self?.addAppRule() },
                onAddProcess: { [weak self] in self?.addProcessRule() },
                onAddSchedule: { [weak self] in self?.addScheduleRule() },
                onDismiss: { [weak self] in self?.popover.performClose(nil) }
            )
        )
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 330, height: 380)
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseTime = ProcessInfo.processInfo.systemUptime
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

        let image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: active ? "Awake active" : "Awake inactive"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
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
                popover.contentSize = NSSize(width: 330, height: max(340, min(500, fitting.height)))
            }
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: - Windows Management
    func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = AwakeSettingsView(
            model: model,
            onRerunGetStarted: { [weak self] in
                self?.settingsWindow?.close()
                self?.showGetStartedWindow(force: true)
            },
            onAddApp: { [weak self] in self?.addAppRule() },
            onAddProcess: { [weak self] in self?.addProcessRule() },
            onAddSchedule: { [weak self] in self?.addScheduleRule() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 530, height: 470),
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

    func showGetStartedWindow(force: Bool = false) {
        if !force && UserDefaults.standard.bool(forKey: "hasCompletedGetStarted") {
            return
        }

        if let window = getStartedWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let getStartedView = AwakeGetStartedView(
            model: model,
            onFinish: { [weak self] in
                self?.getStartedWindow?.close()
                self?.getStartedWindow = nil
                self?.model.refresh()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Get Started with Awake"
        window.contentView = NSHostingView(rootView: getStartedView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        getStartedWindow = window

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        if closedWindow === settingsWindow {
            settingsWindow = nil
        } else if closedWindow === getStartedWindow {
            getStartedWindow = nil
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
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            return
        }
        let appName = FileManager.default.displayName(atPath: url.path)
        model.addAppRule(name: appName, bundleID: bundleID)
        if wasPopoverShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func addProcessRule() {
        let wasPopoverShown = popover.isShown
        popover.performClose(nil)
        guard let values = prompt(
            title: "Watch a Work Process",
            message: "Enter the process name (for example: node, docker, python3). Awake keeps your Mac awake while this process is running.",
            fields: ["Process name (e.g. node)"]
        ) else {
            if wasPopoverShown, let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            return
        }

        let name = values[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            if wasPopoverShown, let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            return
        }
        model.addProcessRule(name: name)
        if wasPopoverShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func addScheduleRule() {
        let wasPopoverShown = popover.isShown
        popover.performClose(nil)
        guard let values = prompt(
            title: "Add a Weekly Schedule",
            message: "Enter weekdays and 24-hour times separated by space.\nExample: mon,tue,wed,thu,fri 22:00 06:00",
            fields: ["Weekdays start end"],
            defaults: ["mon,tue,wed,thu,fri 22:00 06:00"]
        ) else {
            if wasPopoverShown, let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            return
        }

        let parts = values[0].split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 3 else {
            model.errorMessage = "Invalid format. Expected: mon,tue,wed,thu,fri 22:00 06:00"
            if wasPopoverShown, let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            return
        }
        model.addScheduleRule(days: parts[0], start: parts[1], end: parts[2])
        if wasPopoverShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func prompt(title: String, message: String, fields: [String], defaults: [String] = []) -> [String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: max(32, fields.count * 34))

        var inputs: [NSTextField] = []
        for (index, placeholder) in fields.enumerated() {
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.placeholderString = placeholder
            if index < defaults.count && !defaults[index].isEmpty {
                field.stringValue = defaults[index]
            }
            inputs.append(field)
            stack.addArrangedSubview(field)
        }
        alert.accessoryView = stack

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return inputs.map(\.stringValue)
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
