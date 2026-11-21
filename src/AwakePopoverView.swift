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

    private let durations: [(title: String, seconds: Int)] = [
        ("Until stopped", 0),
        ("30 minutes", 1_800),
        ("1 hour", 3_600),
        ("2 hours", 7_200),
        ("4 hours", 14_400),
        ("8 hours", 28_800)
    ]

    private var motion: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    private var isManualOn: Bool {
        model.status?.requests.contains(where: { $0.source == "manual" }) == true
    }

    private var statusTitle: String {
        guard let status = model.status else { return "Loading Awake status…" }
        if status.batterySuppressed { return "Paused by Battery Guard" }
        return status.active ? "Awake is preventing sleep" : "Awake is inactive"
    }

    private var statusDetail: String {
        guard let status = model.status else { return "Checking this Mac" }
        let reasons = status.requests.map(\.reason).filter { !$0.isEmpty }
        if !reasons.isEmpty { return reasons.joined(separator: ", ") }
        if status.recoveryPending { return "A sleep setting needs recovery" }
        return "No active requests"
    }

    private var durationTitle: String {
        if let selected = durations.first(where: { $0.seconds == model.currentDuration }) {
            return selected.title
        }
        let remaining = model.currentDuration
        guard remaining > 0 else { return "Until stopped" }
        if remaining >= 3_600 { return "About \(max(1, remaining / 3_600)) hours" }
        return "About \(max(1, remaining / 60)) minutes"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            Button {
                model.toggleAwake()
            } label: {
                Label(isManualOn ? "Turn Off Awake" : "Turn On Awake", systemImage: isManualOn ? "moon.zzz.fill" : "eye.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("t", modifiers: .command)
            .accessibilityHint(isManualOn ? "Turns off Manual On and snoozes automations for 30 minutes" : "Prevents this Mac from sleeping")

            Menu {
                ForEach(durations, id: \.seconds) { duration in
                    Button {
                        model.selectDuration(duration.seconds)
                    } label: {
                        if model.currentDuration == duration.seconds {
                            Label(duration.title, systemImage: "checkmark")
                        } else {
                            Text(duration.title)
                        }
                    }
                }
            } label: {
                HStack {
                    Label("Duration", systemImage: "clock")
                    Spacer()
                    Text(durationTitle)
                        .foregroundColor(.secondary)
                        .id(durationTitle)
                        .transition(reduceMotion ? .identity : .opacity)
                        .animation(motion, value: durationTitle)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Duration, \(durationTitle)")

            Divider()

            HStack {
                Text("Automations").font(.headline)
                Spacer()
                Menu {
                    Button("Keep Awake while an app is open…", action: onAddApp)
                    Button("Keep Awake while a work process runs…", action: onAddProcess)
                    Button("Add a schedule…", action: onAddSchedule)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Add automation")
            }

            automationList
                .animation(motion, value: model.status?.rules ?? [])

            Divider()

            Button {
                model.toggleBatteryGuard()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery Guard")
                        Text("Pause sleep prevention below 20% on battery")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: model.status?.batteryGuardEnabled == true ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(model.status?.batteryGuardEnabled == true ? .accentColor : .secondary)
                        .id(model.status?.batteryGuardEnabled == true)
                        .transition(reduceMotion ? .identity : .opacity)
                        .animation(motion, value: model.status?.batteryGuardEnabled)
                } icon: {
                    Image(systemName: "battery.25percent")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Battery Guard")
            .accessibilityValue(model.status?.batteryGuardEnabled == true ? "On" : "Off")

            Divider()

            HStack {
                Button(action: onOpenSettings) {
                    Label("Settings…", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Settings")

                Spacer()

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Label("Quit Awake", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel("Quit Awake")
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .top)
        .onExitCommand(perform: onDismiss)
    }

    private var statusHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.status?.active == true ? "eye.fill" : "moon.zzz")
                .font(.title3)
                .foregroundColor(model.status?.batterySuppressed == true ? .orange : .accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var automationList: some View {
        if let rules = model.status?.rules, !rules.isEmpty {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(rules, id: \.id) { rule in
                        automationRow(rule)
                            .transition(reduceMotion ? .identity : .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 144)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundColor(.secondary)
                Text("No automations yet").foregroundColor(.secondary)
                Spacer()
            }
            .font(.subheadline)
            .padding(.vertical, 3)
            .transition(reduceMotion ? .identity : .opacity)
        }
    }

    private func automationRow(_ rule: AwakeStatus.Rule) -> some View {
        HStack(spacing: 8) {
            Group {
                if rule.enabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .transition(reduceMotion ? .identity : .opacity)
                } else {
                    Image(systemName: "pause.circle")
                        .foregroundColor(.secondary)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .animation(motion, value: rule.enabled)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).lineLimit(1)
                Text(rule.kind == "schedule" ? "Schedule" : rule.kind == "app_open" ? "App is open" : "Work process")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                Button(rule.enabled ? "Pause" : "Enable") {
                    model.performRuleAction(rule.enabled ? "disable" : "enable", ruleID: rule.id)
                }
                Button("Remove", role: .destructive) {
                    model.performRuleAction("remove", ruleID: rule.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Actions for \(rule.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
    }
}
