import AppKit
import Combine
import Foundation

final class AwakePopoverModel: ObservableObject {
    @Published private(set) var status: AwakeStatus?
    @Published private(set) var currentDuration = 0
    @Published var errorMessage: String?

    private let workQueue = DispatchQueue(label: "app.awake.cli", qos: .utility)
    private let cliPath: String
    private var refreshInFlight = false

    init(bundleURL: URL = Bundle.main.bundleURL) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundledCLI = bundleURL.appendingPathComponent("Contents/Resources/awake", isDirectory: false).path
        let candidates = [bundledCLI, "\(home)/.local/bin/awake", "/usr/local/bin/awake", "/opt/homebrew/bin/awake"]
        cliPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "/usr/bin/false"
    }

    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true

        let bundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter { !$0.isEmpty })
        var tickArguments = ["tick", "--automation-owner-pid", "\(ProcessInfo.processInfo.processIdentifier)"]
        for bundleID in bundleIDs { tickArguments += ["--bundle-id", bundleID] }

        workQueue.async { [weak self] in
            guard let self else { return }
            _ = self.runCLI(tickArguments)
            let result = self.runCLI(["status", "--json"])
            let decoded = result.succeeded ? Self.decodeStatus(result.output) : nil

            DispatchQueue.main.async {
                self.refreshInFlight = false
                guard let decoded else { return }
                guard StatusUpdatePolicy.shouldPublish(previous: self.status, next: decoded) else { return }

                self.status = decoded
                if let lease = decoded.requests.first(where: { $0.source == "manual" }), let expires = lease.expiresAt {
                    let remaining = max(0, Int(expires.timeIntervalSinceNow))
                    self.currentDuration = StatusUpdatePolicy.durationSelection(forRemainingSeconds: remaining)
                } else if decoded.requests.contains(where: { $0.source == "manual" }) {
                    self.currentDuration = 0
                }
            }
        }
    }

    func toggleAwake(ownerPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        if status?.requests.contains(where: { $0.source == "manual" }) == true {
            perform(["off"])
            return
        }

        var arguments = ["on", currentDuration > 0 ? "\(currentDuration)s" : "indefinite"]
        arguments += ["--owner-pid", "\(ownerPID)"]
        perform(arguments)
    }

    func selectDuration(_ seconds: Int, ownerPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        currentDuration = seconds
        guard status?.requests.contains(where: { $0.source == "manual" }) == true else { return }
        let duration = seconds > 0 ? "\(seconds)s" : "indefinite"
        perform(["on", duration, "--owner-pid", "\(ownerPID)"])
    }

    func toggleBatteryGuard() {
        let enabled = status?.batteryGuardEnabled != true
        perform(["set", "battery-guard", enabled ? "on" : "off"])
    }

    func addAppRule(name: String, bundleID: String) {
        perform(["rule", "app", "app-\(UUID().uuidString.lowercased())", name, bundleID])
    }

    func addProcessRule(name: String, processName: String? = nil) {
        let proc = processName ?? name
        perform(["rule", "process", "process-\(UUID().uuidString.lowercased())", name, proc])
    }

    func addScheduleRule(days: String, start: String, end: String) {
        perform(["rule", "schedule", "schedule-\(UUID().uuidString.lowercased())", "Schedule (\(days))", days, start, end])
    }

    func performRuleAction(_ action: String, ruleID: String) {
        perform(["rule", action, ruleID])
    }

    func endSession() {
        _ = runCLI(["session-end"])
    }

    private func perform(_ arguments: [String]) {
        errorMessage = nil
        workQueue.async { [weak self] in
            guard let self else { return }
            let result = self.runCLI(arguments)
            let detail = Self.stripANSI(result.output).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if !result.succeeded {
                    self.errorMessage = detail.isEmpty ? "Check the installation and permissions." : detail
                }
                self.refresh()
            }
        }
    }

    private func runCLI(_ arguments: [String]) -> CLIResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CLIResult(output: String(data: data, encoding: .utf8) ?? "", succeeded: process.terminationStatus == 0)
        } catch {
            return CLIResult(output: error.localizedDescription, succeeded: false)
        }
    }

    private static func decodeStatus(_ output: String) -> AwakeStatus? {
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
        return output.data(using: .utf8).flatMap { try? decoder.decode(AwakeStatus.self, from: $0) }
    }

    private static func stripANSI(_ output: String) -> String {
        output.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }
}

private struct CLIResult {
    let output: String
    let succeeded: Bool
}
