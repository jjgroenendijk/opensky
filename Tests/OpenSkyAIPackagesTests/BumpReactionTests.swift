// A bumped NPC speaks, waits, steps away from the player, then holds before its
// package resumes (docs/engine/bump-reactions.md).

@testable import OpenSkyAIPackages
import OpenSkyFormatsESM
import simd
import Testing

struct BumpReactionTests {
    private let farmer = ReferenceKey.plugin(name: "test.esm", objectID: 0x100)

    private func contact() -> BumpContact {
        BumpContact(actor: farmer, actorFeet: SIMD3(100, 0, 0), playerFeet: SIMD3(60, 0, 0))
    }

    @Test func aBumpSpeaksThenStepsAwayThenEnds() {
        var bumps = BumpReactions()
        let settings = BumpReactionSettings.vanilla
        #expect(bumps.note([contact()], now: 0, settings: settings) == [.speak(farmer)])
        #expect(bumps.note([contact()], now: 0.5, settings: settings).isEmpty)
        #expect(bumps.advance(now: 0.9, settings: settings).commands.isEmpty)
        let moved = bumps.advance(now: 1, settings: settings)
        #expect(moved.commands == [.move(farmer, to: SIMD3(225, 0, 0))])
        #expect(bumps.advance(now: 3.9, settings: settings).finished.isEmpty)
        #expect(bumps.advance(now: 4, settings: settings).finished == [farmer])
        #expect(bumps.reactingActors.isEmpty)
        #expect(bumps.reactionCount == 1)
    }

    @Test func theMoveIsNeverShorterThanTheMinimum() {
        var settings = BumpReactionSettings.vanilla
        settings.idealMoveDistance = 20
        #expect(settings.moveDistance == 75)
        settings.minMoveDistance = .nan
        settings.idealMoveDistance = -5
        #expect(settings.moveDistance == 0)
    }

    @Test func aPlayerOnTheActorStillGivesADirection() {
        let still = BumpContact(actor: farmer, actorFeet: .zero, playerFeet: .zero)
        #expect(BumpReactions.goal(of: still, distance: 10) == SIMD3(10, 0, 0))
    }

    @Test func cancelDropsTheReaction() {
        var bumps = BumpReactions()
        _ = bumps.note([contact()], now: 0, settings: .vanilla)
        bumps.cancel(farmer)
        let after = bumps.advance(now: 2, settings: .vanilla)
        #expect(after.commands.isEmpty && after.finished.isEmpty)
    }
}

struct FollowSettingsTests {
    @Test func aGoalNearAFellowFollowerMovesToTheSpacing() {
        let goal = FollowSettings.spacedGoal(
            SIMD3(50, 0, 10), fellows: [SIMD3(0, 0, 0)], spacing: 192
        )
        #expect(goal == SIMD3(192, 0, 10))
        let far = SIMD3<Float>(500, 0, 0)
        #expect(FollowSettings.spacedGoal(far, fellows: [.zero], spacing: 192) == far)
        #expect(FollowSettings.spacedGoal(far, fellows: [far], spacing: 0) == far)
    }

    @Test func aRunningFollowerSlowsNearItsGoalDownToTheFloor() {
        let settings = FollowSettings.vanilla
        #expect(settings.runSpeedScale(remaining: 400, slowingDistance: 200) == 1)
        #expect(settings.runSpeedScale(remaining: 160, slowingDistance: 200) == 0.8)
        #expect(settings.runSpeedScale(remaining: 10, slowingDistance: 200) == 0.75)
        #expect(settings.runSpeedScale(remaining: 10, slowingDistance: 0) == 1)
    }
}
