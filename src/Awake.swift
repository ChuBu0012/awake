import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timer: Timer?
    private let model = AwakePopoverModel()
    private var statusObservation: AnyCancellable?
    private var errorObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        statusObservation = model.$status.sink { [weak self] status in
            self?.updateStatusItem(for: status)
        }
        errorObservation = model.$errorMessage.compactMap { $0 }.sink { [weak self] message in
            self?.showError("Awake command failed.\n\n\(message)")
        }
        model.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.model.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.endSession()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Awake")
        button.setAccessibilityLabel("Awake")
        button.setAccessibilityHelp("Show Awake status and controls")
        button.toolTip = "Awake"
    }

    private func configurePopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 470)
        popover.contentViewController = NSHostingController(
            rootView: AwakePopoverView(
                model: model,
                onAddApp: { [weak self] in self?.addAppRule() },
                onAddProcess: { [weak self] in self?.addProcessRule() },
                onAddSchedule: { [weak self] in self?.addScheduleRule() },
                onDismiss: { [weak self] in self?.popover.performClose(nil) }
            )
        )
    }

    private func updateStatusItem(for status: AwakeStatus?) {
        let active = status?.active == true
        statusItem.button?.image = NSImage(
            systemSymbolName: active ? "eye" : "moon.zzz",
            accessibilityDescription: active ? "Awake active" : "Awake inactive"
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func addAppRule() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch App"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else {
            if panel.url != nil { showError("This app does not have a bundle identifier.") }
            return
        }
        model.addAppRule(name: FileManager.default.displayName(atPath: url.path), bundleID: bundleID)
    }

    private func addProcessRule() {
        guard let values = prompt(
            title: "Watch a work process",
            message: "Enter the exact process name (for example: node). This matches the process while it is running.",
            fields: ["Process name"]
        ) else { return }
        let name = values[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { showError("Enter a process name."); return }
        model.addProcessRule(name: name)
    }

    private func addScheduleRule() {
        guard let values = prompt(
            title: "Add a schedule",
            message: "Enter weekdays and 24-hour times. Example: mon,tue,wed,thu,fri 22:00 02:00. Overnight schedules use the day they start.",
            fields: ["Days start end"]
        ) else { return }
        let parts = values[0].split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 3 else { showError("Use: mon,tue,wed,thu,fri 22:00 02:00"); return }
        model.addScheduleRule(days: parts[0], start: parts[1], end: parts[2])
    }

    private func prompt(title: String, message: String, fields: [String]) -> [String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        var inputs: [NSTextField] = []
        for placeholder in fields {
            let field = NSTextField(string: "")
            field.placeholderString = placeholder
            inputs.append(field)
            stack.addArrangedSubview(field)
        }
        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return inputs.map(\.stringValue)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Awake"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
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
