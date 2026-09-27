// The first-person visibility matrix (issue #190): which rig is drawn and
// which is cast, per camera mode. Pure value — no device, no install.

@testable import opensky
import Testing

struct PlayerRigVisibilityTests {
    private func resolve(
        _ mode: CameraMovementMode,
        armsEnabled: Bool = true
    ) -> PlayerRigVisibility {
        PlayerRigVisibility.resolve(
            mode: mode, hasBody: true, hasArms: true, armsEnabled: armsEnabled
        )
    }

    /// The whole matrix, one assertion per mode, so a change to any cell has to
    /// be a deliberate edit here.
    @Test
    func theMatrixIsExactlyThis() {
        #expect(resolve(.fly) == PlayerRigVisibility(
            drawsBody: true, castsBodyShadow: true, drawsArms: false, castsArmShadow: false
        ))
        #expect(resolve(.walk) == PlayerRigVisibility(
            drawsBody: false, castsBodyShadow: true, drawsArms: true, castsArmShadow: false
        ))
        #expect(resolve(.thirdPerson) == PlayerRigVisibility(
            drawsBody: true, castsBodyShadow: true, drawsArms: false, castsArmShadow: false
        ))
    }

    /// Exactly one rig is drawn in each player mode: never both, never neither.
    @Test
    func exactlyOneRigIsDrawnInEachPlayerMode() {
        for mode in CameraMovementMode.allCases where mode.isPlayerControlled {
            let visibility = resolve(mode)
            #expect(visibility.drawsBody != visibility.drawsArms, "\(mode)")
        }
    }

    /// The shadow policy, stated as its own assertion because it is the one
    /// cell that deliberately disagrees with what the camera sees.
    @Test
    func theBodyCastsEvenWhereTheCameraCannotSeeIt() {
        let firstPerson = resolve(.walk)
        #expect(!firstPerson.drawsBody)
        #expect(firstPerson.castsBodyShadow)
    }

    /// The arms never cast, in any mode and whatever is attached.
    @Test
    func theArmsNeverCast() {
        for mode in CameraMovementMode.allCases {
            for enabled in [true, false] {
                #expect(!resolve(mode, armsEnabled: enabled).castsArmShadow, "\(mode)")
            }
        }
    }

    /// Nothing is drawn or cast for a rig that is not attached — which is the
    /// bodiless and armless configurations both staying supported.
    @Test
    func anUnattachedRigIsNeverDrawnOrCast() {
        let none = PlayerRigVisibility.resolve(
            mode: .walk, hasBody: false, hasArms: false
        )
        #expect(none == PlayerRigVisibility(
            drawsBody: false, castsBodyShadow: false, drawsArms: false, castsArmShadow: false
        ))
        let armsOnly = PlayerRigVisibility.resolve(
            mode: .thirdPerson, hasBody: false, hasArms: true
        )
        #expect(!armsOnly.drawsBody)
        #expect(!armsOnly.castsBodyShadow)
        #expect(!armsOnly.drawsArms)
    }

    /// The A/B toggle hides the arms and touches nothing else.
    @Test
    func theArmsToggleOnlyHidesTheArms() {
        let off = resolve(.walk, armsEnabled: false)
        #expect(!off.drawsArms)
        #expect(!off.drawsBody)
        #expect(off.castsBodyShadow)
    }
}
