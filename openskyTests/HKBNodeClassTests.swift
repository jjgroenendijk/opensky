// Per-class decode tests for every behavior node class in the registry
// (todo 14.2), over synthetic in-code packfiles — never an extracted game file
// (AGENTS.md "Legal & IP boundary").
//
// Three cases per class, driven from one table so a new decoder cannot land
// without them:
//
// - nominal: a zero-filled object of the class's declared Havok size decodes,
//   and every miss it records is `noFixup`, which is what a null optional
//   legitimately produces. An `outOfBounds` here would mean the decoder reads
//   past the class.
// - truncated: the object's section ends 16 bytes in, so every member is out of
//   bounds. Decoding must still return a value and record the misses rather
//   than trap.
// - unresolvable pointer: the member at 0x10 — a pointer, a string, or an
//   hkArray on every class in the set — is patched to a section the file does
//   not define. The decoder must record `sectionMissing` and carry on.
//
// The declared sizes double as the byte-map assertion: they are the sizes the
// class layouts in docs/formats/hkx-behavior-nodes.md record, so a table entry
// that disagreed with a decoder's highest offset would fail the nominal case.

import Foundation
@testable import opensky
import Testing

/// One registry class and the Havok size of its instances.
struct HKBClassCase: CustomStringConvertible, Sendable {
    let name: String
    let size: Int

    var description: String {
        name
    }
}

struct HKBNodeClassTests {
    /// Every class the registry decodes, with its declared Havok instance size.
    /// Order matches HKBClassRegistry's table.
    static let classes: [HKBClassCase] = [
        HKBClassCase(name: "hkbVariableBindingSet", size: 40),
        HKBClassCase(name: "hkbBoneWeightArray", size: 64),
        HKBClassCase(name: "hkbBoneIndexArray", size: 64),
        HKBClassCase(name: "hkbStringEventPayload", size: 24),
        HKBClassCase(name: "hkbStateMachine", size: 264),
        HKBClassCase(name: "hkbStateMachineStateInfo", size: 120),
        HKBClassCase(name: "hkbStateMachineTransitionInfoArray", size: 32),
        HKBClassCase(name: "hkbStateMachineEventPropertyArray", size: 32),
        HKBClassCase(name: "hkbClipGenerator", size: 272),
        HKBClassCase(name: "hkbClipTriggerArray", size: 32),
        HKBClassCase(name: "hkbBlenderGenerator", size: 160),
        HKBClassCase(name: "hkbBlenderGeneratorChild", size: 80),
        HKBClassCase(name: "hkbPoseMatchingGenerator", size: 240),
        HKBClassCase(name: "hkbManualSelectorGenerator", size: 96),
        HKBClassCase(name: "hkbModifierGenerator", size: 88),
        HKBClassCase(name: "hkbBehaviorReferenceGenerator", size: 88),
        HKBClassCase(name: "hkbBlendingTransitionEffect", size: 144),
        HKBClassCase(name: "hkbExpressionCondition", size: 32),
        HKBClassCase(name: "hkbStringCondition", size: 24),
        HKBClassCase(name: "hkbExpressionDataArray", size: 32),
        HKBClassCase(name: "hkbEventRangeDataArray", size: 32),
        HKBClassCase(name: "hkbModifierList", size: 96),
        HKBClassCase(name: "hkbEventDrivenModifier", size: 104),
        HKBClassCase(name: "hkbEvaluateExpressionModifier", size: 112),
        HKBClassCase(name: "hkbEventsFromRangeModifier", size: 112),
        HKBClassCase(name: "hkbTimerModifier", size: 112),
        HKBClassCase(name: "hkbDampingModifier", size: 192),
        HKBClassCase(name: "hkbTwistModifier", size: 144),
        HKBClassCase(name: "hkbRotateCharacterModifier", size: 128),
        HKBClassCase(name: "hkbKeyframeBonesModifier", size: 104),
        HKBClassCase(name: "hkbGetUpModifier", size: 128),
        HKBClassCase(name: "hkbFootIkControlsModifier", size: 176),
        HKBClassCase(name: "hkbPoweredRagdollControlsModifier", size: 144),
        HKBClassCase(name: "hkbRigidBodyRagdollControlsModifier", size: 160),
        HKBClassCase(name: "BSSynchronizedClipGenerator", size: 304),
        HKBClassCase(name: "BSiStateTaggingGenerator", size: 96),
        HKBClassCase(name: "BSBoneSwitchGenerator", size: 112),
        HKBClassCase(name: "BSBoneSwitchGeneratorBoneData", size: 64),
        HKBClassCase(name: "BSCyclicBlendTransitionGenerator", size: 176),
        HKBClassCase(name: "BSOffsetAnimationGenerator", size: 176),
        HKBClassCase(name: "BSIsActiveModifier", size: 96),
        HKBClassCase(name: "BSEventEveryNEventsModifier", size: 128),
        HKBClassCase(name: "BSEventOnDeactivateModifier", size: 96),
        HKBClassCase(name: "BSEventOnFalseToTrueModifier", size: 160),
        HKBClassCase(name: "BSInterpValueModifier", size: 104),
        HKBClassCase(name: "BSModifyOnceModifier", size: 112),
        HKBClassCase(name: "BSSpeedSamplerModifier", size: 96),
        HKBClassCase(name: "BSRagdollContactListenerModifier", size: 136),
        HKBClassCase(name: "BSDirectAtModifier", size: 224),
        HKBClassCase(name: "BSLookAtModifier", size: 224)
    ]

