// The ordered help checks over plain facts: owners, followers, the Morality filter with
// its hostility exception, crimes, and the Assistance step.
// See docs/engine/combat.md#who-an-assisting-actor-fights.

@testable import OpenSkyCombat
@testable import OpenSkyFormatsESM
import Testing

@MainActor
private struct Facts: CombatHelpFacts {
    var player = ReferenceKey.player
    var owners: [ReferenceKey: ReferenceKey] = [:]
    var teammates: Set<ReferenceKey> = []
    var moralities: [ReferenceKey: Float] = [:]
    var aggressors: Set<ReferenceKey> = []
    /// Helper, then the actor it counts a criminal.
    var criminals: Set<[ReferenceKey]> = []
    var opponents: [ReferenceKey: [ReferenceKey]] = [:]
    /// Helper, then the actor it fights or hates.
    var opposed: Set<[ReferenceKey]> = []
    var crimeAttackers: Set<ReferenceKey> = []
    /// Helper, then the ally its Assistance and reaction help.
    var assists: Set<[ReferenceKey]> = []

    func owner(of key: ReferenceKey) -> ReferenceKey? {
        owners[key]
    }

    func isTeammate(_ key: ReferenceKey) -> Bool {
        teammates.contains(key)
    }

    func morality(of key: ReferenceKey) -> Float {
        moralities[key] ?? 0
    }

    func startedFight(_ key: ReferenceKey) -> Bool {
        aggressors.contains(key)
    }

    func committedCrime(_ key: ReferenceKey, judgedBy helper: ReferenceKey) -> Bool {
        criminals.contains([helper, key])
    }

    func opponents(of key: ReferenceKey) -> [ReferenceKey] {
        opponents[key] ?? []
    }

    func opposes(_ helper: ReferenceKey, _ opponent: ReferenceKey) -> Bool {
        opposed.contains([helper, opponent])
    }

    func attacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool {
        crimeAttackers.contains(key)
    }

    func assistsByTemperament(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool {
        assists.contains([helper, ally])
    }
}

@MainActor
struct CombatHelpRuleTests {
    private static let helper = ReferenceKey.generated(1)
    private static let ally = ReferenceKey.generated(2)
    private static let foe = ReferenceKey.generated(3)
    private static let summon = ReferenceKey.generated(4)

    private func helps(
        _ facts: Facts,
        _ helper: ReferenceKey = helper,
        _ ally: ReferenceKey? = ally
    )
        -> Bool
    {
        CombatHelpRule.helps(helper, ally, facts: facts)
    }

    @Test func noAllyGetsNoHelpAndAnActorHelpsItself() {
        #expect(!helps(Facts(), Self.helper, nil))
        #expect(helps(Facts(), Self.helper, Self.helper))
    }

    @Test func theAssistanceStepDecidesWhenNoOtherRuleApplies() {
        #expect(!helps(Facts()))
        #expect(helps(Facts(assists: [[Self.helper, Self.ally]])))
    }

    @Test func aCommandedAllyIsJudgedThroughItsOwner() {
        let facts = Facts(owners: [Self.summon: Self.ally], assists: [[Self.helper, Self.ally]])
        #expect(helps(facts, Self.helper, Self.summon))
    }

    @Test func aCommandedHelperIsJudgedThroughItsOwner() {
        let facts = Facts(owners: [Self.summon: Self.helper], assists: [[Self.helper, Self.ally]])
        #expect(helps(facts, Self.summon, Self.ally))
    }

    @Test func aLoopOfOwnersEndsWithNoHelp() {
        let facts = Facts(owners: [Self.summon: Self.ally, Self.ally: Self.summon])
        #expect(!helps(facts, Self.helper, Self.summon))
    }

    @Test func aHelperWithAMoralityRefusesTheActorThatStartedTheFight() {
        var facts = Facts(
            moralities: [Self.helper: 1], aggressors: [Self.ally],
            opponents: [Self.ally: [Self.foe]], assists: [[Self.helper, Self.ally]]
        )
        #expect(!helps(facts))
        facts.opposed = [[Self.helper, Self.foe]]
        #expect(helps(facts))
        facts.moralities = [:]
        facts.opposed = []
        #expect(helps(facts))
    }

    @Test func aCrimeIsRefusedEvenWhenTheHelperOpposesTheFoe() {
        let facts = Facts(
            moralities: [Self.helper: 3], criminals: [[Self.helper, Self.ally]],
            opponents: [Self.ally: [Self.foe]], opposed: [[Self.helper, Self.foe]],
            assists: [[Self.helper, Self.ally]]
        )
        #expect(!helps(facts))
    }

    @Test func aRefusedFollowerIsHelpedWhenTheHelperHelpsThePlayer() {
        var facts = Facts(
            teammates: [Self.ally], moralities: [Self.helper: 2], aggressors: [Self.ally],
            assists: [[Self.helper, .player]]
        )
        #expect(helps(facts))
        facts.assists = []
        #expect(!helps(facts))
    }

    @Test func aFollowerAllyCountsAsThePlayer() {
        let facts = Facts(teammates: [Self.ally], assists: [[Self.helper, .player]])
        #expect(helps(facts))
    }

    @Test func aFollowerHelpsThePlayerUnlessItAttacksThePlayerForCrimes() {
        var facts = Facts(teammates: [Self.helper])
        #expect(helps(facts, Self.helper, .player))
        facts.crimeAttackers = [Self.helper]
        #expect(!helps(facts, Self.helper, .player))
    }

    @Test func aFollowerHelpsWhomThePlayerHelpsUnlessItFightsThePlayerSide() {
        var facts = Facts(teammates: [Self.helper], assists: [[.player, Self.ally]])
        #expect(helps(facts))
        facts.opponents = [Self.ally: [.player]]
        #expect(!helps(facts))
        facts.opponents = [Self.ally: [Self.helper]]
        #expect(!helps(facts))
        facts.opponents = [Self.ally: [Self.foe]]
        #expect(helps(facts))
    }
}
