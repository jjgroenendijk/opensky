// Follower command mode: the agree and refuse rules, and the walk-then-act state
// machine (docs/engine/follower-commands.md).

@testable import OpenSkyAIPackages
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import simd
import Testing

@MainActor
private final class FakeFollowerWorld: FollowerCommandWorld {
    var positions: [ReferenceKey: SIMD3<Float>] = [:]
    var followerCommandPlayerPosition: SIMD3<Float>? = .zero
    var morality: Float = 3
    var lines: [String] = []
    var ended: [(ReferenceKey, Bool)] = []
    var moves: [SIMD3<Float>] = []
    var performed: [FollowerCommandTask] = []
    var moveSucceeds = true

    func followerCommandPosition(of actor: ReferenceKey) -> SIMD3<Float>? {
        positions[actor]
    }

    func followerMorality(_: ReferenceKey) -> Float {
        morality
    }

    func sayFavorLine(_ subtype: FourCC, follower _: ReferenceKey) {
        lines.append(subtype.description)
    }

    func endFavor(_ follower: ReferenceKey, announces: Bool) {
        ended.append((follower, announces))
    }

    func moveFollower(_: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        moves.append(point)
        return moveSucceeds
    }

    func stopFollower(_: ReferenceKey) {}

    var held: Set<ReferenceKey> = []
    let followerCommandSettings = FollowerCommandSettings.vanilla

    func holdFollower(_ follower: ReferenceKey) {
        held.insert(follower)
    }

    func releaseFollower(_ follower: ReferenceKey) {
        held.remove(follower)
    }

    func performFollowerTask(_ task: FollowerCommandTask, follower _: ReferenceKey) -> Bool {
        performed.append(task)
        return true
    }
}

struct FollowerCommandRulesTests {
    private let follower = ReferenceKey.plugin(name: "test.esm", objectID: 0x100)
    private let chest = ReferenceKey.plugin(name: "test.esm", objectID: 0x200)

    private func target(_ kind: FollowerCommandTarget.Kind) -> FollowerCommandTarget {
        FollowerCommandTarget(key: chest, kind: kind, position: SIMD3(500, 0, 0))
    }

    @Test func eachKindGetsItsAction() {
        let actions = [
            FollowerCommandTarget.Kind.item: FollowerCommandTask.Action.pickUp,
            .container: .loot, .corpse: .loot, .actor: .attack,
            .door: .activate, .activator: .activate, .furniture: .activate, .ground: .moveTo
        ]
        for (kind, action) in actions {
            let decision = FollowerCommandRules.decide(
                target(kind),
                follower: follower,
                morality: 0
            )
            guard case let .agree(task) = decision else {
                Issue.record("\(kind) was refused")
                continue
            }
            #expect(task.action == action)
            #expect(decision.line == "AGRE")
        }
    }

    @Test func refusalsSayTheRefuseLine() {
        var noFavor = target(.activator)
        noFavor.noFavorAllowed = true
        var keyOnly = target(.door)
        keyOnly.lock = .requiresKey
        let itself = FollowerCommandTarget(key: follower, kind: .actor, position: .zero)
        let cases: [(FollowerCommandTarget?, FollowerCommandRefusal)] = [
            (nil, .nothing), (noFavor, .noFavorAllowed), (keyOnly, .needsKey), (itself, .itself)
        ]
        for (target, reason) in cases {
            let decision = FollowerCommandRules.decide(target, follower: follower, morality: 0)
            #expect(decision == .refuse(reason))
            #expect(decision.line == "REFU")
        }
    }

    @Test func moralityLimitsCrimes() {
        var owned = target(.item)
        owned.isOwned = true
        var lockedOwned = target(.door)
        lockedOwned.lock = .adept
        lockedOwned.isOwned = true
        let innocent = target(.actor)
        var enemy = target(.actor)
        enemy.isHostile = true
        let rules = FollowerCommandRules.self
        #expect(rules.decide(owned, follower: follower, morality: 3) == .moralRefusal(.property))
        #expect(rules.decide(owned, follower: follower, morality: 3).line == "MREF")
        #expect(rules
            .decide(lockedOwned, follower: follower, morality: 3) == .moralRefusal(.property))
        #expect(rules.decide(innocent, follower: follower, morality: 1) == .moralRefusal(.violence))
        guard
            case let .agree(steal) = rules.decide(owned, follower: follower, morality: 2),
            case let .agree(open) = rules.decide(lockedOwned, follower: follower, morality: 2),
            case let .agree(fight) = rules.decide(enemy, follower: follower, morality: 3),
            case .agree = rules.decide(innocent, follower: follower, morality: 0)
        else {
            Issue.record("an allowed command was refused")
            return
        }
        #expect(steal.crime == .property)
        #expect(open.unlocks && open.crime == .property)
        #expect(fight.crime == nil && !fight.walks)
    }

    @Test func anOpenLockOfAnOwnerIsNoCrime() {
        var door = target(.door)
        door.isOwned = true
        guard case let .agree(task) = FollowerCommandRules.decide(
            door,
            follower: follower,
            morality: 3
        )
        else {
            Issue.record("refused")
            return
        }
        #expect(task.crime == nil && !task.unlocks)
    }
}

