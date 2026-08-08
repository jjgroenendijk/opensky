// The M15 gate's world and graph, built in code (issue #198).
//
// Two pieces, the same split `M14AcceptanceFixture` made one milestone earlier.
// `M15AcceptanceWorld` is the ground the fight happens on: a flat floor, a wall
// for an arrow to stick in, and the clutter a body can shove. `M15AcceptanceFixture`
// is the synthetic behavior graph the fight is driven through: eleven states
// covering draw, sheathe, attack, block, bow draw, loose, stagger, recoil,
// bleedout and death, wired to the census names `CombatGraphNames`,
// `ArcheryGraphNames` and `RagdollGraphNames` declare.
//
// The graph is what makes this a gate rather than a set of unit tests run in a
// row. Every contact frame, nock, release and ragdoll hand-off in the route is
// a *clip trigger* firing out of the graph on its own clock, exactly as a
// vanilla annotation does — not a name a test handed the runtime. A route that
// fed the events in by hand would prove the runtimes work and prove nothing
// about the seam between them and the animation.
//
// Everything here is invented. No packfile bytes, no extracted clip data, no
// heights from the install (AGENTS.md "Legal & IP boundary"). The vanilla half
// of the gate is `M15AcceptanceRealDataTests`, which is env-gated.

import Foundation
@testable import opensky
import simd

/// The synthetic arena the fight happens in.
///
/// Deliberately flat: M14 already proved locomotion resolves over slopes, water
/// and a streaming boundary, and a gate about combat wants the one variable it
/// is measuring to be the fight. The wall is what an arrow that misses can
/// stick in, and it stands far enough east that a shot has to actually fly to
/// reach it.
nonisolated enum M15AcceptanceWorld {
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

    static func sampleGround(_ position: SIMD2<Float>) -> TerrainGroundSample? {
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

/// The eleven-state synthetic combat graph the route drives.
///
/// One state per phase of the fight the gate names, each running a clip whose
/// triggers fire the observed events that phase is defined by. The transitions
/// into the states are wildcards keyed on the events the runtimes *raise*, so
/// the route's own edges are what move the graph and the graph's own clock is
/// what answers.
///
/// Trigger times are spread across the first third of a one-second clip so that
/// a state entered on one frame fires its annotations over the following
/// handful of fixed steps rather than all at once, which is what makes the
/// ordering assertions in `M15AcceptanceTests` about the graph rather than
/// about a list literal.
nonisolated enum M15AcceptanceFixture {
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

    /// Every wildcard edge, as (event, destination) pairs.
    ///
    /// Each phase has an entry edge keyed on the event a runtime *raises* and,
    /// where the phase ends on its own, a return edge keyed on the annotation
    /// its own clip fires. The returns are what let the route swing twice: a
    /// state machine will not transition into the state it is already in, so a
    /// second `attackStart` reaches `Attack` only because the first swing's
    /// `attackStop` annotation took the graph back out.
    ///
    /// `bowDrawn` deliberately has no edge: full draw is a hold, and the state
    /// stays put until the release event arrives.
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

    static let machineName = "M15CombatBehavior"

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
        M14AcceptanceFixture.variables
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
