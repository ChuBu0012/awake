import AppKit
import SwiftUI

struct AwakePopoverView: View {
    @ObservedObject var model: AwakePopoverModel
    let onOpenSettings: () -> Void
    let onAddApp: () -> Void
    let onAddProcess: () -> Void
    let onAddSchedule: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let presetDurations: [(title: String, label: String, seconds: Int)] = [
        ("∞", "Indefinite", 0),
        ("30m", "30 minutes", 1_800),
        ("1h", "1 hour", 3_600),
        ("2h", "2 hours", 7_200),
        ("4h", "4 hours", 14_400),
        ("8h", "8 hours", 28_800)
    ]

    private var currentDurationLabel: String {
        if let found = presetDurations.first(where: { $0.seconds == model.currentDuration }) {
            return found.label
        }
        let secs = model.currentDuration
        guard secs > 0 else { return "Indefinite" }
        if secs >= 3600 {
            return "\(secs / 3600) hr\(secs >= 7200 ? "s" : "")"
        }
        return "\(secs / 60) min"
    }

    private var motion: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    private var isManualOn: Bool {
        model.status?.isManualActive == true
    }

    private var isActive: Bool {
        model.status?.active == true
    }

    private var isBatterySuppressed: Bool {
        model.status?.batterySuppressed == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            if let error = model.errorMessage {
                errorBanner(error)
            }

            mainActionButton

            durationSection

            Divider()
                .padding(.vertical, 2)

            automationsSection

            Divider()
                .padding(.vertical, 2)

            batteryGuardRow

            Divider()
                .padding(.vertical, 2)

            lidSupportRow

            Divider()
                .padding(.vertical, 2)

            footerRow
        }
        .padding(14)
        .frame(width: 340, alignment: .top)
        .onExitCommand(perform: onDismiss)
    }

    // MARK: - Header
    private var statusHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusBadgeBackground)
                    .frame(width: 38, height: 38)

                Image(systemName: statusIconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(statusIconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    assertionStatusIndicator
                }

                Text(statusDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.primary.opacity(0.04), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Open Settings (⌘,)")
        }
    }

    private var statusTitle: String {
        if model.isThermalThrottled { return "Paused by Heat" }
        guard let status = model.status else { return "Awake" }
        if status.batterySuppressed { return "Paused by Battery" }
        if status.active { return "Awake Active" }
        return "Awake Inactive"
    }

    private var statusDetail: String {
        if model.isThermalThrottled {
            return "Thermal Guard • High Mac temperature"
        }
        guard let status = model.status else { return "Checking sleep assertions…" }
        if status.batterySuppressed {
            return "Battery Guard • Below 20% on battery"
        }
        if let timeFormatted = model.timeRemainingFormatted, isManualOn {
            return "Manual timer active • \(timeFormatted) remaining"
        }
        return status.activeReasonSummary
    }

    private var statusBadgeBackground: Color {
        if model.isThermalThrottled || isBatterySuppressed {
            return Color.orange.opacity(0.18)
        } else if isActive {
            return Color.green.opacity(0.18)
        } else {
            return Color.secondary.opacity(0.12)
        }
    }

    private var statusIconName: String {
        if model.isThermalThrottled {
            return "thermometer.sun.fill"
        } else if isBatterySuppressed {
            return "pause.fill"
        } else if isActive {
            return "eye.fill"
        } else {
            return "moon.zzz.fill"
        }
    }

    private var statusIconColor: Color {
        if model.isThermalThrottled || isBatterySuppressed {
            return .orange
        } else if isActive {
            return .green
        } else {
            return .secondary
        }
    }

    private var assertionStatusIndicator: some View {
        let isPaused = model.isThermalThrottled || isBatterySuppressed
        let dotColor: Color = isPaused ? .orange : (isActive ? .green : .secondary.opacity(0.4))
        let textColor: Color = isPaused ? .orange : (isActive ? .green : .secondary)
        let labelText: String = isPaused ? "Paused" : (isActive ? "Asserted" : "Idle")

        return HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(labelText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.04), in: Capsule())
    }

    // MARK: - Error Banner
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(3)

            Spacer()

            Button(action: { model.clearError() }) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Main Action Button
    private var mainActionButton: some View {
        Button {
            model.toggleAwake()
        } label: {
            HStack(spacing: 8) {
                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isManualOn ? "moon.zzz.fill" : "eye.fill")
                        .font(.body.weight(.semibold))
                }

                Text(model.isBusy ? "Updating…" : (isManualOn ? "Turn Off Awake" : "Turn On Awake"))
                    .font(.body.weight(.semibold))

                Spacer()

                Text("⌘T")
                    .font(.caption.weight(.medium))
                    .opacity(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isManualOn ? .secondary : .accentColor)
        .disabled(model.isBusy)
        .accessibilityHint(isManualOn ? "Turns off sleep prevention" : "Prevents this Mac from sleeping")
    }

    // MARK: - Duration Selector
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Duration", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let timeFormatted = model.timeRemainingFormatted, isManualOn {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text(timeFormatted)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.accentColor)
                } else {
                    Text(currentDurationLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 4) {
                ForEach(presetDurations, id: \.seconds) { item in
                    let isSelected = model.currentDuration == item.seconds
                    Button {
                        model.selectDuration(item.seconds)
                    } label: {
                        Text(item.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                    .help(item.label)
                    .accessibilityLabel(item.label)
                }
            }
        }
    }

    // MARK: - Automations
    private var automationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Automations", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))

                if let count = model.status?.rules.count, count > 0 {
                    let activeCount = model.status?.rules.filter(\.enabled).count ?? 0
                    Text("\(activeCount)/\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                }

                Spacer()

                Menu {
                    Button("Watch an App is open…", action: onAddApp)
                    Button("Watch a Work process runs…", action: onAddProcess)
                    Button("Add a Weekly schedule…", action: onAddSchedule)
                    Divider()
                    Button("Manage all rules in Settings…", action: onOpenSettings)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.04), in: Circle())
                }
                .menuStyle(.borderlessButton)
                .help("Add an automation rule")
            }

            if let rules = model.status?.rules, !rules.isEmpty {
                VStack(spacing: 6) {
                    ForEach(rules, id: \.id) { rule in
                        automationRow(rule)
                    }
                }
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.slash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("No automation rules configured yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func automationRow(_ rule: AwakeStatus.Rule) -> some View {
        let isAct = isRuleActive(rule)
        let appOpen = isAppOpen(for: rule)
        let statusCol = ruleStatusColor(rule, isActive: isAct, isAppOpen: appOpen)

        return HStack(spacing: 8) {
            Image(systemName: ruleIcon(rule.kind))
                .font(.system(size: 13))
                .foregroundColor(isAct ? Color(red: 0.2, green: 0.78, blue: 0.35) : (rule.enabled ? .accentColor : .secondary))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                HStack(spacing: 6) {
                    Text(ruleKindDescription(rule.kind))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Circle()
                        .fill(statusCol)
                        .frame(width: 6, height: 6)
                        .help(ruleStatusTooltip(rule, isActive: isAct, isAppOpen: appOpen))
                }
            }

            Spacer(minLength: 4)

            Button {
                model.performRuleAction(rule.enabled ? "disable" : "enable", ruleID: rule.id)
            } label: {
                Image(systemName: rule.enabled ? "pause.circle" : "play.circle")
                    .font(.system(size: 15))
                    .foregroundColor(rule.enabled ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .help(rule.enabled ? "Pause rule" : "Enable rule")

            Menu {
                Button(rule.enabled ? "Pause Rule" : "Enable Rule") {
                    model.performRuleAction(rule.enabled ? "disable" : "enable", ruleID: rule.id)
                }
                Divider()
                Button("Delete Rule", role: .destructive) {
                    model.performRuleAction("remove", ruleID: rule.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(3)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
    }

    private func isRuleActive(_ rule: AwakeStatus.Rule) -> Bool {
        if rule.active == true { return true }
        return model.status?.requests.contains(where: { $0.id == "rule:\(rule.id)" }) == true
    }

    private func isAppOpen(for rule: AwakeStatus.Rule) -> Bool {
        if rule.appOpen == true { return true }
        let running = NSWorkspace.shared.runningApplications
        if let bID = rule.bundleID, running.contains(where: { $0.bundleIdentifier == bID }) {
            return true
        }
        let lower = rule.name.lowercased()
        if lower.contains("visual studio code") || lower.contains("code") {
            return running.contains(where: { $0.bundleIdentifier == "com.microsoft.VSCode" || $0.bundleIdentifier == "com.microsoft.VSCodeInsiders" })
        }
        if lower.contains("cursor") {
            return running.contains(where: { $0.bundleIdentifier == "com.todesktop.230313mzl4w4u92" })
        }
        if lower.contains("claude") {
            return running.contains(where: { $0.bundleIdentifier == "com.anthropic.claude-desktop" })
        }
        if lower.contains("chatgpt") {
            return running.contains(where: { $0.bundleIdentifier == "com.openai.chat" })
        }
        if lower.contains("antigravity") {
            return running.contains(where: { $0.bundleIdentifier == "com.google.antigravity" })
        }
        if lower.contains("xcode") {
            return running.contains(where: { $0.bundleIdentifier == "com.apple.dt.Xcode" })
        }
        if lower.contains("iterm") {
            return running.contains(where: { $0.bundleIdentifier == "com.googlecode.iterm2" })
        }
        if lower.contains("terminal") {
            return running.contains(where: { $0.bundleIdentifier == "com.apple.Terminal" })
        }
        if lower.contains("ghostty") {
            return running.contains(where: { $0.bundleIdentifier == "com.mitchellh.ghostty" })
        }
        if lower.contains("warp") {
            return running.contains(where: { $0.bundleIdentifier == "dev.warp.Warp-Stable" })
        }
        if lower.contains("docker") {
            return running.contains(where: { $0.bundleIdentifier == "com.docker.docker" })
        }
        if lower.contains("orbstack") {
            return running.contains(where: { $0.bundleIdentifier == "dev.kdrag0n.OrbStack" || $0.bundleIdentifier == "dev.kdrag0n.MacVirt" })
        }
        return false
    }

    private func ruleStatusColor(_ rule: AwakeStatus.Rule, isActive: Bool, isAppOpen: Bool) -> Color {
        guard rule.enabled else { return .secondary.opacity(0.6) }
        if isActive {
            return Color(red: 0.2, green: 0.78, blue: 0.35)
        }
        if rule.kind == "work_process" && isAppOpen {
            return Color.orange
        }
        return .secondary.opacity(0.5)
    }

    private func ruleStatusTooltip(_ rule: AwakeStatus.Rule, isActive: Bool, isAppOpen: Bool) -> String {
        guard rule.enabled else { return "Rule paused" }
        switch rule.kind {
        case "work_process":
            if isActive {
                return "Agent / Task running (Active)"
            } else if isAppOpen {
                return "App open, idle"
            } else {
                return "App closed"
            }
        case "app_open":
            if isActive {
                return "App is open (Active)"
            } else {
                return "App closed"
            }
        case "schedule":
            if isActive {
                return "Schedule active"
            } else {
                return "Outside schedule"
            }
        default:
            return isActive ? "Active" : "Inactive"
        }
    }

    private func ruleIcon(_ kind: String) -> String {
        switch kind {
        case "schedule": return "calendar"
        case "app_open": return "app.badge.checkmark"
        default: return "terminal"
        }
    }

    private func ruleKindDescription(_ kind: String) -> String {
        switch kind {
        case "schedule": return "Schedule"
        case "app_open": return "App is open"
        default: return "Work process"
        }
    }

    // MARK: - Battery Guard
    private var batteryGuardRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.25percent")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Battery Guard")
                    .font(.system(size: 12, weight: .medium))
                Text("Pause sleep prevention below 20% on battery")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { model.status?.batteryGuardEnabled == true },
                set: { _ in model.toggleBatteryGuard() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .disabled(model.isBusy)
        }
    }

    // MARK: - Lid-Closed Support Row
    private var lidSupportRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Lid-closed Support")
                        .font(.system(size: 12, weight: .medium))
                    if model.sudoersConfigured && model.status?.lidSupportEnabled == true && isActive {
                        Text("Active")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                Text("Lock sleep even when lid is closed (pmset)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if model.sudoersConfigured {
                Toggle("", isOn: Binding(
                    get: { model.status?.lidSupportEnabled == true },
                    set: { _ in model.toggleLidSupport() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(model.isBusy)
            } else {
                Button("Grant…") {
                    model.requestSudoersPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Grant one-time permission to allow sleep prevention with lid closed")
            }
        }
    }

    // MARK: - Footer
    private var footerRow: some View {
        HStack {
            Button(action: onOpenSettings) {
                Label("Settings…", systemImage: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit Awake", systemImage: "power")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .foregroundColor(.secondary)
    }
}
