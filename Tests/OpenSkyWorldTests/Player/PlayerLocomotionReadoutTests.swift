@testable import OpenSkyWorld
import Testing

struct PlayerLocomotionReadoutTests {
    @Test
    func graphTextNamesWhyThereIsNoBody() {
        let text = PlayerLocomotionReadout.graphText(
            for: Self.snapshot(graphAvailable: false, bodyFailureReason: "no skeleton")
        )
        #expect(text.contains("Behavior graph: not attached"))
        #expect(text.contains("Player body: none (no skeleton)"))
    }

    @Test
    func graphTextNamesABodyFailureWithAnAttachedGraph() {
        let text = PlayerLocomotionReadout.graphText(
            for: Self.snapshot(graphAvailable: true, bodyFailureReason: "attach failed")
        )
        #expect(text.contains("Behavior graph: attached"))
        #expect(text.contains("Player body: none (attach failed)"))
    }

    @Test
    func graphTextOmitsTheBodyLineWhenABodyIsAttached() {
        let text = PlayerLocomotionReadout.graphText(
            for: Self.snapshot(graphAvailable: true, bodyFailureReason: nil)
        )
        #expect(!text.contains("Player body"))
    }

    private static func snapshot(
        graphAvailable: Bool,
        bodyFailureReason: String?
    ) -> PlayerLocomotionSnapshot {
        PlayerLocomotionSnapshot(
            rendererAvailable: true,
            walkModeActive: true,
            status: LocomotionStatus(graphAvailable: graphAvailable),
            bindings: [],
            configuration: .synthetic,
            activeStates: [],
            firstPersonActiveStates: [],
            variables: [],
            forcedGait: nil,
            tally: nil,
            bodyFailureReason: bodyFailureReason
        )
    }
}
