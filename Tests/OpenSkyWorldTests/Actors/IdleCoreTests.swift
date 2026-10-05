// The idle runtime's pure rules: which actors use markers, which marker they
// take, how long an idle plays, and the readout wording.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct IdleCoreTests {
    private static func marker(_ objectID: UInt32, at position: SIMD3<Float>, flags: UInt8 = 0)
        throws -> IdleMarkerPlacement
    {
        let record = try IdleMarker(record: ESMFixture.record("IDLM", formID: objectID, fields: [
            ("EDID", ESMFixture.zstring("Marker\(objectID)")), ("IDLF", ESMFixture.u8(flags))
        ]))
        return IdleMarkerPlacement(
            reference: .plugin(name: "test.esm", objectID: objectID),
            marker: ResolvedRecord(
                id: ResolvedFormID(plugin: "Test.esm", objectID: objectID),
                record: record, sourcePlugin: "Test.esm"
            ),
            position: position
        )
    }

    @Test func sandboxAndTheIdleMarkerProcedureUseMarkers() {
        #expect(IdleCore.usesMarkers(.sandbox))
        #expect(IdleCore.usesMarkers(.unsupported("UseIdleMarker")))
        #expect(!IdleCore.usesMarkers(.travel))
        #expect(!IdleCore.usesMarkers(nil))
    }

    @Test func anActorTakesTheNearestFreeMarkerInReach() throws {
        let near = try Self.marker(1, at: SIMD3(100, 0, 0))
        let nearer = try Self.marker(2, at: SIMD3(50, 0, 0))
        let far = try Self.marker(3, at: SIMD3(5000, 0, 0))
        let markers = [near, nearer, far]
        #expect(IdleCore.nearestFreeMarker(to: .zero, among: markers, claimed: [])?
            .reference == nearer.reference)
        #expect(IdleCore.nearestFreeMarker(
            to: .zero, among: markers, claimed: [nearer.reference]
        )?.reference == near.reference)
        #expect(IdleCore.nearestFreeMarker(
            to: .zero, among: markers, claimed: [nearer.reference], excluded: [near.reference]
        ) == nil)
    }

    @Test func markerFlagsSetTheOrderAndDoOnce() throws {
        let plain = try Self.marker(1, at: .zero)
        let flagged = try Self.marker(2, at: .zero, flags: 0x05)
        #expect(IdleCore.selectionOrder(of: plain.marker.record) == .random)
        #expect(IdleCore.selectionOrder(of: flagged.marker.record) == .sequence)
        #expect(!IdleCore.isDoOnce(plain.marker.record))
        #expect(IdleCore.isDoOnce(flagged.marker.record))
    }

    @Test func playLengthLoopsTheClipBetweenTheDataBounds() throws {
        let idle = try IdleAnimation(record: ESMFixture.record("IDLE", fields: [
            ("DATA", ESMFixture.u8(2, 4, 0, 0) + ESMFixture.u16(0))
        ]))
        let seconds = IdleCore.playSeconds(
            clipDuration: 1.5, properties: idle.properties, random: { $0 - 1 }
        )
        #expect(seconds == 6)
        #expect(IdleCore.playSeconds(clipDuration: 1.5, properties: nil, random: { _ in 0 }) == 1.5)
        #expect(IdleCore.nextSelection(after: 10, playSeconds: 6, timer: 20) == 30)
        #expect(IdleCore.nextSelection(after: 10, playSeconds: 6, timer: nil) == 16)
    }

    @Test func clipPathsFoldParentSegmentsAndFollowTheProject() {
        #expect(IdlePlaybackResolver.normalized(
            "meshes\\actors\\character\\..\\SharedKillMoves\\A.hkx"
        ) == "meshes\\actors\\sharedkillmoves\\a.hkx")
        #expect(IdlePlaybackResolver.projectFolder(
            of: "Actors\\Character\\Behaviors\\0_Master.hkx"
        ) == "meshes\\actors\\character\\")
        #expect(IdlePlaybackResolver.behaviorPath(
            "Behaviors\\MT_Behavior.hkx", project: "meshes\\actors\\wolf\\"
        ) == "meshes\\actors\\wolf\\behaviors\\mt_behavior.hkx")
        #expect(IdlePlaybackResolver.behaviorPath("notes.txt", project: "") == nil)
    }

    @Test func aPropBoneWithoutItsTagFindsTheTaggedSkeletonBone() {
        let bones = ["NPC Root [Root]", "NPC R Hand [RHnd]", "AnimObjectR"]
        #expect(IdlePlaybackResolver.skeletonBone("NPC R Hand", in: bones) == "NPC R Hand [RHnd]")
        #expect(IdlePlaybackResolver.skeletonBone("AnimObjectR", in: bones) == "AnimObjectR")
        #expect(IdlePlaybackResolver.skeletonBone("Tail", in: bones) == "Tail")
    }

    @Test func theReadoutNamesTheVerdictsAndThePath() {
        #expect(IdleReadout.verdictText(.rejected("GetIsID")) == "failed GetIsID")
        #expect(IdleReadout.pathText(.graphEvent(behaviorFiles: ["a", "MT_Behavior.hkx"]))
            == "graph event (MT_Behavior.hkx)")
        #expect(IdleReadout.propText(.attached(
            editorID: "AnimObjectLute", modelPath: "lute.nif", bone: "AnimObjectR"
        )) == "AnimObjectLute on AnimObjectR")
        #expect(IdleReadout.markersText(for: .unavailable) == "Idle markers: unavailable")
    }
}
