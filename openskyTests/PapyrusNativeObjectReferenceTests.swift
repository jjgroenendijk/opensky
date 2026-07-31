// Enable, delete and position natives of the `ObjectReference` family (issue
// #172): every write lands in `WorldStateStore` and every read comes back out
// of it. Activation and linked references are in
// `PapyrusNativeObjectReferenceLinkTests`.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeObjectReferenceTests {
    @Test func disableAndEnableWriteEnableStateAndIsEnabledReadsItBack() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        #expect(fixture.call("IsEnabled", returnType: .boolean) == .returned(.boolean(true)))

        #expect(fixture.call("Disable") == .returned(.none))
        #expect(fixture.session.worldState.component(
            ReferenceEnableState.self, for: fixture.key
        ) == .disabled)
        #expect(fixture.call("IsEnabled", returnType: .boolean) == .returned(.boolean(false)))
        // The write carried the reference's resident cell, so the rebuild
        // fan-out is that one cell rather than every resident one.
        #expect(fixture.session.worldState.dirtyCount(in: PapyrusWorldFixture.cell) == 1)
        #expect(fixture.session.worldState.unattributedDirtyCount == 0)

        #expect(fixture.call("Enable") == .returned(.none))
        #expect(fixture.call("IsEnabled", returnType: .boolean) == .returned(.boolean(true)))
    }

    /// `Enable(abFadeIn)` and `Disable(abFadeOut)` take the fade flag and
    /// ignore it: M11 has no fade, and the state written is the same either
    /// way.
    @Test func enableAndDisableAcceptAndIgnoreTheFadeArgument() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        #expect(fixture.call("Disable", arguments: [.boolean(true)]) == .returned(.none))
        #expect(fixture.session.worldState.component(
            ReferenceEnableState.self, for: fixture.key
        ) == .disabled)
    }

    @Test func deleteWritesRuntimeDeletionState() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        #expect(fixture.call("Delete") == .returned(.none))
        #expect(fixture.session.worldState.component(
            ReferenceDeletionState.self, for: fixture.key
        ) == .deleted)
        // Runtime deletion is what drops a reference from the drawn set.
        let state = try #require(fixture.session.bridge.referenceState(for: fixture.key))
        #expect(!state.isVisible)
    }

    @Test func positionGettersReadTheResolvedState() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        #expect(fixture.call("GetPositionX", returnType: .float) == .returned(.float(1)))
        #expect(fixture.call("GetPositionY", returnType: .float) == .returned(.float(2)))
        #expect(fixture.call("GetPositionZ", returnType: .float) == .returned(.float(3)))
    }

    @Test func setPositionPreservesRotationScaleAndUnsetAxes() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        fixture.session.worldState.set(
            ReferenceTransformOverride(
                position: SIMD3<Float>(1, 2, 3),
                rotation: SIMD3<Float>(0.25, 0.5, 0.75),
                scale: 2
            ),
            for: fixture.key,
            in: PapyrusWorldFixture.cell
        )

        #expect(fixture.call("SetPosition", arguments: [.float(10)]) == .returned(.none))
        var written = try #require(fixture.session.worldState.component(
            ReferenceTransformOverride.self, for: fixture.key
        ))
        #expect(written.position == SIMD3<Float>(10, 2, 3))
        #expect(written.rotation == SIMD3<Float>(0.25, 0.5, 0.75))
        #expect(written.scale == 2)

        #expect(fixture.call(
            "SetPosition", arguments: [.float(4), .integer(5), .float(6)]
        ) == .returned(.none))
        written = try #require(fixture.session.worldState.component(
            ReferenceTransformOverride.self, for: fixture.key
        ))
        #expect(written.position == SIMD3<Float>(4, 5, 6))
        #expect(written.rotation == SIMD3<Float>(0.25, 0.5, 0.75))
        #expect(written.scale == 2)
        #expect(fixture.call("GetPositionZ", returnType: .float) == .returned(.float(6)))
    }

    @Test func setPositionRejectsMalformedCoordinates() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        #expect(PapyrusWorldFixture.isInvalidArguments(
            fixture.call("SetPosition", arguments: [.string("here")])
        ))
        #expect(PapyrusWorldFixture.isInvalidArguments(
            fixture.call("SetPosition", arguments: [.float(.nan)])
        ))
        #expect(PapyrusWorldFixture.isInvalidArguments(fixture.call("SetPosition")))
        #expect(fixture.session.worldState.component(
            ReferenceTransformOverride.self, for: fixture.key
        ) == nil)
    }

    /// A call with no receiver at all — a static-shaped call on a family that
    /// has none — fails rather than writing under a guessed key.
    @Test func worldCallWithoutAReceiverFails() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let result = fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "ObjectReference", "Disable", receiver: nil
        ))
        #expect(PapyrusWorldFixture.isInvalidArguments(result))
        #expect(fixture.session.worldState.dirtyCount == 0)
    }
}
