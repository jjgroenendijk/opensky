// The actor-state graph inputs: which `iState` a step picks, the values written, and
// the bridge writing them to a graph that declares the `iState_*` constants.

@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import OpenSkyPhysics
@testable import OpenSkyPlayer
import simd
import Testing

struct ActorStateGraphCoreTests {
    @Test func anAttackOutranksAGuardAndAGuardOutranksMovement() {
        var inputs = ActorStateGraphInputs()
        inputs.weaponDrawn = true
        inputs.rightHandType = 1
        #expect(ActorStateGraphCore.state(for: inputs, gait: .walk) == .npc1HM)
        #expect(ActorStateGraphCore.state(for: inputs, gait: .sprint) == .npcSprinting)
        inputs.isBlocking = true
        #expect(ActorStateGraphCore.state(for: inputs, gait: .sprint) == .npcBlocking)
        inputs.isAttacking = true
        #expect(ActorStateGraphCore.state(for: inputs, gait: .sprint) == .npcAttacking)
        inputs.isPowerAttacking = true
        #expect(ActorStateGraphCore.state(for: inputs, gait: .walk) == .npcPowerAttacking)
    }

    @Test func theDrawnHandPicksTheWeaponState() {
        var inputs = ActorStateGraphInputs()
        #expect(ActorStateGraphCore.state(for: inputs, gait: .walk) == .npcDefault)
        inputs.weaponDrawn = true
        let expected: [Int32: ActorGraphState] = [
            0: .npcDefault, 2: .npc1HM, 6: .npc2HM, 7: .npcBow, 12: .npcBow, 9: .npcMagic
        ]
        for (hand, state) in expected {
            inputs.rightHandType = hand
            #expect(ActorStateGraphCore.state(for: inputs, gait: .walk) == state)
        }
        inputs.rightHandType = 5
        inputs.isAttacking = true
        #expect(ActorStateGraphCore.state(for: inputs, gait: .walk) == .npcAttacking2H)
    }

    @Test func aCastOrADrawnBowOutranksTheGait() {
        var inputs = ActorStateGraphInputs()
        inputs.castingLeft = true
        #expect(ActorStateGraphCore.state(for: inputs, gait: .sneak) == .npcMagicCasting)
        inputs.isBowDrawn = true
        #expect(ActorStateGraphCore.state(for: inputs, gait: .sneak) == .npcBowDrawn)
    }

    @Test func drunkOutranksTheGaitButNotACast() {
        var inputs = ActorStateGraphInputs()
        inputs.isDrunk = true
        #expect(ActorStateGraphCore.state(for: inputs, gait: .sprint) == .npcDrunk)
        inputs.castingRight = true
        #expect(ActorStateGraphCore.state(for: inputs, gait: .walk) == .npcMagicCasting)
        inputs.riding = .riding
        #expect(ActorStateGraphCore.state(for: inputs, gait: .walk) == .npcHorse)
    }

