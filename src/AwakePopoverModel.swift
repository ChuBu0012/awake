import AppKit
import Combine
import Foundation

final class AwakePopoverModel: ObservableObject {
    @Published private(set) var status: AwakeStatus?
    @Published private(set) var currentDuration = 0
    @Published private(set) var isBusy = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var timeRemainingFormatted: String?
    @Published var errorMessage: String?

    private let workQueue = DispatchQueue(label: "app.awake.cli", qos: .userInitiated)
    private let cliPath: String
    private var refreshInFlight = false
    private var needsRefreshAgain = false
    private var countdownTimer: Timer?

    init(bundleURL: URL = Bundle.main.bundleURL) {
        self.cliPath = Self.resolveCLIPath(bundleURL: bundleURL)
    }

    deinit {
        stopCountdownTimer()
    }

    func clearError() {
        errorMessage = nil
    }

    func refresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.refreshInFlight {
                self.needsRefreshAgain = true
                return
            }
            self.refreshInFlight = true
            self.executeRefresh()
        }
    }

    private func executeRefresh() {
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
                let shouldRerun = self.needsRefreshAgain
                self.needsRefreshAgain = false

                if let decoded {
                    if StatusUpdatePolicy.shouldPublish(previous: self.status, next: decoded) {
                        self.status = decoded
                    }
                    self.updateRemainingDuration(from: decoded)
                }

                if shouldRerun {
                    self.refresh()
                }
            }
        }
    }

    func toggleAwake(ownerPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        guard !isBusy else { return }

        if status?.active == true {
            performAction(["off"])
            return
        }

        var arguments = ["on", currentDuration > 0 ? "\(currentDuration)s" : "indefinite"]
        arguments += ["--owner-pid", "\(ownerPID)"]
        performAction(arguments)
    }

    func selectDuration(_ seconds: Int, ownerPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        currentDuration = seconds
        guard status?.requests.contains(where: { $0.source == "manual" }) == true else { return }
        guard !isBusy else { return }
        let duration = seconds > 0 ? "\(seconds)s" : "indefinite"
        performAction(["on", duration, "--owner-pid", "\(ownerPID)"])
    }

    func toggleBatteryGuard() {
        guard !isBusy else { return }
        let enabled = status?.batteryGuardEnabled != true
        performAction(["set", "battery-guard", enabled ? "on" : "off"])
    }

    func toggleLidSupport() {
        guard !isBusy else { return }
        let enabled = status?.lidSupportEnabled != true
        performAction(["set", "lid-support", enabled ? "on" : "off"])
    }

    func addAppRule(name: String, bundleID: String) {
        guard !isBusy else { return }
        let ruleID = "app-\(UUID().uuidString.lowercased())"
        performAction(["rule", "app", ruleID, name, bundleID])
    }

    func addProcessRule(name: String, processName: String? = nil, bundleID: String? = nil) {
        guard !isBusy else { return }
        var proc = (processName ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
        if proc.contains("/") {
            proc = URL(fileURLWithPath: proc).lastPathComponent
        }
        guard !proc.isEmpty else { return }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruleName = displayName.isEmpty ? proc : displayName
        let ruleID = "process-\(UUID().uuidString.lowercased())"
        var args = ["rule", "process", ruleID, ruleName, proc]
        if let bID = bundleID, !bID.isEmpty {
            args.append(bID)
        }
        performAction(args)
    }

    func addScheduleRule(days: String, start: String, end: String) {
        guard !isBusy else { return }
        let cleanDays = days.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanStart = start.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEnd = end.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruleID = "schedule-\(UUID().uuidString.lowercased())"
        performAction(["rule", "schedule", ruleID, "Schedule (\(cleanDays))", cleanDays, cleanStart, cleanEnd])
    }

    func performRuleAction(_ action: String, ruleID: String) {
        guard !isBusy else { return }
        performAction(["rule", action, ruleID])
    }

    func endSession() {
        stopCountdownTimer()
        _ = runCLI(["session-end"])
    }

    private func performAction(_ arguments: [String], completion: (() -> Void)? = nil) {
        isBusy = true
        errorMessage = nil
        workQueue.async { [weak self] in
            guard let self else { return }
            let result = self.runCLI(arguments)
            let detail = Self.stripANSI(result.output).trimmingCharacters(in: .whitespacesAndNewlines)

            let statusResult = self.runCLI(["status", "--json"])
            let decoded = statusResult.succeeded ? Self.decodeStatus(statusResult.output) : nil

            DispatchQueue.main.async {
                self.isBusy = false
                if !result.succeeded {
                    self.errorMessage = detail.isEmpty ? "Action could not be completed. Check CLI and system permissions." : detail
                }
                if let decoded {
                    self.status = decoded
                    self.updateRemainingDuration(from: decoded)
                }
                completion?()
            }
        }
    }

    private func runCLI(_ arguments: [String]) -> CLIResult {
        executeCLI(arguments)
    }

    private func executeCLI(_ arguments: [String], timeoutSeconds: Double = 6.0) -> CLIResult {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            return CLIResult(output: "Awake CLI executable not found at: \(cliPath)", succeeded: false)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        let readHandle = pipe.fileHandleForReading
        var collectedData = Data()
        let dataLock = NSLock()

        readHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                dataLock.lock()
                collectedData.append(chunk)
                dataLock.unlock()
            }
        }

        do {
            try process.run()
        } catch {
            readHandle.readabilityHandler = nil
            return CLIResult(output: error.localizedDescription, succeeded: false)
        }

        let startTime = Date()
        while process.isRunning && Date().timeIntervalSince(startTime) < timeoutSeconds {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            let killStart = Date()
            while process.isRunning && Date().timeIntervalSince(killStart) < 0.5 {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        readHandle.readabilityHandler = nil
        let remaining = readHandle.readDataToEndOfFile()
        dataLock.lock()
        collectedData.append(remaining)
        let finalData = collectedData
        dataLock.unlock()

        try? readHandle.close()

        let text = String(data: finalData, encoding: .utf8) ?? ""
        return CLIResult(output: text, succeeded: process.terminationStatus == 0)
    }

    private func updateRemainingDuration(from status: AwakeStatus) {
        if let lease = status.requests.first(where: { $0.source == "manual" }), let expires = lease.expiresAt {
            let remaining = max(0, Int(expires.timeIntervalSinceNow))
            self.remainingSeconds = remaining
            self.currentDuration = StatusUpdatePolicy.durationSelection(forRemainingSeconds: remaining)
            self.timeRemainingFormatted = Self.formatSeconds(remaining)
            self.startCountdownTimerIfNeeded()
        } else if status.requests.contains(where: { $0.source == "manual" }) {
            self.remainingSeconds = 0
            self.currentDuration = 0
            self.timeRemainingFormatted = "Until stopped"
            self.stopCountdownTimer()
        } else {
            self.remainingSeconds = 0
            self.timeRemainingFormatted = nil
            self.stopCountdownTimer()
        }
    }

    private func startCountdownTimerIfNeeded() {
        guard countdownTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
                self.timeRemainingFormatted = Self.formatSeconds(self.remainingSeconds)
                if self.remainingSeconds == 0 {
                    self.refresh()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private static func formatSeconds(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            let mins = (seconds % 3600) / 60
            return "\(hours)h \(mins)m"
        } else if seconds >= 60 {
            let mins = seconds / 60
            let secs = seconds % 60
            return "\(mins)m \(secs)s"
        } else if seconds > 0 {
            return "\(seconds)s"
        } else {
            return "Expired"
        }
    }

    private static func resolveCLIPath(bundleURL: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundledResource = Bundle.main.url(forResource: "awake", withExtension: nil)?.path
        let resourceFolder = Bundle.main.resourcePath.map { "\($0)/awake" }
        let bundledCLI = bundleURL.appendingPathComponent("Contents/Resources/awake", isDirectory: false).path
        let execDir = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("awake").path
        let cwdBuild = FileManager.default.currentDirectoryPath + "/build/awake"

        let candidates = [
            bundledResource,
            resourceFolder,
            bundledCLI,
            execDir,
            "\(home)/.local/bin/awake",
            "/opt/homebrew/bin/awake",
            "/usr/local/bin/awake",
            cwdBuild
        ].compactMap { $0 }

        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "/usr/bin/false"
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
