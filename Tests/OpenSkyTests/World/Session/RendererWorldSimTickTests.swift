// The Papyrus VM in the engine loop: whole fixed steps, `Utility.Wait` resumes
// after the right count, and a paused frame does nothing. Offscreen renders use
// a fixed 1/30 s step without the game clock, so counts are exact. Needs Metal 4.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyRendering
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorld
import RenderingTesting
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct RendererWorldSimTickTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    private static let step = 1.0 / 30.0

    @MainActor
    private static func makeRenderer() throws -> Renderer {
        let device = try #require(Self.device)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view, shaderLibrary: ShaderLibraryFixture.library(device: device))
    }

    /// A script whose `OnLoad` waits one second and then records a note, so
    /// the note appears exactly when the scheduler has run 30 fixed steps.
    @MainActor
    private static func waitingWorld(
        _ probe: PapyrusWorldProbeDispatch
    ) -> PapyrusWorldRuntime {
        let script = PapyrusWorldFixture.eventScript("Waiter", events: [
            ("OnLoad", PapyrusWorldFixture.probeBody(note: "woke", waitSeconds: 1))
        ])
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [script], nativeDispatch: probe, fixedStepSeconds: step
        )
        world.enqueue(PapyrusScriptEvent(
            target: PapyrusWorldFixture.key(objectID: 0x101, script: "Waiter"),
            functionName: "OnLoad",
            arguments: []
        ))
        return world
    }

    /// Instantiates the waiting script under the key the queued event targets.
    @MainActor
    private static func seedInstance(_ world: PapyrusWorldRuntime) throws {
        let key = PapyrusWorldFixture.key(objectID: 0x101, script: "Waiter")
        let handle = try world.runtime.makeInstance(scriptName: "Waiter")
        world.instancesByKey[key] = handle
        world.keysByHandle[handle] = key
    }

    // MARK: - Frame hook

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aLatentWaitResumesAfterTheRightNumberOfFixedSteps() throws {
        let renderer = try Self.makeRenderer()
        let probe = PapyrusWorldProbeDispatch()
        let world = Self.waitingWorld(probe)
        try Self.seedInstance(world)
        renderer.onWorldUpdate = { delta in
            _ = world.advance(delta: delta, gameClock: renderer.gameClock)
        }

        // One step delivers OnLoad, which suspends; 30 more steps of 1/30 s
        // satisfy Utility.Wait(1.0).
        let hook = try #require(renderer.onWorldUpdate)
        hook(Float(Self.step))
        #expect(probe.notes.isEmpty)
        for _ in 0 ..< 29 {
            hook(Float(Self.step))
        }
        #expect(probe.notes.isEmpty)
        hook(Float(Self.step))
        #expect(probe.notes == ["woke"])
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aPartialDeltaAdvancesNothingUntilItAccumulatesAStep() throws {
        let renderer = try Self.makeRenderer()
        let probe = PapyrusWorldProbeDispatch()
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [PapyrusWorldFixture.fullEventScript("Waiter")],
            nativeDispatch: probe,
            fixedStepSeconds: Self.step
        )
        try Self.seedInstance(world)
        world.enqueue(PapyrusScriptEvent(
            target: PapyrusWorldFixture.key(objectID: 0x101, script: "Waiter"),
            functionName: "OnLoad",
            arguments: []
        ))
        renderer.onWorldUpdate = { _ = world.advance(delta: $0) }
        let hook = try #require(renderer.onWorldUpdate)

        hook(Float(Self.step) / 2)
        #expect(probe.notes.isEmpty)
        hook(Float(Self.step) / 2)
        #expect(probe.notes == ["waiter.onload"])
    }

    // MARK: - Offscreen fixed step

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func offscreenFramesDriveTheWorldTickAndAPausedFrameDoesNot() throws {
        let renderer = try Self.makeRenderer()
        var deltas: [Float] = []
        renderer.onWorldUpdate = { deltas.append($0) }

        _ = try renderer.renderOffscreen(width: 64, height: 64)
        #expect(deltas == [Float(Self.step)])

        renderer.worldSimPaused = true
        _ = try renderer.renderOffscreen(width: 64, height: 64)
        #expect(deltas == [Float(Self.step), 0])
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aPausedWorldTickAdvancesNoScript() throws {
        let renderer = try Self.makeRenderer()
        let probe = PapyrusWorldProbeDispatch()
        let world = Self.waitingWorld(probe)
        try Self.seedInstance(world)
        renderer.onWorldUpdate = { _ = world.advance(delta: $0) }
        renderer.worldSimPaused = true

        for _ in 0 ..< 60 {
            _ = try renderer.renderOffscreen(width: 64, height: 64)
        }
        #expect(probe.notes.isEmpty)

        renderer.worldSimPaused = false
        for _ in 0 ..< 31 {
            _ = try renderer.renderOffscreen(width: 64, height: 64)
        }
        #expect(probe.notes == ["woke"])
    }
}
