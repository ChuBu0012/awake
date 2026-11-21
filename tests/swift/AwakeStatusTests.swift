import Foundation

@main
struct AwakeStatusTests {
    static func main() {
        let original = status()
        expect(!StatusUpdatePolicy.shouldPublish(previous: original, next: original), "equal status snapshots must not publish")

        let activeChanged = status(active: true)
        expect(StatusUpdatePolicy.shouldPublish(previous: original, next: activeChanged), "active state changes must publish")

        let batteryChanged = status(batteryGuardEnabled: false)
        expect(StatusUpdatePolicy.shouldPublish(previous: original, next: batteryChanged), "Battery Guard changes must publish")

        let rulesChanged = status(rules: [AwakeStatus.Rule(id: "rule-1", name: "TextEdit", kind: "app", enabled: true)])
        expect(StatusUpdatePolicy.shouldPublish(previous: original, next: rulesChanged), "Automation rule changes must publish")

        expect(StatusUpdatePolicy.shouldPublish(previous: nil, next: original), "the first status snapshot must publish")
        expect(StatusUpdatePolicy.durationSelection(forRemainingSeconds: 1_799) == 1_800, "a newly started 30-minute request must keep the 30-minute selection")
        expect(StatusUpdatePolicy.durationSelection(forRemainingSeconds: 125) == 125, "custom durations must keep their remaining duration")
        expect(StatusUpdatePolicy.durationSelection(forRemainingSeconds: 0) == 0, "expired durations must become indefinite")

        // Recommendations discovery checks
        let recommendations = AppRecommendationEngine.discoverRecommendations()
        for rec in recommendations {
            expect(!rec.name.isEmpty, "recommended app name must not be empty")
            expect(!rec.bundleID.isEmpty, "recommended bundleID must not be empty")
            expect(!rec.reason.isEmpty, "recommended reason must not be empty")
        }
        expect(!RecommendedAppItem.WatchMode.workProcess.description.isEmpty, "work process mode description must not be empty")
        expect(!RecommendedAppItem.WatchMode.appOpen.description.isEmpty, "app open mode description must not be empty")

        // Status helper properties checks
        let inactiveStatus = status(active: false)
        expect(!inactiveStatus.isManualActive, "empty requests must not be manual active")
        expect(inactiveStatus.activeReasonSummary == "Normal sleep behavior", "inactive reason must report normal sleep behavior")

        let manualStatus = AwakeStatus(
            active: true,
            batterySuppressed: false,
            batteryGuardEnabled: true,
            lidSupportEnabled: false,
            snoozedUntil: nil,
            requests: [AwakeStatus.Lease(id: "manual", source: "manual", reason: "Manual On", expiresAt: nil)],
            rules: [],
            recoveryPending: false
        )
        expect(manualStatus.isManualActive, "manual request must report isManualActive")
        expect(manualStatus.activeReasonSummary == "Manual On", "manual active reason must match lease reason")

        let snoozedStatus = AwakeStatus(
            active: false,
            batterySuppressed: false,
            batteryGuardEnabled: true,
            lidSupportEnabled: false,
            snoozedUntil: Date().addingTimeInterval(1800),
            requests: [],
            rules: [],
            recoveryPending: false
        )
        expect(snoozedStatus.isSnoozed, "future snoozedUntil must be snoozed")
        expect(snoozedStatus.activeReasonSummary == "Automations snoozed", "snoozed reason must be reported")

        let snoozedWithActiveRequest = AwakeStatus(
            active: true,
            batterySuppressed: false,
            batteryGuardEnabled: true,
            lidSupportEnabled: true,
            snoozedUntil: Date().addingTimeInterval(1800),
            requests: [AwakeStatus.Lease(id: "cmd-1", source: "command", reason: "Long Running Build", expiresAt: nil)],
            rules: [],
            recoveryPending: false
        )
        expect(snoozedWithActiveRequest.isSnoozed, "future snoozedUntil must be snoozed")
        expect(snoozedWithActiveRequest.activeReasonSummary == "Long Running Build", "active request reason must take precedence over snoozed automations")
        expect(snoozedWithActiveRequest.lidSupportEnabled, "lidSupportEnabled must be true when set")

        let suppressedStatus = AwakeStatus(
            active: false,
            batterySuppressed: true,
            batteryGuardEnabled: true,
            lidSupportEnabled: false,
            snoozedUntil: nil,
            requests: [AwakeStatus.Lease(id: "manual", source: "manual", reason: "Manual On", expiresAt: nil)],
            rules: [],
            recoveryPending: false
        )
        expect(suppressedStatus.activeReasonSummary == "Paused by Battery Guard", "battery suppressed status must be reported")

        print("AwakeStatusTests: all checks passed")
    }

    private static func status(
        active: Bool = false,
        batteryGuardEnabled: Bool = true,
        rules: [AwakeStatus.Rule] = []
    ) -> AwakeStatus {
        AwakeStatus(
            active: active,
            batterySuppressed: false,
            batteryGuardEnabled: batteryGuardEnabled,
            lidSupportEnabled: false,
            snoozedUntil: nil,
            requests: [],
            rules: rules,
            recoveryPending: false
        )
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
}
