// A script visibly changes the world, end to end. A lever's real `OnActivate`
// bytecode calls `GetLinkedRef()` and `Disable()` on a door. Chain: raycast and
// use key -> Papyrus -> `OnActivate` -> `ReferenceEnableState` -> rebuild, where
// `runtimeDisabledSkipCount` shows the door left. Only the rebuild needs a GPU.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct ScriptedWorldAcceptanceTests {
    // MARK: - The chain, minus the rebuild

    /// Steps one through four of the gate. Nothing here needs a Metal device,
    /// so this half of the evidence stands on a device-less runner.
    @Test("a lever's script disables its linked door through the whole chain")
    func scriptedActivationDisablesTheLinkedReference() throws {
        let chain = try ScriptedWorldChain()

        // The script really ran: no fault, no unimplemented native, no failed
        // native. `GetLinkedRef` and `Disable` were resolved through the
        // `ObjectReference` base script and dispatched as real native calls.
        let tally = chain.session.world.runtime.tally
        #expect(tally.faultTotal == 0)
        #expect(tally.unimplementedNativeTotal == 0)
        #expect(tally.nativeFailureTotal == 0)
        #expect(tally.nativeCallTotal == 3) // Probe.Seen, GetLinkedRef, Disable

        // Step three: `akActionRef` reached script code as the player.
        guard case let .object(activator) = chain.recorder.seen.first else {
            Issue.record("akActionRef did not reach script code as an object")
            return
        }
        #expect(chain.recorder.seen.count == 1)
        #expect(chain.session.world.referenceKey(for: activator) == ReferenceKey.player)

        // Step four: the world-state delta, on both references.
        let activation = try #require(chain.session.worldState.component(
            ReferenceActivationState.self, for: ScriptedWorldChain.leverKey
        ))
        #expect(activation.activationCount == 1)
        #expect(activation.lastActivator == ReferenceKey.player)
        // The lever is an `activate` interaction, not a door, so nothing opened.
        #expect(activation.isOpen == false)
        #expect(chain.session.worldState.component(
            ReferenceEnableState.self, for: ScriptedWorldChain.doorKey
        ) == ReferenceEnableState(isEnabled: false))
    }

    @Test("both writes are attributed to the cell the streamer resolved")
    func bothWritesAreAttributedToTheCell() throws {
        let chain = try ScriptedWorldChain()
        let state = chain.session.worldState

        // The streamer, not the fixture, answered where each reference lives,
        // so the rebuild fan-out stays narrowed to this one cell.
        #expect(state.dirtyCount == 2)
        #expect(state.dirtyCount(in: ScriptedWorldChain.cell) == 2)
        #expect(state.unattributedDirtyCount == 0)
        #expect(state.sortedDirtyKeys(in: ScriptedWorldChain.cell) == [
            ScriptedWorldChain.doorKey, ScriptedWorldChain.leverKey
        ])
        // Activation first, then the script's own write, both cell-tagged.
        let journal = state.journalEntries
        #expect(journal.map(\.kind) == [.activation, .enableState])
        #expect(journal.allSatisfy { $0.cell == ScriptedWorldChain.cell })
        #expect(journal.last?.key == ScriptedWorldChain.doorKey)
    }

    // MARK: - The rebuild

    /// Step five: the same delta run back through the real `CellSceneBuilder`.
    /// Gated on a Metal device because a cell build uploads meshes; the
    /// assertions above carry the gate when no device is present.
    @Test(.enabled(if: CellSceneFixture.hasDevice))
    func theDisabledDoorLeavesTheDrawnSet() throws {
        let cells = try CellSceneFixture()
        try cells.writeLooseFile("meshes/arch/solid.nif", cells.collisionRenderNIF())
        let pluginData = ScriptedWorldChain.rebuildPlugin(cells)

        // Authored, with no script having run: both references draw.
        let authored = try cells.build(pluginData: pluginData, gridX: 0, gridY: 0)
        #expect(authored.location == ScriptedWorldChain.cell)
        #expect(authored.summary.totalRefCount == 2)
        #expect(authored.summary.drawnRefCount == 2)
        #expect(authored.summary.runtimeDisabledSkipCount == 0)

        let chain = try ScriptedWorldChain()
        let rebuilt = try cells.build(
            pluginData: pluginData,
            gridX: 0,
            gridY: 0,
            state: chain.session.worldState.snapshot()
        )

        // The evidence the gate asks for: the reference the script disabled is
        // counted as runtime-disabled and is gone from render and collision,
        // while the lever that ran the script still draws.
        #expect(rebuilt.summary.runtimeDisabledSkipCount == 1)
        #expect(rebuilt.summary.runtimeDeletedSkipCount == 0)
        #expect(rebuilt.summary.drawnRefCount == 1)
        #expect(rebuilt.summary.skippedRefCount == 1)
        #expect(rebuilt.summary.summaryLine.contains("1 skipped (1 runtime-disabled)"))
        #expect(rebuilt.renderScene.instanceCount == 1)
        #expect(cells.instanceTranslations(rebuilt) == [ScriptedWorldChain.leverPosition])
        #expect(!rebuilt.staticCollision.shapes.contains {
            $0.reference == FormID(ScriptedWorldChain.doorID)
        })
        // Disabled is not deleted: the door stays addressable, so a later
        // `Enable` can bring it back.
        #expect(rebuilt.references.entry(for: FormID(ScriptedWorldChain.doorID)) != nil)
    }
}