    @Test func theBridgeReportsTheGraphsDrunkTagThroughIState() {
        var table = BehaviorObjectTable()
        let binding = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("iStateToSetAs", 1)]), at: 0x08
        )
        let root = table.add(
            BSiStateTaggingGenerator(
                node: BehaviorFixture.nodeHeader("MT_Drunk_iStateGen", bindingSet: binding),
                defaultGenerator: nil, stateToSetAs: 0, priority: 0, unresolved: []
            ),
            at: 0x10
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table,
            data: BehaviorFixture.graphData(variables: [
                BehaviorVariableSpec(ActorStateGraphNames.state, .int32, 0),
                BehaviorVariableSpec(ActorGraphState.npcDrunk.variableName, .int32, 22)
            ])
        )
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        _ = bridge.plan(LocomotionBridgeTests.state())
        _ = bridge.plan(LocomotionBridgeTests.state())
        #expect(bridge.actorState.isDrunk)
        #expect(graph.variable(named: ActorStateGraphNames.state) == .int(22))
    }

    @Test func writesCarryTheCameraTheKeysAndTheState() {
        var inputs = ActorStateGraphInputs()
        inputs.setCamera(position: SIMD3(1, 2, 3), forward: SIMD3(0, 1, 0), pitch: 0.25)
        inputs.castingRight = true
        inputs.weight = 100
        let writes = Dictionary(
            uniqueKeysWithValues: ActorStateGraphCore.writes(
                inputs, sprintAllowed: false, wantsBlock: true, stateValue: 10
            ).map { ($0.name, $0.value) }
        )
        #expect(writes[ActorStateGraphNames.cameraFromY] == .real(2))
        #expect(
            writes[ActorStateGraphNames.targetLocation]
                == .quad(SIMD4(1, 2 + ActorStateGraphInputs.lookDistance, 3, 0))
        )
        #expect(writes[ActorStateGraphNames.pitch] == .real(0.25))
        #expect(writes[ActorStateGraphNames.sprintOK] == .bool(false))
        #expect(writes[ActorStateGraphNames.wantBlock] == .int(1))
        #expect(writes[ActorStateGraphNames.wantCastRight] == .bool(true))
        #expect(writes[ActorStateGraphNames.inCastState] == .real(1))
        #expect(writes[ActorStateGraphNames.state] == .int(10))
        #expect(writes[ActorStateGraphNames.weaponAdjust] == .real(1))
        #expect(Set(writes.keys) == Set(ActorStateGraphNames.inputs))
    }

    /// A sheathed sword is no drawn weapon, so the selectors keep their unarmed child.
    @Test func equippedHandsCountOnlyWhileDrawn() {
        var inputs = ActorStateGraphInputs()
        inputs.rightHandType = 1
        inputs.leftHandType = 10
        inputs.isBeastRace = true
        inputs.swimming = true
        func writes() -> [String: BehaviorVariableValue] {
            Dictionary(uniqueKeysWithValues: ActorStateGraphCore.writes(
                inputs, sprintAllowed: true, wantsBlock: false, stateValue: nil
            ).map { ($0.name, $0.value) })
        }
        #expect(writes()[ActorStateGraphNames.rightHandEquipped] == .int(0))
        inputs.weaponDrawn = true
        #expect(writes()[ActorStateGraphNames.rightHandEquipped] == .int(1))
        #expect(writes()[ActorStateGraphNames.leftHandEquipped] == .int(10))
        #expect(writes()[ActorStateGraphNames.isBeastRace] == .bool(true))
        #expect(writes()[ActorStateGraphNames.getUpType] == .int(2))
        #expect(ActorStateGraphCore.getUpType(swimming: false) == 1)
    }

    @Test func aGraphWithNoConstantGetsNoState() {
        let writes = ActorStateGraphCore.writes(
            ActorStateGraphInputs(), sprintAllowed: true, wantsBlock: false, stateValue: nil
        )
        #expect(!writes.contains { $0.name == ActorStateGraphNames.state })
    }

    @Test func theStateNameIsTheConstantThatHoldsTheValue() {
        let constants: [ActorGraphState: Int32] = [.npc1HM: 6, .npcSprinting: 1]
        #expect(ActorStateGraphCore.stateName(of: 6, constants: constants) == "6 (NPC1HM)")
        #expect(ActorStateGraphCore.stateName(of: 40, constants: constants) == "40")
    }

    @Test func theBridgeWritesTheGraphsOwnStateConstant() {
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("idle", animationName: "idle"), at: 0x10
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table,
            data: BehaviorFixture.graphData(variables: [
                BehaviorVariableSpec(ActorStateGraphNames.state, .int32, 0),
                BehaviorVariableSpec(ActorGraphState.npcSprinting.variableName, .int32, 1),
                BehaviorVariableSpec(ActorStateGraphNames.sprintOK, .bool, 1)
            ])
        )
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        bridge.intent = LocomotionIntent(moveForward: 1, sprint: true)
        bridge.isSprintAllowed = false
        _ = bridge.plan(LocomotionBridgeTests.state())
        // No sprint, and the graph declares no `iState_NPCDefault`, so `iState` keeps 0.
        #expect(graph.variable(named: ActorStateGraphNames.sprintOK) == .bool(false))
        #expect(graph.variable(named: ActorStateGraphNames.state) == .int(0))
        bridge.isSprintAllowed = true
        _ = bridge.plan(LocomotionBridgeTests.state())
        #expect(graph.variable(named: ActorStateGraphNames.state) == .int(1))
        #expect(bridge.status.boundVariables.contains(ActorStateGraphNames.state))
    }
}
