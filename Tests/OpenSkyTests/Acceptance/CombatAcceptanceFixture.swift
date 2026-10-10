// The M15 gate's world and graph, built in code. `CombatAcceptanceWorld` is a
// flat floor, a wall for arrows, and clutter to shove. `CombatAcceptanceFixture` is
// a synthetic behavior graph whose clip triggers fire each contact, nock,
// release, and ragdoll hand-off on the graph's own clock, so the gate tests the
// seam between the runtimes and animation. Everything is invented; the vanilla
// half is `CombatAcceptanceRealDataTests`.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd

/// The synthetic arena. Flat, so the fight is the one variable. The wall stops
/// a missed arrow and stands far enough east that a shot must fly.
nonisolated enum CombatAcceptanceWorld {
    static let floorHeight: Float = 0
    /// Where the wall stands, on +X, past the opponent.
    static let wallX: Float = 1200
    /// Where the player starts.
    static let startX: Float = 200
    /// One line of Y for the whole arena, in cell (0, 0)'s middle.
    static let startY = CellGridManager.cellCenter(of: CellCoordinate(x: 0, y: 0)).y
    /// Where the opponent stands: inside a drawn weapon's reach of the start,
    /// so a swing from standing connects and the route never has to walk to it.
    static let opponentX: Float = 260
    /// Where the clutter is dropped from, high enough that it visibly falls.
    static let clutterDropHeight: Float = 120

    static func sampleGround(_: SIMD2<Float>) -> TerrainGroundSample? {
        TerrainGroundSample(height: floorHeight, normal: SIMD3<Float>(0, 0, 1))
    }

    /// The static geometry a projectile sweeps against and a ragdoll lands on:
    /// the floor, and the wall at `wallX`.
    static func collisionShapes() -> [StaticCollisionShape] {
        [
            DynamicBodyScene.floor(z: floorHeight, extent: 4000),
            DynamicBodyScene.wall(at: wallX, extent: 4000)
        ]
    }

    static func stepWorld() -> DynamicStepWorld {
        DynamicStepWorld(staticCandidates: DynamicBodyScene.query(collisionShapes()))
    }

    /// One crate of movable clutter, dropped above the floor so the route can
    /// watch it fall, settle, and stay settled.
    static func clutter(key: ReferenceKey, x: Float) -> DynamicBodyPlacement {
        let volume = DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: 12))
            ?? .radial(first: .zero, second: .zero, radius: 12)
        return DynamicBodyPlacement(
            key: key,
            reference: FormID(0x0000_0C01),
            definition: DynamicBodyDefinition(volumes: [volume], mass: 30),
            originPosition: SIMD3(x, startY, clutterDropHeight),
            orientation: .identityRotation
        )
    }
}

