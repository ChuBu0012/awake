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
}

enum StatusUpdatePolicy {
    static func shouldPublish(previous: AwakeStatus?, next: AwakeStatus) -> Bool {
        previous != next
    }
}
