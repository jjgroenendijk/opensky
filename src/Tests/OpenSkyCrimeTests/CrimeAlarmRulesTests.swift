// The alarm's pure rules: who hears it, the hostility test, and the decide step.
// See docs/engine/crime-reports.md#the-alarm.

@testable import OpenSkyCrime
@testable import OpenSkyCrimeInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct CrimeAlarmRulesTests {
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let other = CrimeFixture.key(0x7F0)

    private static func crime(faction: ReferenceKey = hold, takenBy: ReferenceKey? = nil)
        -> AlarmCrime
    {
        AlarmCrime(
            kind: .theft, criminal: .player, faction: faction, victim: nil, gold: 25,
            violent: false, stolenItem: nil, stolenCount: 1, takenBy: takenBy
        )
    }

    private static func hearer(
        distance: Float = 100,
        guarding: ReferenceKey? = nil,
        crimeFaction: ReferenceKey? = hold,
        shared: Set<ReferenceKey> = [],
        hostile: Bool = true
    ) -> AlarmHearer {
        AlarmHearer(
            distance: distance, policedFaction: guarding, crimeFaction: crimeFaction,
            sharedCrimeFactions: shared, isHostile: hostile
        )
    }

    @Test func aGuardHearsOnlyACrimeNoGuardHasTaken() {
        let guarding = Self.hearer(guarding: Self.hold)
        #expect(CrimeAlarmRules.hears(guarding, Self.crime()))
        #expect(!CrimeAlarmRules.hears(guarding, Self.crime(takenBy: Self.other)))
        #expect(!CrimeAlarmRules.hears(
            Self.hearer(distance: 4001, guarding: Self.hold),
            Self.crime()
        ))
    }

    @Test func anotherActorNeedsTheCrimeFactionOrAListThatSharesItAndHostility() {
        #expect(CrimeAlarmRules.hears(Self.hearer(), Self.crime()))
        #expect(!CrimeAlarmRules.hears(Self.hearer(hostile: false), Self.crime()))
        #expect(!CrimeAlarmRules.hears(Self.hearer(crimeFaction: nil), Self.crime()))
        let stranger = Self.hearer(crimeFaction: Self.other)
        #expect(!CrimeAlarmRules.hears(stranger, Self.crime()))
        let sharing = Self.hearer(crimeFaction: Self.other, shared: [Self.hold])
        #expect(CrimeAlarmRules.hears(sharing, Self.crime()))
    }

    @Test func onlyTheftPickpocketAndTrespassAreLesserCrimes() {
        #expect(CrimeAlarmRules.isLesser(.theft))
        #expect(CrimeAlarmRules.isLesser(.pickpocket))
        #expect(CrimeAlarmRules.isLesser(.trespass))
        #expect(!CrimeAlarmRules.isLesser(.assault))
        #expect(!CrimeAlarmRules.isLesser(.murder))
    }

    @Test func theRelationshipRankStartsTheReactionAndTheFactionsChangeIt() {
        #expect(CrimeAlarmRules.reaction(relationship: nil, faction: nil) == .neutral)
        #expect(CrimeAlarmRules.reaction(relationship: nil, faction: .enemy) == .enemy)
        #expect(CrimeAlarmRules.reaction(relationship: .ally, faction: .enemy) == .ally)
        #expect(CrimeAlarmRules.reaction(relationship: .enemy, faction: .neutral) == .enemy)
        #expect(CrimeAlarmRules.reaction(relationship: .enemy, faction: .friend) == .friend)
        #expect(CrimeAlarmRules.reaction(relationship: .friend, faction: .ally) == .ally)
        #expect(CrimeAlarmRules.reaction(relationship: .friend, faction: .enemy) == .friend)
    }

    @Test func aggressionDecidesWhichReactionIsHostile() {
        func hostile(
            _ aggression: ActorAggression, _ reaction: ActorReaction,
            angry: Bool = false, targeted: Bool = false
        ) -> Bool {
            CrimeAlarmRules.isHostile(
                aggression: aggression, reaction: reaction, isAngry: angry,
                criminalTargetsWitness: targeted
            )
        }
        #expect(hostile(.frenzied, .ally))
        #expect(hostile(.aggressive, .enemy))
        #expect(!hostile(.aggressive, .neutral))
        #expect(hostile(.veryAggressive, .neutral))
        #expect(!hostile(.veryAggressive, .friend))
        #expect(!hostile(.unaggressive, .enemy))
        #expect(hostile(.unaggressive, .neutral, angry: true))
        #expect(hostile(.unaggressive, .neutral, targeted: true))
        #expect(!hostile(.unaggressive, .friend, targeted: true))
    }

    @Test func theDecideStepTakesTheFirstRoleThatApplies() {
        let fights = AlarmCrimeView(isTaken: false, mayTakeBack: true, fights: true)
        let taken = AlarmCrimeView(isTaken: true, mayTakeBack: false, fights: false)
        let owned = AlarmCrimeView(isTaken: false, mayTakeBack: true, fights: false)
        let foreign = AlarmCrimeView(isTaken: false, mayTakeBack: false, fights: false)
        #expect(CrimeAlarmRules.decide(isGuard: true, crimes: [], theftMark: false).role == .pursue)
        #expect(CrimeAlarmRules.decide(isGuard: false, crimes: [taken, fights], theftMark: false)
            .role == .fight)
        #expect(CrimeAlarmRules.decide(isGuard: false, crimes: [taken], theftMark: false)
            .role == .done)
        #expect(CrimeAlarmRules.decide(isGuard: false, crimes: [foreign], theftMark: true)
            .role == .flee)
        #expect(CrimeAlarmRules.decide(isGuard: false, crimes: [owned], theftMark: false)
            .role == .takeBack)
        let marked = CrimeAlarmRules.decide(isGuard: false, crimes: [owned], theftMark: true)
        #expect(marked.role == .fight)
        #expect(marked.angry)
    }

    @Test func aFleeingCriminalRunsStraightAwayOnTheGround() {
        let point = CrimeAlarmRules.fleePoint(
            criminal: SIMD3(100, 0, 50), from: SIMD3(0, 0, 0), distance: 2000
        )
        #expect(point == SIMD3(2100, 0, 50))
        let same = CrimeAlarmRules.fleePoint(criminal: .zero, from: .zero, distance: 10)
        #expect(same == SIMD3(10, 0, 0))
    }

    @Test func theTheftMarkKeepsItsDayAndATheftOnAnotherDayClearsIt() {
        var mark = TheftMark()
        #expect(!mark.isSet)
        mark.note(day: 3)
        #expect(mark.day == 3)
        mark.note(day: 3)
        #expect(mark.isSet)
        mark.note(day: 4)
        #expect(!mark.isSet)
        mark.note(day: 4)
        #expect(mark.day == 4)
    }
}
