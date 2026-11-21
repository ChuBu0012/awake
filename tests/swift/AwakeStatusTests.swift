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
