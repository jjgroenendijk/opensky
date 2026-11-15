// An actor's sound types through its audio template, the chance pick, and which loops
// play near the listener. See docs/engine/actor-sounds.md.

import OpenSkyAudio
import OpenSkyFormatsESM
import Testing

struct ActorSoundsTests {
    private static let breath = FormID(0x500)
    private static let gears = FormID(0x501)
    private static let template = FormID(0x20)

    private static let records: [FormID: ActorSoundRecord] = [
        FormID(0x10): ActorSoundRecord(inheritsFrom: template, types: [
            ActorSoundType(type: 0, entries: [.init(sound: FormID(0x999))])
        ]),
        template: ActorSoundRecord(inheritsFrom: nil, types: [
            ActorSoundType(type: 7, entries: [.init(sound: breath, chance: 100)]),
            ActorSoundType(
                type: 6,
                entries: [.init(sound: gears), .init(sound: FormID(0x9), chance: 0)]
            )
        ]),
        FormID(0x30): ActorSoundRecord(inheritsFrom: FormID(0x31), types: []),
        FormID(0x31): ActorSoundRecord(inheritsFrom: FormID(0x30), types: []),
        FormID(0x40): ActorSoundRecord(inheritsFrom: FormID(0x10), types: [])
    ]

    private static func sounds(_ id: UInt32) -> ActorSounds {
        ActorSounds.of(FormID(id)) { records[$0] }
    }

    @Test func theAudioTemplateReplacesTheOwnList() {
        let sounds = Self.sounds(0x10)
        #expect(sounds.sounds(.idle).isEmpty)
        #expect(sounds.sounds(.consciousLoop) == [Self.breath])
    }

    @Test func aChanceOfZeroNeverPlays() {
        #expect(Self.sounds(0x20).sounds(.movementLoop) == [Self.gears])
    }

    @Test func onlyOneStepOfInheritanceCounts() {
        #expect(Self.sounds(0x30) == .none)
        #expect(Self.sounds(0x40) == .none)
    }

    @Test func onlyTheConsciousLoopPlaysOnItsOwn() {
        let sounds = Self.sounds(0x10)
        #expect(sounds.loops(isConscious: true) == [Self.breath])
        #expect(sounds.loops(isConscious: false).isEmpty)
    }

    @Test func thePickTriesTheLowestChanceFirst() {
        let sounds = ActorSounds(types: [
            ActorSoundType(type: 0, entries: [
                .init(sound: FormID(0xB), chance: 100), .init(sound: FormID(0xA), chance: 30)
            ])
        ])
        var rolls = [12]
        #expect(sounds.pick(.idle) { rolls.removeFirst() } == FormID(0xA))
        rolls = [64, 99]
        #expect(sounds.pick(.idle) { rolls.removeFirst() } == FormID(0xB))
        #expect(rolls.isEmpty)
    }

    @Test func thePickPlaysNothingWhenNoRollPasses() {
        let sounds = ActorSounds(types: [
            ActorSoundType(type: 3, entries: [.init(sound: FormID(0xA), chance: 50)])
        ])
        #expect(sounds.pick(.hit) { 50 } == nil)
        #expect(sounds.pick(.idle) { 0 } == nil)
    }

    @Test func thePlanKeepsTheNearestActorsInReach() {
        let sounds = Self.sounds(0x20)
        let sources = (0 ..< ActorLoopPlan.actorLimit + 2).map { index in
            ActorSoundSource(
                key: .generated(UInt64(index + 1)),
                position: SIMD3(Float(index) * 100, 0, 0),
                sounds: sounds, isConscious: true
            )
        }
        let far = ActorSoundSource(
            key: .generated(99), position: SIMD3(ActorLoopPlan.reach + 1, 0, 0),
            sounds: sounds, isConscious: true
        )
        let wanted = ActorLoopPlan.wanted(sources + [far], listener: .zero)
        #expect(wanted.count == ActorLoopPlan.actorLimit)
        #expect(wanted[ActorLoop(actor: .generated(1), sound: Self.breath)] == .zero)
        #expect(wanted[ActorLoop(
            actor: .generated(UInt64(ActorLoopPlan.actorLimit + 1)),
            sound: Self.breath
        )] == nil)
    }
}
