// A guard warns an intruder twice and then attacks, a follower sprints and sneaks with its
// target, and the situation scan names combat, spectator, and dead-body situations.

@testable import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyWorldInterface
import simd
import Testing

struct PackageProcedureGuardTests {
    private static let intruder = ReferenceKey.player

    /// A guard at the origin: attack inside 100 units, warn inside 500.
    private func guardMachine(
        warnings: GuardWarningSettings = .vanilla
    ) -> PackageProcedureMachine {
        var setup = PackageProcedureSetup(kind: .guardArea, center: .zero, destination: .zero)
        setup.guardWarnings = warnings
        setup.watched = Self.intruder
        setup.near = 100
        setup.far = 500
        var machine = PackageProcedureMachine(setup: setup)
        _ = machine.start()
        _ = machine.handle(.arrived)
        return machine
    }

    private func observe(
        _ key: ReferenceKey, at x: Float, dead: Bool = false, fighting: Bool = false
    ) -> PackageSituationObservation {
        PackageSituationObservation(
            key: key,
            position: [x, 0, 0],
            isDead: dead,
            isFighting: fighting
        )
    }

    private func sense(
        _ machine: inout PackageProcedureMachine, at x: Float
    ) -> [PackageProcedureCommand] {
        machine.handle(.sensed(PackageSenses(actor: .zero, watched: [x, 0, 0])))
    }

    @Test func aGuardWarnsTwiceThenAttacks() {
        var machine = guardMachine()
        #expect(machine.state == .waiting)
        #expect(sense(&machine, at: 1000).isEmpty)
        #expect(sense(&machine, at: 300) == [.act(.warn(Self.intruder, level: 1))])
        _ = machine.handle(.acted(.done))
        #expect(sense(&machine, at: 300).isEmpty)
        _ = machine.handle(.tick(GuardWarningSettings.vanilla.warningSeconds))
        #expect(sense(&machine, at: 300) == [.act(.warn(Self.intruder, level: 2))])
        _ = machine.handle(.acted(.done))
        _ = machine.handle(.tick(GuardWarningSettings.vanilla.warningSeconds))
        #expect(sense(&machine, at: 300) == [.act(.attack(Self.intruder, startsCombat: true))])
    }

    @Test func iGuardWarningsSetsHowOftenAGuardWarns() {
        var settings = GuardWarningSettings.vanilla
        settings.warnings = 1
        settings.warningSeconds = 2
        var machine = guardMachine(warnings: settings)
        #expect(sense(&machine, at: 300) == [.act(.warn(Self.intruder, level: 1))])
        _ = machine.handle(.acted(.done))
        _ = machine.handle(.tick(1))
        #expect(sense(&machine, at: 300).isEmpty)
        _ = machine.handle(.tick(1))
        #expect(sense(&machine, at: 300) == [.act(.attack(Self.intruder, startsCombat: true))])
    }

    @Test func aGuardAttacksAtOnceInsideTheImmediateRadius() {
        var machine = guardMachine()
        #expect(sense(&machine, at: 50) == [.act(.attack(Self.intruder, startsCombat: true))])
    }

    @Test func aGuardStandsDownWhenTheIntruderLeaves() {
        var machine = guardMachine()
        _ = sense(&machine, at: 300)
        _ = machine.handle(.acted(.lasts(seconds: 1)))
        _ = machine.handle(.tick(1))
        #expect(machine.isWarning)
        #expect(sense(&machine, at: 900) == [.act(.standDown)])
        _ = machine.handle(.acted(.done))
        #expect(!machine.isWarning)
        #expect(machine.state == .waiting)
    }

    @Test func aGuardWithoutATrespassLineStillCountsTheWarning() {
        var machine = guardMachine()
        _ = sense(&machine, at: 300)
        _ = machine.handle(.acted(.failed))
        #expect(machine.state == .waiting)
        #expect(machine.warnings == 1)
    }

    @Test func aFollowerMatchesItsTargetsGait() {
        #expect(PackageProcedureMachine.followGait(distance: 50, targetGait: .sneak) == .sneak)
        #expect(PackageProcedureMachine.followGait(distance: 50, targetGait: .sprint) == .sprint)
        #expect(PackageProcedureMachine.followGait(distance: 50, targetGait: .walk) == nil)
        #expect(PackageProcedureMachine.followGait(distance: 400, targetGait: .walk) == .sprint)
    }

    @Test func aFollowerWalksAgainWhenItsTargetStartsToSprint() {
        var setup = PackageProcedureSetup(kind: .follow, center: .zero)
        setup.watched = Self.intruder
        setup.far = 100
        var machine = PackageProcedureMachine(setup: setup)
        _ = machine.start()
        let first = machine.handle(.sensed(PackageSenses(
            actor: .zero, watched: [200, 0, 0], watchedGait: .walk
        )))
        #expect(first == [.pace(nil), .move(to: [200, 0, 0])])
        let sprint = machine.handle(.sensed(PackageSenses(
            actor: .zero, watched: [200, 0, 0], watchedGait: .sprint
        )))
        #expect(sprint == [.pace(.sprint), .move(to: [200, 0, 0])])
    }

    @Test func theSituationScanNamesEachSituation() {
        let fighter = ReferenceKey.plugin(name: "skyrim.esm", objectID: 1)
        let watcher = ReferenceKey.plugin(name: "skyrim.esm", objectID: 2)
        let mourner = ReferenceKey.plugin(name: "skyrim.esm", objectID: 3)
        let body = ReferenceKey.plugin(name: "skyrim.esm", objectID: 4)
        let far = ReferenceKey.plugin(name: "skyrim.esm", objectID: 5)
        let observations = [
            observe(fighter, at: 0, fighting: true), observe(watcher, at: 1000),
            observe(mourner, at: 9000), observe(body, at: 9500, dead: true),
            observe(far, at: 50000)
        ]
        let situations = PackageSituationScan.situations(
            of: [fighter, watcher, mourner, body, far], observations: observations
        )
        #expect(situations == [fighter: .combat, watcher: .spectator, mourner: .observeDeadBody])
    }
}