    /// Bytes left in the section for the truncated case; every class in the set
    /// declares its first serialized member at 0x10 or later, so 16 bytes puts
    /// all of them out of bounds while still leaving the object addressable.
    private static let truncatedPayloadSize = 16

    /// The table and the registry describe the same set, so neither can grow
    /// without the other.
    @Test
    func tableMatchesTheRegistry() {
        let tabled = Set(Self.classes.map(\.name))
        let registered = Set(HKBClassRegistry.decoders.keys)
        let difference = "table minus registry: \(tabled.subtracting(registered)); "
            + "registry minus table: \(registered.subtracting(tabled))"
        #expect(tabled == registered, "\(difference)")
    }

    @Test(arguments: HKBNodeClassTests.classes)
    func decodesAZeroFilledObject(_ entry: HKBClassCase) throws {
        var fixture = HKBNodeFixture(payloadSize: entry.size)
        let target = fixture.addObject(entry.name, at: 0)
        let graph = try fixture.buildGraph()
        let decoder = try #require(HKBClassRegistry.decoder(for: entry.name))
        let object = try #require(decoder(target, graph), "\(entry.name) did not decode")

        #expect(object.className == entry.name)
        let misreads = object.unresolved.filter { $0.miss != .noFixup }
        let detail = "\(entry.name) read past its \(entry.size) bytes: "
            + "\(misreads.map { "\($0.field) \($0.miss.rawValue)" })"
        #expect(misreads.isEmpty, "\(detail)")
        // A zero-filled object has no pointers patched, so nothing is reachable
        // from it; the summary must still be produced rather than trap.
        #expect(object.references.isEmpty)
        #expect(!object.summary.isEmpty)
    }

    @Test(arguments: HKBNodeClassTests.classes)
    func toleratesATruncatedObject(_ entry: HKBClassCase) throws {
        var fixture = HKBNodeFixture(payloadSize: entry.size)
        let target = fixture.addObject(entry.name, at: 0)
        fixture.truncatePayload(to: Self.truncatedPayloadSize)
        let graph = try fixture.buildGraph()
        let decoder = try #require(HKBClassRegistry.decoder(for: entry.name))
        let object = try #require(
            decoder(target, graph), "\(entry.name) lost its object entirely"
        )

        let outOfBounds = object.unresolved.filter { $0.miss == .outOfBounds }
        let detail = "\(entry.name) reported no out-of-bounds member despite only "
            + "\(Self.truncatedPayloadSize) bytes of object data"
        #expect(!outOfBounds.isEmpty, "\(detail)")
    }

    @Test(arguments: HKBNodeClassTests.classes)
    func recordsAnUnresolvablePointer(_ entry: HKBClassCase) throws {
        // 0x20 covers the smallest classes so the array-size word at 0x18 fits.
        var fixture = HKBNodeFixture(payloadSize: max(entry.size, 0x20))
        let target = fixture.addObject(entry.name, at: 0)
        // Every class in the set holds a pointer, an hkStringPtr, or an hkArray
        // at 0x10. A non-empty count makes the array cases follow the pointer;
        // for the pointer and string cases 0x18 is ignored padding.
        fixture.setInt32(1, at: 0x18)
        fixture.setDanglingPointer(at: 0x10)
        let graph = try fixture.buildGraph()
        let decoder = try #require(HKBClassRegistry.decoder(for: entry.name))
        let object = try #require(decoder(target, graph))

        let detail = "\(entry.name) did not report the dangling pointer at 0x10: "
            + "\(object.unresolved.map { "\($0.field) \($0.miss.rawValue)" })"
        #expect(object.unresolved.contains { $0.miss == .sectionMissing }, "\(detail)")
    }
}
