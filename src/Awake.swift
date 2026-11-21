import AppKit
import Foundation
import UniformTypeIdentifiers

private struct AwakeStatus: Decodable {
    struct Lease: Decodable {
        let id: String
        let source: String
        let reason: String
        let expiresAt: Date?
        enum CodingKeys: String, CodingKey { case id, source, reason; case expiresAt = "expires_at" }
    }
    struct Rule: Decodable {
        let id: String
        let name: String
        let kind: String
        let enabled: Bool
    }
    let active: Bool
    let batterySuppressed: Bool
    let batteryGuardEnabled: Bool
    let lidSupportEnabled: Bool
    let snoozedUntil: Date?
    let requests: [Lease]
    let rules: [Rule]
    let recoveryPending: Bool
    enum CodingKeys: String, CodingKey {
        case active, requests, rules
        case batterySuppressed = "battery_suppressed"
        case batteryGuardEnabled = "battery_guard_enabled"
        case lidSupportEnabled = "lid_support_enabled"
        case snoozedUntil = "snoozed_until"
        case recoveryPending = "recovery_pending"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var busy = false
    private var lastCommandSucceeded = false
    private var status: AwakeStatus?
    private var currentDuration = 0
    private var statusItemTitle: NSMenuItem!
    private var detailItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var batteryItem: NSMenuItem!
    private var automationMenu: NSMenu!
    private var durationMenu: NSMenu!
    private let workQueue = DispatchQueue(label: "app.awake.cli", qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        buildMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = runCLI(["session-end"])
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Awake")
        let menu = NSMenu()
        statusItemTitle = NSMenuItem(title: "Awake", action: nil, keyEquivalent: "")
        statusItemTitle.isEnabled = false
        menu.addItem(statusItemTitle)
        detailItem = NSMenuItem(title: "Loading status…", action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        menu.addItem(detailItem)
        menu.addItem(.separator())
        toggleItem = NSMenuItem(title: "Turn On Awake", action: #selector(toggleAwake), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let durationParent = NSMenuItem(title: "Duration", action: nil, keyEquivalent: "")
        durationMenu = NSMenu()
        for (title, seconds) in [("Until stopped", 0), ("30 minutes", 1800), ("1 hour", 3600), ("2 hours", 7200), ("4 hours", 14400), ("8 hours", 28800)] {
            let item = NSMenuItem(title: title, action: #selector(selectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            durationMenu.addItem(item)
        }
        durationParent.submenu = durationMenu
        menu.addItem(durationParent)
        menu.addItem(.separator())

        let automationParent = NSMenuItem(title: "Automations", action: nil, keyEquivalent: "")
        automationMenu = NSMenu()
        let addApp = NSMenuItem(title: "Keep Awake while an app is open…", action: #selector(addAppRule), keyEquivalent: "")
        addApp.target = self
        automationMenu.addItem(addApp)
        let addProcess = NSMenuItem(title: "Keep Awake while a work process runs…", action: #selector(addProcessRule), keyEquivalent: "")
        addProcess.target = self
        automationMenu.addItem(addProcess)
        let addSchedule = NSMenuItem(title: "Add a schedule…", action: #selector(addScheduleRule), keyEquivalent: "")
        addSchedule.target = self
        automationMenu.addItem(addSchedule)
        automationMenu.addItem(.separator())
        automationParent.submenu = automationMenu
        menu.addItem(automationParent)

        batteryItem = NSMenuItem(title: "Battery Guard", action: #selector(toggleBatteryGuard), keyEquivalent: "")
        batteryItem.target = self
        menu.addItem(batteryItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Awake", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func refresh() {
        guard !busy else { return }
        busy = true
        let bundles = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }.filter { !$0.isEmpty }
        var args = ["tick", "--automation-owner-pid", "\(ProcessInfo.processInfo.processIdentifier)"]
        for bundle in Set(bundles) { args += ["--bundle-id", bundle] }
        workQueue.async { [weak self] in
            guard let self else { return }
            _ = self.runCLI(args)
            let output = self.runCLI(["status", "--json"])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = fractional.date(from: value) { return date }
                let standard = ISO8601DateFormatter()
                standard.formatOptions = [.withInternetDateTime]
                if let date = standard.date(from: value) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RFC3339 date: \(value)")
            }
            let decoded = output.data(using: .utf8).flatMap { try? decoder.decode(AwakeStatus.self, from: $0) }
            DispatchQueue.main.async {
                self.busy = false
                if let decoded {
                    self.status = decoded
                    if let lease = decoded.requests.first(where: { $0.source == "manual" }), let expires = lease.expiresAt {
                        self.currentDuration = max(0, Int(expires.timeIntervalSinceNow))
                    } else if decoded.requests.contains(where: { $0.source == "manual" }) {
                        self.currentDuration = 0
                    }
                    self.renderStatus()
                } else {
                    self.detailItem.title = "Status unavailable — check Awake installation"
                }
            }
        }
    }

    private func renderStatus() {
        guard let status else { return }
        if status.batterySuppressed {
            statusItemTitle.title = "Awake is paused by Battery Guard"
        } else {
            statusItemTitle.title = status.active ? "Awake is preventing sleep" : "Awake is inactive"
        }
        let reasons = status.requests.map(\.reason).filter { !$0.isEmpty }
        detailItem.title = reasons.isEmpty ? "No active requests" : reasons.joined(separator: ", ")
        toggleItem.title = status.requests.contains(where: { $0.source == "manual" }) ? "Turn Off Awake (snooze automations)" : "Turn On Awake"
        batteryItem.state = status.batteryGuardEnabled ? .on : .off
        statusItem.button?.image = NSImage(systemSymbolName: status.active ? "eye" : "moon.zzz", accessibilityDescription: status.active ? "Awake active" : "Awake inactive")
        for item in durationMenu.items { item.state = item.tag == currentDuration ? .on : .off }
        renderRules()
    }

    private func runCLI(_ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: findCLI())
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            lastCommandSucceeded = process.terminationStatus == 0
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            lastCommandSucceeded = false
            return ""
        }
    }

    private func findCLI() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundledCLI = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/awake", isDirectory: false)
            .path
        let candidates = [bundledCLI, "\(home)/.local/bin/awake", "/usr/local/bin/awake", "/opt/homebrew/bin/awake"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "/usr/bin/false"
    }

    private func perform(_ arguments: [String]) {
        workQueue.async { [weak self] in
            guard let self else { return }
            let output = self.runCLI(arguments)
                .replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let succeeded = self.lastCommandSucceeded
            DispatchQueue.main.async {
                if !succeeded {
                    let detail = output.isEmpty ? "Check the installation and permissions." : output
                    self.showError("Awake command failed.\n\n\(detail)")
                }
                self.refresh()
            }
        }
    }

    @objc private func toggleAwake() {
        if status?.requests.contains(where: { $0.source == "manual" }) == true {
            perform(["off"])
        } else {
            var args = ["on"]
            if currentDuration > 0 { args.append("\(currentDuration)s") } else { args.append("indefinite") }
            args += ["--owner-pid", "\(ProcessInfo.processInfo.processIdentifier)"]
            perform(args)
        }
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        currentDuration = sender.tag
        if status?.requests.contains(where: { $0.source == "manual" }) == true {
            let duration = sender.tag > 0 ? "\(sender.tag)s" : "indefinite"
            let args = ["on", duration, "--owner-pid", "\(ProcessInfo.processInfo.processIdentifier)"]
            perform(args)
        } else { renderStatus() }
    }

    @objc private func toggleBatteryGuard() {
        let enabled = status?.batteryGuardEnabled != true
        perform(["set", "battery-guard", enabled ? "on" : "off"])
    }

    @objc private func addAppRule() {
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
        let name = FileManager.default.displayName(atPath: url.path)
        let id = "app-" + UUID().uuidString.lowercased()
        perform(["rule", "app", id, name, bundleID])
    }

    @objc private func addProcessRule() {
        guard let values = prompt(title: "Watch a work process", message: "Enter the exact process name (for example: node). This matches the process while it is running.", fields: ["Process name"]) else { return }
        let name = values[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { showError("Enter a process name."); return }
        perform(["rule", "process", "process-\(UUID().uuidString.lowercased())", name, name])
    }

    @objc private func addScheduleRule() {
        guard let values = prompt(title: "Add a schedule", message: "Enter weekdays and 24-hour times. Example: mon,tue,wed,thu,fri 22:00 02:00. Overnight schedules use the day they start.", fields: ["Days start end"]) else { return }
        let parts = values[0].split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 3 else { showError("Use: mon,tue,wed,thu,fri 22:00 02:00"); return }
        perform(["rule", "schedule", "schedule-\(UUID().uuidString.lowercased())", "Schedule (\(parts[0]))", parts[0], parts[1], parts[2]])
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

    private func renderRules() {
        guard let status else { return }
        while automationMenu.numberOfItems > 4 { automationMenu.removeItem(at: 4) }
        guard !status.rules.isEmpty else {
            let empty = NSMenuItem(title: "No automations yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            automationMenu.addItem(empty)
            return
        }
        for rule in status.rules {
            let parent = NSMenuItem(title: "\(rule.enabled ? "✓" : "○") \(rule.name)", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let toggle = NSMenuItem(title: rule.enabled ? "Pause" : "Enable", action: #selector(ruleAction(_:)), keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = [rule.id, rule.enabled ? "disable" : "enable"]
            submenu.addItem(toggle)
            let remove = NSMenuItem(title: "Remove", action: #selector(ruleAction(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = [rule.id, "remove"]
            submenu.addItem(remove)
            parent.submenu = submenu
            automationMenu.addItem(parent)
        }
    }

    @objc private func ruleAction(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [String], values.count == 2 else { return }
        perform(["rule", values[1], values[0]])
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Awake"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
