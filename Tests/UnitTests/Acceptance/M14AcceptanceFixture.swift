// The M14 gate's world and graph, built in code (issue #191).
//
// Two pieces. `M14AcceptanceWorld` is the ground the capsule runs over: flat
// exterior, a walkable slope, and a basin with water deep enough to swim in,
// all as closed-form functions of x so a test can say where the player should
// be rather than reading a height out of a file. `M14AcceptanceFixture` is the
// synthetic behavior graph: eight states, one per locomotion state the gate
// names, wired to the events and variables `LocomotionGraphNames` declares.
//
// Everything here is invented. No packfile bytes, no extracted heights, no
// clip data from the install (AGENTS.md "Legal & IP boundary"). The vanilla
// half of the gate is `M14AcceptanceRealDataTests`, which is env-gated.

import Foundation
@testable import opensky
import simd

/// The synthetic terrain and water the route runs over.
///
/// Laid out west to east along +X, because the route is a straight line and a
/// one-dimensional height function is one a failing assertion can quote back:
///
///     x < 1600     flat, z = 0            walk, run, sneak, jump and land
///     1600 - 2000  20-degree rise to 144  the slope
///     2000 - 2300  plateau at 144         the sprint stretch
///     2300 - 2500  45-degree fall to -56  the bank into the water
///     2500 - 2900  basin floor at -56     swimming, 156 units under water
///     2900 - 3100  45-degree rise to 144  the far bank
///     x > 3100     plateau at 144         the run to the cell boundary
///
/// Both slopes sit under `WalkController.maximumSlopeDegrees` (50), so the
/// capsule walks them rather than sliding: a route that could not be walked
/// would prove nothing about locomotion.
nonisolated enum M14AcceptanceWorld {
    static let flatHeight: Float = 0
    static let plateauHeight: Float = 144
    static let basinHeight: Float = -56
    /// Water surface over the basin. 156 units above the floor, comfortably
    /// past `LocomotionBridge.swimEnterDepth` (90).
    static let waterSurface: Float = 100
    static let waterStartX: Float = 2350
    static let waterEndX: Float = 3050

    /// Ground height under a world XY.
    static func height(at position: SIMD2<Float>) -> Float {
        let x = position.x
        if x < 1600 {
            return flatHeight
        }
        if x < 2000 {
            return (x - 1600) * 0.36
        }
        if x < 2300 {
            return plateauHeight
        }
        if x < 2500 {
            return plateauHeight - (x - 2300)
        }
        if x < 2900 {
            return basinHeight
        }
        if x < 3100 {
            return basinHeight + (x - 2900)
        }
        return plateauHeight
    }

    /// The surface gradient, so the sampled normal is the real one for the
    /// slope the capsule is on rather than always straight up.
    static func gradient(at position: SIMD2<Float>) -> Float {
        let x = position.x
        if x >= 1600, x < 2000 {
            return 0.36
        }
        if x >= 2300, x < 2500 {
            return -1
        }
        if x >= 2900, x < 3100 {
            return 1
        }
        return 0
    }

    static func sampleGround(_ position: SIMD2<Float>) -> TerrainGroundSample? {
        let slope = gradient(at: position)
        let normal = simd_normalize(SIMD3<Float>(-slope, 0, 1))
        return TerrainGroundSample(height: height(at: position), normal: normal)
    }

    /// Water surface at a world XY, or nil where the route is dry.
    static func sampleWater(_ position: SIMD2<Float>) -> Float? {
        (waterStartX ... waterEndX).contains(position.x) ? waterSurface : nil
    }
}

