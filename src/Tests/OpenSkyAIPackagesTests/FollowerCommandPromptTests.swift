import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import Testing

struct FollowerCommandPromptTests {
    private let follower = ReferenceKey.plugin(name: "Skyrim.esm", objectID: 0xA2C94)
    private let bandit = ReferenceKey.plugin(name: "Skyrim.esm", objectID: 0x1000)

    @Test func aLivingActorOtherThanTheFollowerReadsAttack() {
        let other = FollowerCommandTarget(key: bandit, kind: .actor, position: .zero)
        let itself = FollowerCommandTarget(key: follower, kind: .actor, position: .zero)
        let corpse = FollowerCommandTarget(key: bandit, kind: .corpse, position: .zero)
        #expect(FollowerCommandPrompt.verb(for: other, follower: follower) == .attack)
        #expect(FollowerCommandPrompt.verb(for: itself, follower: follower) == nil)
        #expect(FollowerCommandPrompt.verb(for: corpse, follower: follower) == nil)
    }

    @Test func onlyAnOpenUnownedContainerReadsTakeAll() {
        var chest = FollowerCommandTarget(key: bandit, kind: .container, position: .zero)
        #expect(FollowerCommandPrompt.verb(for: chest, follower: follower) == .takeAll)
        chest.isOwned = true
        #expect(FollowerCommandPrompt.verb(for: chest, follower: follower) == nil)
    }
}
