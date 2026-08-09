// Package selection and bounded procedure machines over synthetic records and
// synthetic navmesh geometry. No game data is embedded.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct PackageRuntimeTests {
    private static let actorKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x500)
    private static let conditionKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x700)

    @Test func firstScheduledTrueConditionWinsAndEnableFlipReevaluates() throws {
        let scheduled = try package(
            id: 0x100,
            editorID: "Scheduled",
            schedule: PackageFixture.scheduleValue(hour: 8, duration: 240),
            condition: ConditionEvaluatorFixture.field(
                comparisonValue: Float(1).bitPattern,
                functionIndex: 35,
                runOn: 2,
                reference: 0x700
            )
        )
        let fallback = try package(id: 0x101, editorID: "Fallback")
        let actor = try actorBase(id: 0x600, packages: [0x100, 0x101])
        let store = PackageStore(
            packages: [scheduled, fallback],
            actorTemplates: ActorTemplateResolver(actors: [0x600: actor], leveledActors: [:])
        )
        var runtime = ActorPackageRuntime(store: store)
        try runtime.register(actor: Self.actorKey, base: actor.formID)

        runtime.advance(clock: GameClock(hour: 9)) { _ in
            tryContext(enableState: .disabled)
        }
        #expect(runtime.currentPackage(for: Self.actorKey)?.package.formID == FormID(0x100))
        let scheduledReadout = try #require(runtime.readouts().first)
        #expect(scheduledReadout.editorID == "Scheduled")
        #expect(scheduledReadout.schedule?.hour == 8)

        runtime.forceReevaluate(
            actor: Self.actorKey,
            clock: GameClock(hour: 9),
            context: tryContext(enableState: .enabled)
        )
        #expect(runtime.currentPackage(for: Self.actorKey)?.package.formID == FormID(0x101))

        runtime.forceReevaluate(
            actor: Self.actorKey,
            clock: GameClock(hour: 12),
            context: tryContext(enableState: .disabled)
        )
        #expect(runtime.currentPackage(for: Self.actorKey)?.package.formID == FormID(0x101))
    }

    @Test func boundedAndOnDemandEvaluationDoNotPollEveryAdvance() throws {
        let actor = try actorBase(id: 0x600, packages: [0x100])
        let store = try PackageStore(
            packages: [package(id: 0x100, editorID: "Always")],
            actorTemplates: ActorTemplateResolver(actors: [0x600: actor], leveledActors: [:])
        )
        var changes = 0
        var runtime = ActorPackageRuntime(store: store)
        runtime.onSelectionChanged = { _ in changes += 1 }
        try runtime.register(actor: Self.actorKey, base: actor.formID)
        runtime.advance(clock: GameClock(hour: 9)) { _ in ConditionContext() }
        runtime.advance(clock: GameClock(hour: 9.1)) { _ in
            Issue.record("context should not be requested before the bounded interval")
            return ConditionContext()
        }
        #expect(changes == 1)
        runtime.forceReevaluate(
            actor: Self.actorKey,
            clock: GameClock(hour: 9.1),
            context: ConditionContext()
        )
        #expect(changes == 1)
    }

    @Test func packageAndActorTemplateChainsResolveOrReportCycles() throws {
        let procedureTemplate = try package(
            id: 0x200,
            editorID: "Sleep",
            procedureNames: ["Sleep"]
        )
        let concrete = try package(id: 0x100, editorID: "Bedtime", template: 0x200)
        let templateActor = try actorBase(id: 0x601, packages: [0x100])
        let actor = try actorBase(
            id: 0x600,
            templateFlags: 0x20,
            template: 0x601,
            packages: [0x999]
        )
        let resolver = ActorTemplateResolver(
            actors: [0x600: actor, 0x601: templateActor],
            leveledActors: [:]
        )
        let store = PackageStore(packages: [concrete, procedureTemplate], actorTemplates: resolver)
        #expect(try store.packageStack(for: actor.formID).value == [FormID(0x100)])
        let resolved = try store.resolve(FormID(0x100))
        #expect(resolved.templateChain == [FormID(0x100), FormID(0x200)])
        #expect(resolved.procedure == .sleep)

        let first = try package(id: 0x300, template: 0x301)
        let second = try package(id: 0x301, template: 0x300)
        let cyclic = PackageStore(packages: [first, second], actorTemplates: resolver)
        #expect(throws: PackageResolveError.templateCycle([
            FormID(0x300), FormID(0x301), FormID(0x300)
        ])) {
            _ = try cyclic.resolve(FormID(0x300))
        }
    }

    @Test func procedureMachinesAreDeterministicAndFeedSyntheticNavmesh() throws {
        let destination = SIMD3<Float>(19, 19, 0)
        var travel = PackageProcedureMachine(
            kind: .travel,
            center: .zero,
            destination: destination,
            radius: 0,
            seed: 1
        )
        #expect(travel.start() == [.move(to: destination)])

        let mesh = try NavigationRuntimeFixture.grid(id: 0x900, columns: 2, rows: 2)
        var graph = RuntimeNavigationGraph()
        graph.setCell(.interior(FormID(1)), scene: NavigationRuntimeFixture.scene(
            location: .interior(FormID(1)),
            navmeshes: [mesh]
        ))
        let path = graph.findPath(NavigationPathQuery(
            start: SIMD3(1, 1, 0),
            target: destination,
            capsuleRadius: 1,
            projectionRadius: 3
        ))
        #expect(path.path != nil)
        #expect(travel.handle(.arrived).isEmpty)
        #expect(travel.state == .complete)

        for (kind, clip) in [(PackageProcedureKind.sleep, PackageLoopClip.sleep), (.eat, .eat)] {
            var machine = PackageProcedureMachine(
                kind: kind,
                center: .zero,
                destination: destination,
                radius: 0,
                seed: 2
            )
            #expect(machine.start() == [.move(to: destination)])
            #expect(machine.handle(.arrived) == [.playLoop(clip)])
            #expect(machine.state == .looping(clip))
        }

        for kind in [PackageProcedureKind.wander, .sandbox] {
            var first = PackageProcedureMachine(
                kind: kind, center: .zero, radius: 10, seed: 42
            )
            var second = PackageProcedureMachine(
                kind: kind, center: .zero, radius: 10, seed: 42
            )
            #expect(first.start() == second.start())
            #expect(first.handle(.arrived).isEmpty)
            #expect(!first.handle(.tick(4)).isEmpty)
        }
    }

    private func tryContext(enableState: ReferenceEnableState) -> ConditionContext {
        ConditionContext(
            referenceEnable: ReferenceEnableResolution(states: [
                Self.conditionKey: enableState
            ]),
            references: (try? ConditionEvaluatorFixture.references([
                (formID: 0x700, base: 0x800)
            ])) ?? .empty
        )
    }

    private func package(
        id: UInt32,
        editorID: String? = nil,
        schedule: Package.Schedule = .anytime,
        condition: ESMField? = nil,
        template: UInt32? = nil,
        procedureNames: [String] = []
    ) throws -> Package {
        var conditions = ConditionList()
        if let condition {
            try conditions.decode(field: condition)
        }
        return Package(
            formID: FormID(id),
            editorID: editorID,
            general: Package.GeneralData(
                flags: [],
                kind: .package,
                interruptOverride: 0,
                preferredSpeed: .walk,
                interruptFlags: 0
            ),
            schedule: schedule,
            conditions: conditions,
            template: template.map(FormID.init),
            dataInputs: [],
            procedureTypes: procedureNames,
            scriptData: ScriptData(ownerType: "PACK")
        )
    }

    private func actorBase(
        id: UInt32,
        templateFlags: UInt16 = 0,
        template: UInt32? = nil,
        packages: [UInt32]
    ) throws -> ActorBase {
        var acbs = Data(count: 18)
        acbs.appendUInt16(templateFlags)
        acbs.appendUInt32(0)
        var fields = ESMFixture.field("ACBS", acbs)
        if let template {
            fields += PackageRuntimeFixture.formIDField("TPLT", template)
        }
        for package in packages {
            fields += PackageRuntimeFixture.formIDField("PKID", package)
        }
        return try ActorBase(
            record: PackageFixture.parse(ESMFixture.record("NPC_", formID: id, data: fields)),
            localized: false
        )
    }
}

private enum PackageRuntimeFixture {
    static func formIDField(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }
}

extension NavigationPathResult {
    fileprivate var path: NavigationPath? {
        guard case let .path(path) = self else { return nil }
        return path
    }
}
