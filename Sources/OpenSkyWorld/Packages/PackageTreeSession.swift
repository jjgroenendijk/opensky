// The session side of one actor's procedure tree: branch conditions read the live
// context, and parameters resolve through the package world.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

@MainActor
struct PackageTreeSession: PackageTreeHost, PackageInputResolving {
    let world: any PackageWorld
    let actor: ReferenceKey
    let aliasQuest: FormID?
    let clock: GameClock
    let values: [Int8: Package.DataValue]
    let translation: FormIDTranslation?
    let seed: UInt64
    /// Read once, on the first branch condition, because a context costs a world walk.
    private var context: ConditionContext?

    init(
        world: any PackageWorld, actor: ReferenceKey, hold: PackageHold,
        package: ResolvedPackage, clock: GameClock, translation: FormIDTranslation?
    ) {
        self.world = world
        self.actor = actor
        aliasQuest = hold.aliasQuest
        self.clock = clock
        self.translation = translation
        values = PackageProcedureInputs.values(
            of: package.package,
            template: package.definition == package.package ? nil : package.definition
        )
        seed = UInt64(package.package.formID.rawValue)
    }

    mutating func passes(_ conditions: [Condition]) -> Bool {
        var live = context ?? world.packageConditionContext(clock: clock)
        live.subject = actor
        live.clock = clock
        context = live
        var evaluator = ConditionEvaluator(context: live)
        evaluator.context.formIDTranslation = translation
        let outcome = evaluator.evaluate(conditions)
        evaluator.context.formIDTranslation = live.formIDTranslation
        context = evaluator.context
        return outcome.isTrue
    }

    func setup(
        for leaf: PackageProcedureLeaf, objectLists: [Int8: [ReferenceKey]]
    ) -> PackageLeafSetup {
        PackageProcedureInputs(
            leaf: leaf, values: values, objectLists: objectLists,
            start: world.packageActorPosition(actor) ?? .zero,
            seed: seed &+ UInt64(leaf.node)
        ).build(resolver: self)
    }

    func senses(watching watched: ReferenceKey) -> PackageSenses? {
        world.packageActorPosition(actor).map {
            PackageSenses(actor: $0, watched: world.packageActorPosition(watched))
        }
    }

    func place(of location: Package.Location) -> PackagePlace? {
        world.packagePlace(of: location, actor: actor, aliasQuest: aliasQuest)
    }

    func reference(of target: Package.Target) -> ReferenceKey? {
        world.packageReference(target, actor: actor, aliasQuest: aliasQuest)
    }

    func position(of reference: ReferenceKey) -> SIMD3<Float>? {
        world.packageActorPosition(reference)
    }

    func patrolPath(from start: Package.Target) -> [SIMD3<Float>]? {
        world.packagePatrolPath(from: start, actor: actor, aliasQuest: aliasQuest)
    }

    func seat(in furniture: ReferenceKey) -> PackageSeat? {
        world.packageSeat(in: furniture, actor: actor)
    }
}
