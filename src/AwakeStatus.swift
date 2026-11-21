import Foundation

struct AwakeStatus: Decodable, Equatable {
    struct Lease: Decodable, Equatable {
        let id: String
        let source: String
        let reason: String
        let expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, source, reason
            case expiresAt = "expires_at"
        }
    }

    struct Rule: Decodable, Equatable {
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

    var isSnoozed: Bool {
        guard let snoozedUntil = snoozedUntil else { return false }
        return snoozedUntil > Date()
    }

    var manualLease: Lease? {
        requests.first(where: { $0.source == "manual" })
    }

    var isManualActive: Bool {
        manualLease != nil
    }

    var activeReasonSummary: String {
        if batterySuppressed {
            return "Paused by Battery Guard"
        }
        let reasons = requests.map(\.reason).filter { !$0.isEmpty }
        if !reasons.isEmpty {
            return reasons.joined(separator: ", ")
        }
        if isSnoozed {
            return "Automations snoozed"
        }
        if recoveryPending {
            return "A sleep setting needs recovery"
        }
        return active ? "Awake is preventing sleep" : "Normal sleep behavior"
    }
}

enum StatusUpdatePolicy {
    private static let presetDurations = [1_800, 3_600, 7_200, 14_400, 28_800]

    static func shouldPublish(previous: AwakeStatus?, next: AwakeStatus) -> Bool {
        previous != next
    }

    static func durationSelection(forRemainingSeconds remaining: Int) -> Int {
        guard remaining > 0 else { return 0 }
        guard let preset = presetDurations.min(by: { abs($0 - remaining) < abs($1 - remaining) }),
              abs(preset - remaining) <= 60 else {
            return remaining
        }
        return preset
    }
}
