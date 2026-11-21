import AppKit
import Foundation

// MARK: - App Recommendation Model & Discovery Engine
// Discovers local AI agents and developer tools on this Mac without telemetry or network access.

struct RecommendedAppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let appURL: URL?
    let suggestedProcess: String
    let reason: String
    var mode: WatchMode
    var isSelected: Bool

    enum WatchMode: String, CaseIterable, Identifiable {
        case workProcess = "Work process"
        case appOpen = "App is open"

        var id: String { rawValue }
        var description: String {
            switch self {
            case .workProcess:
                return "Keeps awake while active tasks or commands run in the app"
            case .appOpen:
                return "Keeps awake as long as the application window is running"
            }
        }
    }
}

final class AppRecommendationEngine {
    // Known developer and AI tools catalog
    private static let knownCatalog: [(name: String, bundleIDs: [String], appNames: [String], process: String, reason: String, defaultMode: RecommendedAppItem.WatchMode)] = [
        (
            name: "Cursor",
            bundleIDs: ["com.todesktop.230313mzl4w4u92"],
            appNames: ["Cursor.app"],
            process: "Cursor",
            reason: "AI Code Editor (prevents sleep during background indexing and AI generation)",
            defaultMode: .workProcess
        ),
        (
            name: "Visual Studio Code",
            bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
            appNames: ["Visual Studio Code.app", "Code.app"],
            process: "Code Helper",
            reason: "Developer Editor (keeps Mac awake during builds, tests, and AI extensions)",
            defaultMode: .workProcess
        ),
        (
            name: "Claude",
            bundleIDs: ["com.anthropic.claude-desktop"],
            appNames: ["Claude.app"],
            process: "Claude",
            reason: "AI Assistant (keeps Mac awake during long Claude Code and agent runs)",
            defaultMode: .appOpen
        ),
        (
            name: "ChatGPT",
            bundleIDs: ["com.openai.chat"],
            appNames: ["ChatGPT.app"],
            process: "ChatGPT",
            reason: "AI Assistant (keeps Mac awake during Advanced Data Analysis and long tasks)",
            defaultMode: .appOpen
        ),
        (
            name: "Antigravity",
            bundleIDs: ["com.google.antigravity"],
            appNames: ["Antigravity.app"],
            process: "antigravity",
            reason: "AI Agent IDE (keeps Mac awake during autonomous background workflows)",
            defaultMode: .workProcess
        ),
        (
            name: "Xcode",
            bundleIDs: ["com.apple.dt.Xcode"],
            appNames: ["Xcode.app"],
            process: "swift-frontend",
            reason: "Apple IDE (keeps Mac awake during indexing, compiling, and test suites)",
            defaultMode: .workProcess
        ),
        (
            name: "OrbStack",
            bundleIDs: ["dev.kdrag0n.MacVirt", "dev.kdrag0n.OrbStack"],
            appNames: ["OrbStack.app"],
            process: "orbstack",
            reason: "Docker & Linux Engine (keeps local containers and background jobs awake)",
            defaultMode: .workProcess
        ),
        (
            name: "Docker",
            bundleIDs: ["com.docker.docker"],
            appNames: ["Docker.app"],
            process: "docker",
            reason: "Container Engine (keeps background services and builds running)",
            defaultMode: .workProcess
        ),
        (
            name: "Terminal",
            bundleIDs: ["com.apple.Terminal"],
            appNames: ["Terminal.app"],
            process: "Terminal",
            reason: "macOS Command Line (keeps CLI scripts and agents awake)",
            defaultMode: .workProcess
        ),
        (
            name: "iTerm2",
            bundleIDs: ["com.googlecode.iterm2"],
            appNames: ["iTerm.app", "iTerm2.app"],
            process: "iTerm2",
            reason: "Developer Terminal (keeps long-running terminal jobs awake)",
            defaultMode: .workProcess
        ),
        (
            name: "Ghostty",
            bundleIDs: ["com.mitchellh.ghostty"],
            appNames: ["Ghostty.app"],
            process: "ghostty",
            reason: "Fast Terminal (keeps background agent sessions alive)",
            defaultMode: .workProcess
        ),
        (
            name: "Warp",
            bundleIDs: ["dev.warp.Warp-Stable"],
            appNames: ["Warp.app"],
            process: "Warp",
            reason: "AI Terminal (keeps developer workflows running)",
            defaultMode: .workProcess
        ),
        (
            name: "Postman",
            bundleIDs: ["com.postmanlabs.mac"],
            appNames: ["Postman.app"],
            process: "Postman",
            reason: "API Platform (keeps collection runs and monitor tests awake)",
            defaultMode: .appOpen
        )
    ]

    static func discoverRecommendations() -> [RecommendedAppItem] {
        var results: [RecommendedAppItem] = []
        let searchDirectories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var foundBundleIDs = Set<String>()

        for entry in knownCatalog {
            var matchingURL: URL?
            var resolvedBundleID: String?

            // 1. Try resolving by Bundle ID
            for bID in entry.bundleIDs {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bID) {
                    matchingURL = appURL
                    resolvedBundleID = bID
                    break
                }
            }

            // 2. Try resolving by Application File Name
            if matchingURL == nil {
                for dir in searchDirectories {
                    for appName in entry.appNames {
                        let candidate = dir.appendingPathComponent(appName)
                        if FileManager.default.fileExists(atPath: candidate.path) {
                            matchingURL = candidate
                            resolvedBundleID = Bundle(url: candidate)?.bundleIdentifier ?? entry.bundleIDs.first
                            break
                        }
                    }
                    if matchingURL != nil { break }
                }
            }

            if let matchingURL = matchingURL, let bID = resolvedBundleID, !foundBundleIDs.contains(bID) {
                foundBundleIDs.insert(bID)
                results.append(
                    RecommendedAppItem(
                        id: bID,
                        name: entry.name,
                        bundleID: bID,
                        appURL: matchingURL,
                        suggestedProcess: entry.process,
                        reason: entry.reason,
                        mode: entry.defaultMode,
                        isSelected: true // Recommended checked by default
                    )
                )
            }
        }

        return results
    }
}
