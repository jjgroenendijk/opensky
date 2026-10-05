// The VATS camera condition functions read the shot request, and fail with
// the camera domain when no request is set.

import FeaturesTesting
@testable import OpenSkyConditions
import OpenSkyFormatsESM
@testable import OpenSkyWorld
import Testing

struct CameraConditionFunctionTests {
    private static func isTrue(
        _ function: UInt16,
        _ parameter1: UInt32 = 0,
        _ parameter2: UInt32 = 0,
        camera: CameraConditionResolution
    ) throws -> ConditionOutcome {
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern,
            functionIndex: function,
            parameter1: parameter1,
            parameter2: parameter2
        )
        var context = ConditionContext()
        context.camera = camera
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(condition)
    }

    /// True when the function returns exactly `value`.
    private static func returns(
        _ function: UInt16, member parameter1: UInt32 = 0, value: Float,
        camera: CameraConditionResolution
    ) throws -> Bool {
        var context = ConditionContext()
        context.camera = camera
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function, parameter1: parameter1
        )
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(condition).isTrue
    }

    private static var rangedShot: CameraConditionResolution {
        var camera = CameraConditionResolution()
        camera.isAvailable = true
        camera.action = 4
        camera.weaponType = 7
        camera.projectileType = 6
        camera.freeDistance = [.left: 200, .back: 300]
        camera.targetDistance = 900
        camera.targetVisibleSides = [.right]
        return camera
    }

    @Test func vatsValueComparesTheSelectedMember() throws {
        #expect(try Self.isTrue(407, 6, 4, camera: Self.rangedShot).isTrue)
        #expect(try !Self.isTrue(407, 6, 1, camera: Self.rangedShot).isTrue)
        #expect(try Self.isTrue(407, 15, 7, camera: Self.rangedShot).isTrue)
        #expect(try Self.isTrue(407, 18, 6, camera: Self.rangedShot).isTrue)
        #expect(try !Self.isTrue(407, 0, 0x12EB7, camera: Self.rangedShot).isTrue)
    }

    @Test func vatsValueRejectsAnUnknownMember() throws {
        let outcome = try Self.isTrue(407, 99, 0, camera: Self.rangedShot)
        #expect(outcome.failures == [.unresolvedParameter(407)])
    }

    @Test func sideFunctionsReturnTheRoomAndTheVisibleSides() throws {
        #expect(try Self.returns(515, value: 0, camera: Self.rangedShot))
        #expect(try Self.returns(516, value: 200, camera: Self.rangedShot))
        #expect(try Self.returns(517, value: 300, camera: Self.rangedShot))
        #expect(try Self.returns(407, member: 4, value: 900, camera: Self.rangedShot))
        #expect(try Self.isTrue(522, camera: Self.rangedShot).isTrue)
        #expect(try !Self.isTrue(523, camera: Self.rangedShot).isTrue)
    }

    @Test(arguments: [UInt16(407), 515, 516, 517, 518, 522, 523])
    func failsHonestlyWithoutAShotRequest(function: UInt16) throws {
        let outcome = try Self.isTrue(function, 6, 4, camera: .empty)
        #expect(outcome.failures == [.unavailableData(.camera)])
    }
}