@MainActor
struct FollowerCommandCoordinatorTests {
    private let follower = ReferenceKey.plugin(name: "test.esm", objectID: 0x100)
    private let lever = ReferenceKey.plugin(name: "test.esm", objectID: 0x300)

    private func setUp() -> (FollowerCommandCoordinator, FakeFollowerWorld) {
        let world = FakeFollowerWorld()
        world.positions[follower] = SIMD3(0, 0, 0)
        let commands = FollowerCommandCoordinator(world: world)
        commands.favorStarted(follower)
        return (commands, world)
    }

    private var leverTarget: FollowerCommandTarget {
        FollowerCommandTarget(key: lever, kind: .activator, position: SIMD3(1000, 0, 0))
    }

    @Test func anAgreedCommandWalksThenActs() {
        let (commands, world) = setUp()
        #expect(commands.isChoosing)
        commands.command(leverTarget)
        #expect(world.lines == ["AGRE"])
        #expect(world.moves == [SIMD3(904, 0, 0)])
        #expect(commands.phase == .walking(
            follower: follower,
            task: FollowerCommandRules.task(for: leverTarget)
        ))
        #expect(world.held == [follower])
        commands.movementSettled(actor: follower, reason: .arrival)
        #expect(world.performed.map(\.action) == [.activate])
        #expect(commands.phase == .idle)
        #expect(commands.lastOutcome == .done)
        #expect(world.ended.map(\.1) == [false])
        #expect(world.held.isEmpty)
    }

    @Test func reachingTheTargetActsWithoutWaitingForTheMover() {
        let (commands, world) = setUp()
        commands.command(leverTarget)
        world.positions[follower] = SIMD3(950, 0, 0)
        commands.tick(0.1)
        #expect(world.performed.count == 1)
    }

    @Test func aRefusalKeepsCommandModeOpen() {
        let (commands, world) = setUp()
        commands.command(nil)
        #expect(world.lines == ["REFU"])
        #expect(commands.isChoosing)
        #expect(world.performed.isEmpty)
    }

    @Test func commandModeEndsWithTheExitLine() {
        let (commands, world) = setUp()
        #expect(commands.cancel())
        #expect(world.ended.map(\.1) == [true])
        #expect(commands.lastOutcome == .cancelled)
        #expect(!commands.cancel())
    }

    @Test func commandModeEndsWhenTheFollowerIsFar() {
        let (commands, world) = setUp()
        commands.tick(commands.settings.waitSeconds + 1)
        #expect(commands.isChoosing)
        world.positions[follower] = SIMD3(commands.settings.radius + 1, 0, 0)
        commands.tick(0.1)
        #expect(commands.lastOutcome == .tooFar)
        #expect(world.ended.map(\.1) == [true])
    }

    @Test func aFollowerSentToASpotWaitsThereThenFollowsAgain() {
        let (commands, world) = setUp()
        let spot = SIMD3<Float>(600, 200, 0)
        commands.command(FollowerCommandTarget(key: nil, kind: .ground, position: spot))
        #expect(world.lines == ["AGRE"])
        #expect(world.moves == [spot])
        commands.movementSettled(actor: follower, reason: .arrival)
        #expect(commands.phase == .waiting(follower: follower, left: commands.settings.waitSeconds))
        #expect(world.performed.isEmpty)
        #expect(world.held == [follower])
        commands.tick(commands.settings.waitSeconds - 1)
        #expect(commands.lastOutcome == nil)
        commands.tick(1)
        #expect(commands.lastOutcome == .done)
        #expect(world.held.isEmpty)
        #expect(world.ended.map(\.1) == [false])
    }

    @Test func aNewCommandModeForTheSameFollowerKeepsItsFlag() {
        let (commands, world) = setUp()
        commands.command(leverTarget)
        commands.favorStarted(follower)
        #expect(commands.isChoosing)
        #expect(world.ended.isEmpty)
        #expect(world.held.isEmpty)
    }

    @Test func aFailedWalkEndsTheTask() {
        let (commands, world) = setUp()
        world.moveSucceeds = false
        commands.command(leverTarget)
        #expect(commands.lastOutcome == .unreachable)
        #expect(commands.phase == .idle)
        commands.favorStarted(follower)
        world.moveSucceeds = true
        commands.command(leverTarget)
        commands.movementSettled(actor: follower, reason: .giveUp)
        #expect(commands.lastOutcome == .unreachable)
        #expect(world.performed.isEmpty)
    }

    @Test func aScriptThatClearsTheFavourStopsTheWalk() {
        let (commands, world) = setUp()
        commands.command(leverTarget)
        commands.favorEnded(follower)
        #expect(commands.phase == .idle)
        #expect(world.held.isEmpty)
    }
}
