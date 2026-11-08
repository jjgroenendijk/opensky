// A dependent animated object takes its owner's idle events, each actor once, a
// seated actor's idle conditions run on its furniture as the Target, and the sit
// states `GetSitting` reads.

@testable import OpenSkyActorPresentation
import OpenSkyConditions
import OpenSkyFormatsESM
import Testing

@MainActor
struct IdleDependentsTests {
    private static func actor(_ id: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: id)
    }

    @Test func dependentsFollowTheirOwnerInOrderOnce() {
        let idles = IdleCoordinator(world: nil, data: nil)
        idles.addDependent(Self.actor(2), of: Self.actor(1))
        idles.addDependent(Self.actor(3), of: Self.actor(1))
        idles.addDependent(Self.actor(1), of: Self.actor(3))
        idles.addDependent(Self.actor(2), of: Self.actor(1))
        #expect(idles.withDependents(Self.actor(1)) == [1, 2, 3].map(Self.actor))
        idles.removeDependent(Self.actor(2), of: Self.actor(1))
        #expect(idles.withDependents(Self.actor(1)) == [1, 3].map(Self.actor))
    }

    @Test func aSeatedActorsFurnitureIsTheConditionTarget() {
        let idles = IdleCoordinator(world: nil, data: nil)
        let block = Self.actor(9)
        #expect(idles.conditionContext(for: Self.actor(1)).target == nil)
        idles.furnitureUses[Self.actor(1)] = FurnitureUse(
            sitState: .sitting, animationType: 1, entry: 0x40000, furniture: block
        )
        let context = idles.conditionContext(for: Self.actor(1))
        #expect(context.subject == Self.actor(1))
        #expect(context.target == block)
    }

    /// `GetSitting` reads 4 while the actor gets up, then 0. A sit whose idle still
    /// loads keeps reading 1.
    @Test func gettingUpReadsReadyToStandUntilTheStandUpEnds() {
        let idles = IdleCoordinator(world: nil, data: nil)
        let sitter = Self.actor(1)
        let loader = Self.actor(2)
        idles.furnitureUses[sitter] = FurnitureUse(
            sitState: .sitting, animationType: 1, entry: 0x40000, furniture: Self.actor(9)
        )
        idles.furnitureUses[loader] = FurnitureUse(
            sitState: .loading, animationType: 1, entry: 0x40000, furniture: Self.actor(8)
        )

        idles.leaveFurniture(sitter)
        #expect(idles.furnitureUses[sitter]?.sitState == .readyToStand)
        idles.advanceSitStates(now: IdleCoordinator.standUpSeconds / 2)
        #expect(idles.furnitureUses[sitter]?.sitState == .readyToStand)
        idles.advanceSitStates(now: IdleCoordinator.standUpSeconds)
        #expect(idles.furnitureUses[sitter] == nil)
        #expect(idles.furnitureUses[loader]?.sitState == .loading)
    }
}