/// The eleven-state synthetic combat graph. Wildcard transitions key on the
/// events the runtimes raise. Trigger times spread over the first third of a
/// one-second clip, so a state fires its annotations over several fixed steps
/// and the ordering checks test the graph, not a list literal.
nonisolated enum CombatAcceptanceFixture {
    /// State ids, which are also the order the states are declared in.
    enum State: Int, CaseIterable {
        case idle = 0
        case walk = 1
        case draw = 2
        case sheathe = 3
        case attack = 4
        case block = 5
        case blockExit = 6
        case bowDraw = 7
        case bowRelease = 8
        case stagger = 9
        case recoil = 10
        case death = 11

        var name: String {
            switch self {
            case .idle: "Idle"
            case .walk: "Walk"
            case .draw: "WeaponDraw"
            case .sheathe: "WeaponSheathe"
            case .attack: "Attack"
            case .block: "Block"
            case .blockExit: "BlockExit"
            case .bowDraw: "BowDraw"
            case .bowRelease: "BowRelease"
            case .stagger: "Stagger"
            case .recoil: "Recoil"
            case .death: "Death"
            }
        }

        /// Where the state's clip holds bone 1, so a pose identifies a state.
        var boneX: Float {
            Float(rawValue) * 10
        }

        /// The annotations this state's clip fires, in order, with the local
        /// time each fires at.
        var annotations: [(time: Float, event: String)] {
            switch self {
            case .draw:
                [
                    (0.05, CombatGraphNames.beginWeaponDraw),
                    (0.15, CombatGraphNames.weapEquipOut)
                ]
            case .sheathe:
                [
                    (0.05, CombatGraphNames.beginWeaponSheathe),
                    (0.15, CombatGraphNames.unequipOut)
                ]
            case .attack:
                [
                    // The swing's own start comes back out of the graph as
                    // well as going in: `attackStart` is in the census on both
                    // sides, and the state machine opens its window on the
                    // fired one rather than on the raised one.
                    (0.02, CombatGraphNames.attackStart),
                    (0.05, CombatGraphNames.weaponSwing),
                    (0.10, CombatGraphNames.preHitFrame),
                    (0.15, CombatGraphNames.hitFrame),
                    (0.30, CombatGraphNames.attackStop)
                ]
            case .bowDraw:
                [
                    (0.05, ArcheryGraphNames.arrowAttach),
                    (0.20, ArcheryGraphNames.bowDrawn)
                ]
            case .bowRelease:
                [
                    (0.05, ArcheryGraphNames.arrowRelease),
                    (0.10, ArcheryGraphNames.arrowDetach)
                ]
            case .block:
                [(0.02, CombatGraphNames.blockStart)]
            case .blockExit:
                [(0.02, CombatGraphNames.blockStop)]
            case .stagger:
                [(0.30, CombatGraphNames.staggerStop)]
            case .recoil:
                [(0.20, CombatGraphNames.recoilStop)]
            case .death:
                [(0.10, RagdollGraphNames.addRagdollToWorld)]
            default:
                []
            }
        }
    }

    /// Every wildcard edge, as (event, destination) pairs. A phase that ends on
    /// its own has a return edge on its clip's annotation, so a second
    /// `attackStart` can reach `Attack` again. `bowDrawn` has no edge: full draw
    /// holds until the release event.
    static let wildcardEdges: [(event: String, state: State)] = [
        (LocomotionGraphNames.moveStart, .walk),
        (LocomotionGraphNames.moveStop, .idle),
        (CombatGraphNames.weapEquip, .draw),
        (CombatGraphNames.weapEquipOut, .idle),
        (CombatGraphNames.unequip, .sheathe),
        (CombatGraphNames.unequipOut, .idle),
        (CombatGraphNames.attackStart, .attack),
        (CombatGraphNames.attackStop, .idle),
        (CombatGraphNames.blockStart, .block),
        (CombatGraphNames.blockStop, .blockExit),
        (ArcheryGraphNames.bowDrawStart, .bowDraw),
        (ArcheryGraphNames.attackRelease, .bowRelease),
        (ArcheryGraphNames.arrowDetach, .idle),
        (CombatGraphNames.staggerStart, .stagger),
        (CombatGraphNames.staggerStop, .idle),
        (CombatGraphNames.recoilStart, .recoil),
        (CombatGraphNames.recoilStop, .idle),
        (RagdollGraphNames.bleedOutStart, .death),
        (RagdollGraphNames.deathAnim, .death)
    ]

    static let machineName = "CombatAcceptanceBehavior"

    /// Every event the graph declares: the locomotion set the bridge raises,
    /// plus every combat, archery and ragdoll name either side of the seam
    /// uses. Deduplicated with the first spelling winning, so an id is stable
    /// across runs.
    static let events: [String] = {
        var seen: Set<String> = []
        return (
            LocomotionGraphNames.events
                + CombatGraphNames.raisedEvents + CombatGraphNames.observedEvents
                + ArcheryGraphNames.raisedEvents + ArcheryGraphNames.observedEvents
                + RagdollGraphNames.deathEvents + RagdollGraphNames.handOffEvents
        ).filter { seen.insert($0).inserted }
    }()

    /// Every variable the three runtimes write, plus the locomotion set.
    static let variables: [BehaviorVariableSpec] =
        LocomotionAcceptanceFixture.variables
            + [
                BehaviorVariableSpec(CombatGraphNames.isAttacking, .bool, 0),
                BehaviorVariableSpec(CombatGraphNames.isBlocking, .bool, 0),
                BehaviorVariableSpec(CombatGraphNames.isStaggering, .bool, 0),
                BehaviorVariableSpec(CombatGraphNames.staggerMagnitude, .real, 0),
                BehaviorVariableSpec(CombatGraphNames.isRecoiling, .bool, 0),
                BehaviorVariableSpec(CombatGraphNames.recoilMagnitude, .real, 0),
                BehaviorVariableSpec(CombatGraphNames.weaponSpeedMult, .real, 1),
                BehaviorVariableSpec(CombatGraphNames.rightHandType, .int32, 0),
                BehaviorVariableSpec(CombatGraphNames.leftHandType, .int32, 0),
                BehaviorVariableSpec(ArcheryGraphNames.isBowDrawn, .bool, 0)
            ]

    static func eventID(_ name: String) -> Int {
        events.firstIndex(of: name) ?? -1
    }

    /// One static clip per state, named for the state, keyed through
    /// `BehaviorClipTable.key` because the table normalizes separators and case
    /// on lookup.
    static var clips: BehaviorClipTable {
        var byName: [String: any BehaviorClip] = [:]
        for state in State.allCases {
            byName[BehaviorClipTable.key(state.name)] = BehaviorStaticClip(
                samples: [BehaviorFixture.sample(bone: 1, x: state.boneX)]
            )
        }
        return BehaviorClipTable(byName: byName)
    }

    /// A fresh instance of the graph. Called once per participant: the player's
    /// and the opponent's instances share their declarations and nothing else,
    /// which is what lets the gate assert that a stagger raised on the opponent
    /// reached the opponent.
    static func instance() -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let root = build(into: &table)
        return BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(variables: variables, events: events),
            clips: clips
        )
    }

    // MARK: - Building

    /// Lays the machine out in one table: one trigger array and one clip per
    /// state, the wildcard array, the states, and the machine itself.
    private static func build(into table: inout BehaviorObjectTable) -> HKXPointerTarget {
        var generators: [State: HKXPointerTarget] = [:]
        for state in State.allCases {
            let triggers = state.annotations.isEmpty ? nil : table.add(
                BehaviorFixture.clipTriggers(state.annotations.map {
                    BehaviorTriggerSpec(localTime: $0.time, eventId: eventID($0.event))
                }),
                at: 0x100 + state.rawValue * 0x10
            )
            generators[state] = table.add(
                BehaviorFixture.clipGenerator(
                    state.name, animationName: state.name, triggers: triggers
                ),
                at: 0x200 + state.rawValue * 0x10
            )
        }
        let wildcards = table.add(
            BehaviorStateMachineFixture.transitions(
                wildcardEdges.map { edge in
                    disablingConditions(BehaviorTransitionSpec(
                        eventId: eventID(edge.event), toStateId: edge.state.rawValue
                    ))
                }
            ),
            at: 0x400
        )
        var states: [HKXPointerTarget?] = []
        for state in State.allCases {
            states.append(table.add(
                BehaviorStateMachineFixture.stateInfo(BehaviorStateSpec(
                    stateId: state.rawValue,
                    name: state.name,
                    generator: generators[state]
                )),
                at: 0x500 + state.rawValue * 0x10
            ))
        }
        return table.add(
            BehaviorStateMachineFixture.machine(
                machineName, states: states, wildcardTransitions: wildcards
            ),
            at: 0x600
        )
    }

    /// `FLAG_DISABLE_CONDITION` is what the exporter sets on every transition
    /// carrying no condition object; none of these carry one, so all of them
    /// set it or the evaluator would look for a condition that is not there.
    private static func disablingConditions(
        _ spec: BehaviorTransitionSpec
    ) -> BehaviorTransitionSpec {
        var updated = spec
        updated.flags = BehaviorTransitionFlag.disableCondition
        return updated
    }
}