/// The eight-state synthetic graph the route drives.
///
/// One state per locomotion state the gate names, each running a static clip
/// that holds bone 1 at its own translation, so the pose alone says which state
/// is showing. Every transition into a state is a wildcard keyed on the event
/// the bridge raises for it, which is what makes the route's own edges the
/// thing that moves the graph — nothing here is driven by a test-only poke.
///
/// The one exception is `Run`, and deliberately: running is a gait rather than
/// an edge, so the bridge raises no event for it. `moveStart` therefore carries
/// two wildcard transitions — a plain one to `Walk`, and a higher-priority one
/// to `Run` guarded by `Speed >= 270` — so the same edge lands in a different
/// state depending on how fast the player set off. That is how a machine
/// authored against real data tells the two apart, reduced to two states: the
/// vanilla files rank a conditioned transition above its unconditioned sibling
/// the same way.
nonisolated enum M14AcceptanceFixture {
    /// State ids, which are also the order the states are declared in.
    enum State: Int, CaseIterable {
        case idle = 0
        case walk = 1
        case run = 2
        case sprint = 3
        case jump = 4
        case land = 5
        case sneak = 6
        case swim = 7

        var name: String {
            switch self {
            case .idle: "Idle"
            case .walk: "Walk"
            case .run: "Run"
            case .sprint: "Sprint"
            case .jump: "Jump"
            case .land: "Land"
            case .sneak: "Sneak"
            case .swim: "Swim"
            }
        }

        /// Where the state's clip holds bone 1, so a pose identifies a state.
        var boneX: Float {
            Float(rawValue) * 10
        }
    }

    static let machineName = "M14PlayerLocomotion"
    /// The speed at which `Walk` hands over to `Run`. Halfway between the
    /// synthetic walk (180) and run (360) gaits.
    static let runSpeedThreshold: Float = 270

    /// A fresh instance of the graph. Called once per perspective: the two
    /// instances share their declarations and nothing else, which is what lets
    /// the gate assert that first and third person reach the same states from
    /// the same input.
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

    /// Every variable the bridge writes, plus the perspective flag it seeds.
    static let variables: [BehaviorVariableSpec] = [
        BehaviorVariableSpec(LocomotionGraphNames.speed, .real, 0),
        BehaviorVariableSpec(LocomotionGraphNames.speedSampled, .real, 0),
        BehaviorVariableSpec(LocomotionGraphNames.direction, .real, 0),
        BehaviorVariableSpec(LocomotionGraphNames.turnDelta, .real, 0),
        BehaviorVariableSpec(LocomotionGraphNames.isSprinting, .bool, 0),
        BehaviorVariableSpec(LocomotionGraphNames.isSneaking, .bool, 0),
        BehaviorVariableSpec(LocomotionGraphNames.isInSneak, .int32, 0),
        BehaviorVariableSpec(LocomotionGraphNames.inJumpState, .bool, 0),
        BehaviorVariableSpec(LocomotionGraphNames.speedWalk, .real, 0),
        BehaviorVariableSpec(LocomotionGraphNames.speedRun, .real, 0),
        BehaviorVariableSpec(LocomotionGraphNames.isFirstPerson, .bool, 0)
    ]

    /// Every event the bridge can raise, in `LocomotionGraphNames` order, so an
    /// event id here is that array's index.
    static let events = LocomotionGraphNames.events

    static func eventID(_ name: String) -> Int {
        events.firstIndex(of: name) ?? -1
    }

    /// One static clip per state, named for the state. Keyed through
    /// `BehaviorClipTable.key` because the table normalizes separators and case
    /// on lookup, and a raw key would never be found.
    static var clips: BehaviorClipTable {
        var byName: [String: any BehaviorClip] = [:]
        for state in State.allCases {
            byName[BehaviorClipTable.key(state.name)] = BehaviorStaticClip(
                samples: [BehaviorFixture.sample(bone: 1, x: state.boneX)]
            )
        }
        return BehaviorClipTable(byName: byName)
    }

    // MARK: - Building

    /// Lays the machine out in one table: clips, the wildcard array, the one
    /// local transition array, the eight states, and the machine itself.
    private static func build(into table: inout BehaviorObjectTable) -> HKXPointerTarget {
        var generators: [State: HKXPointerTarget] = [:]
        for state in State.allCases {
            generators[state] = table.add(
                BehaviorFixture.clipGenerator(state.name, animationName: state.name),
                at: 0x100 + state.rawValue * 0x10
            )
        }
        let condition = table.add(
            BehaviorStateMachineFixture.condition(
                "\(LocomotionGraphNames.speed) >= \(Int(runSpeedThreshold))"
            ),
            at: 0x080
        )
        var specs = wildcardSpecs()
        specs.append(BehaviorTransitionSpec(
            eventID(LocomotionGraphNames.moveStart), to: .run, condition: condition
        ))
        let wildcards = table.add(
            BehaviorStateMachineFixture.transitions(specs), at: 0x210
        )
        var states: [HKXPointerTarget?] = []
        for state in State.allCases {
            states.append(table.add(
                BehaviorStateMachineFixture.stateInfo(BehaviorStateSpec(
                    stateId: state.rawValue,
                    name: state.name,
                    generator: generators[state]
                )),
                at: 0x300 + state.rawValue * 0x10
            ))
        }
        return table.add(
            BehaviorStateMachineFixture.machine(
                machineName, states: states, wildcardTransitions: wildcards
            ),
            at: 0x400
        )
    }

    /// The wildcard array: one transition per edge the bridge raises. Jump is
    /// the only pair that does not return to `Idle` — a landing is its own
    /// state, and `moveStop` is what leaves it.
    private static func wildcardSpecs() -> [BehaviorTransitionSpec] {
        [
            (LocomotionGraphNames.moveStart, State.walk),
            (LocomotionGraphNames.moveStop, .idle),
            (LocomotionGraphNames.sprintStart, .sprint),
            (LocomotionGraphNames.sprintStop, .walk),
            (LocomotionGraphNames.sneakStart, .sneak),
            (LocomotionGraphNames.sneakStop, .idle),
            (LocomotionGraphNames.jumpUp, .jump),
            (LocomotionGraphNames.jumpFall, .jump),
            (LocomotionGraphNames.jumpLand, .land),
            (LocomotionGraphNames.swimStart, .swim),
            (LocomotionGraphNames.swimStop, .idle)
        ].map { BehaviorTransitionSpec(eventID($0.0), to: $0.1) }
    }
}

extension BehaviorTransitionSpec {
    /// A wildcard-shaped transition to one of the fixture's states. Conditions
    /// are opt-in: `FLAG_DISABLE_CONDITION` is what the exporter sets on every
    /// transition that carries no condition object, so passing one has to clear
    /// it or the condition would never be read.
    init(
        _ eventId: Int,
        to state: M14AcceptanceFixture.State,
        condition: HKXPointerTarget? = nil
    ) {
        self.init(eventId: eventId, toStateId: state.rawValue)
        self.condition = condition
        flags = condition == nil ? BehaviorTransitionFlag.disableCondition : 0
        // A conditioned transition outranks its unconditioned sibling on the
        // same event, which is how one edge reaches two states.
        priority = condition == nil ? 0 : 1
    }
}
