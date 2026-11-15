// A deferred resolution: built on the first read, once, and shared by copies of the
// context, so a live context reads only the state its conditions ask for.

import OpenSkyActorsInterface
@testable import OpenSkyConditions
import OpenSkyFormatsESM
import Testing

@MainActor
struct ConditionDeferredResolutionTests {
    /// Counts builds and holds the value the next build reads.
    private final class Source {
        var isMenuOpen = false
        var builds = 0

        func menus() -> MenuConditionResolution {
            builds += 1
            return MenuConditionResolution(isMenuOpen: isMenuOpen, isLoading: false)
        }
    }

    @Test func aResolutionNobodyReadsIsNeverBuilt() {
        let source = Source()
        var context = ConditionContext()
        context.setDeferred { source.menus() }
        _ = context.weather
        #expect(source.builds == 0)
    }

    @Test func theFirstReadBuildsItAndCopiesShareTheResult() {
        let source = Source()
        var context = ConditionContext()
        context.setDeferred { source.menus() }
        let copy = context
        #expect(context.menus.isMenuOpen == false)
        _ = copy.menus
        _ = context.menus
        #expect(source.builds == 1)
    }

    /// The state is read at the first read, not when the context was made.
    @Test func aChangeBeforeTheFirstReadIsSeen() {
        let source = Source()
        var context = ConditionContext()
        context.setDeferred { source.menus() }
        source.isMenuOpen = true
        #expect(context.menus.isMenuOpen == true)
    }

    @Test func aTransformWaitsForTheFirstReadToo() {
        let source = Source()
        var context = ConditionContext()
        context.setDeferred { source.menus() }
        context.transform(MenuConditionResolution.self) {
            MenuConditionResolution(isMenuOpen: $0.isMenuOpen, isLoading: true)
        }
        #expect(source.builds == 0)
        source.isMenuOpen = true
        #expect(context.menus == MenuConditionResolution(isMenuOpen: true, isLoading: true))
        #expect(source.builds == 1)
    }

    @Test func aTransformChangesAStoredValue() {
        var context = ConditionContext()
        context.menus = MenuConditionResolution(isMenuOpen: true, isLoading: false)
        context.transform(MenuConditionResolution.self) {
            MenuConditionResolution(isMenuOpen: $0.isMenuOpen, isLoading: true)
        }
        #expect(context.menus == MenuConditionResolution(isMenuOpen: true, isLoading: true))
    }

    @Test func aStoredValueReplacesADeferredOne() {
        let source = Source()
        var context = ConditionContext()
        context.setDeferred { source.menus() }
        context.menus = MenuConditionResolution(isMenuOpen: true, isLoading: true)
        #expect(context.menus.isLoading == true)
        #expect(source.builds == 0)
    }

    @Test func anOverlayCarriesADeferredResolution() {
        let source = Source()
        source.isMenuOpen = true
        var overlay = ConditionContext()
        overlay.setDeferred { source.menus() }
        var base = ConditionContext()
        base.menus = MenuConditionResolution(isMenuOpen: false, isLoading: false)
        #expect(base.overlaid(by: overlay).menus.isMenuOpen == true)
    }

    @Test func deferredActorsAlsoServeTheCombatTargetRunOn() {
        let source = Source()
        var context = ConditionContext()
        context.setDeferredActors {
            source.builds += 1
            return .empty
        }
        #expect(context.combatTargetResolver != nil)
        #expect(source.builds == 0)
        _ = context.combatTargetResolver?.combatTarget(of: .player)
        _ = context.actors
        #expect(source.builds == 1)
    }

    @Test func dataIsAResolutionLikeTheOthers() {
        var context = ConditionContext()
        #expect(context.data.sourcePlugin == nil)
        context.data = context.data.with(sourcePlugin: "Test.esm")
        #expect(context.data.sourcePlugin == "Test.esm")
    }
}
