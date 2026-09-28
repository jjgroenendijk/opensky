// The fixture behind `M11ScriptedWorldAcceptanceTests` (issue #172): a lever
// whose compiled `OnActivate` body calls `GetLinkedRef` and then `Disable`,
// wired to a real `CellStreamer` and driven by a real raycast activation.
//
// Every byte is built in code — REFR records, PEX objects, and the plugin the
// rebuild reads — never extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import simd
import Testing

/// Holds what script code saw, so `akActionRef` can be asserted on the exact
/// value the bytecode passed rather than on the queued event.
final class M11ScriptedWorldRecorder {
    var seen: [PapyrusValue] = []
}

/// Runs the whole activation chain once, in `init`, and exposes what it left
/// behind. Constructing it is the test action; the tests only assert.
@MainActor
struct M11ScriptedWorldChain {
    static let leverID: UInt32 = 0x22
    static let doorID: UInt32 = 0x21
    static let statID: UInt32 = 0x100
    static let leverPosition = SIMD3<Float>(10, 20, 30)
    static let doorPosition = SIMD3<Float>(-10, -20, -30)
    /// The cell the streamer resolves the camera into, the cell both writes are
    /// attributed to, and the cell the rebuild reads — all the same cell.
    static let cell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))

    static var leverKey: ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: leverID)
    }

    static var doorKey: ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: doorID)
    }

    let session: PapyrusWorldFixture.Session
    let streamer: CellStreamer
    let recorder = M11ScriptedWorldRecorder()

    init(
        activate: Bool = true,
        scriptName: String = "LeverScript",
        objects: [PexObject]? = nil
    ) throws {
        let lever = try PapyrusWorldFixture.referenceEntry(
            objectID: Self.leverID,
            scripts: [VMADFixture.Script(scriptName, properties: [])],
            isPersistent: true,
            placement: Self.leverPosition,
            // The authored XLKR link, untagged, is the only thing that tells the
            // script which reference it affects.
            linkedReferences: [(keyword: nil, ref: Self.doorID)]
        )
        let door = try PapyrusWorldFixture.referenceEntry(
            objectID: Self.doorID, scripts: [], placement: Self.doorPosition
        )
        session = PapyrusWorldFixture.session(
            objects: objects ?? [Self.objectReferenceScript(), Self.leverScript()],
            entries: [lever, door],
            cell: Self.cell
        )
        let runner = ManualCellBuildRunner()
        streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        // The streamer answers every world lookup from here on, so cell
        // attribution is the engine's answer and not the fixture's.
        session.bridge.references = streamer
        let recorder = recorder
        session.dispatch.probeHandler = { call, _ in
            recorder.seen.append(contentsOf: call.arguments)
            return .returned(.none)
        }
        streamer.onInteraction.add { [weak bridge = session.bridge] event in
            bridge?.handleInteraction(event)
        }
        Self.integrate(streamer: streamer, runner: runner, entries: [lever, door])
        // Attach queued OnInit/OnCellAttach/OnLoad; drain them so only the
        // activation's own work is left to observe.
        PapyrusWorldFixture.drain(session.world)

        if activate {
            Self.pressUseKey(streamer)
            PapyrusWorldFixture.drain(session.world)
        }
    }

    // MARK: - Entering the chain

    /// Completes the one cell build the streamer asks for, with the lever
    /// carrying an `activate` interaction and a collision shape to raycast at.
    private static func integrate(
        streamer: CellStreamer,
        runner: ManualCellBuildRunner,
        entries: [RuntimeReferenceEntry]
    ) {
        let lever = PapyrusWorldActivationTests.interaction(
            reference: leverID, action: .activate
        )
        streamer.update(cameraPosition: CellStreamerTests.center)
        runner.complete(
            CellStreamerTests.coordinate(0, 0),
            with: .success(CellStreamerTests.cellScene(
                location: cell,
                interactions: [lever.reference: lever],
                staticCollision: collision(reference: leverID, position: leverTarget),
                references: RuntimeReferenceIndex(entries: entries)
            ))
        )
    }

    /// Where this test enters the chain: `CellStreamer.update(cameraPosition:
    /// interactionRay:activate:)`, the same call the render loop makes every
    /// frame with the use key held. Everything above it is `GameViewController`
    /// key handling and an `MTKView` draw callback, neither of which a headless
    /// test can honestly drive, so the raycast, the interaction target, the
    /// `InteractionEvent`, and the multicast fan-out are all real from here.
    private static func pressUseKey(_ streamer: CellStreamer) {
        let ray = CellStreamerTests.interactionRay(
            from: CellStreamerTests.center, to: leverTarget
        )
        streamer.update(cameraPosition: CellStreamerTests.center, interactionRay: ray)
        streamer.update(
            cameraPosition: CellStreamerTests.center, interactionRay: ray, activate: true
        )
    }

    /// Where the lever's collision shape sits, a short walk from the camera so
    /// the view ray reaches it.
    private static var leverTarget: SIMD3<Float> {
        CellStreamerTests.center + SIMD3<Float>(10, 0, 0)
    }

    private static func collision(
        reference: UInt32,
        position: SIMD3<Float>
    ) -> StaticCollisionSet {
        let extent = SIMD3<Float>(repeating: 1)
        var stats = StaticCollisionStats()
        stats.shapeCount = 1
        return StaticCollisionSet(
            location: nil,
            shapes: [StaticCollisionShape(
                reference: FormID(reference),
                transform: MatrixMath.translation(position),
                geometry: .box(halfExtents: extent),
                bounds: ModelBounds(min: position - extent, max: position + extent)
            )],
            stats: stats
        )
    }

    // MARK: - The compiled scripts

    /// The base script every placed reference extends, carrying the two
    /// functions this gate needs as `native` declarations with no body — the
    /// same shape the game's own `ObjectReference.pex` has. It is what makes
    /// `Self.GetLinkedRef()` inside a subclass dispatch as
    /// `ObjectReference.GetLinkedRef` rather than under the subclass's name.
    static func objectReferenceScript() -> PexObject {
        PexFixture.runtimeObject(
            name: "ObjectReference",
            states: [PapyrusTestSupport.state(functions: [
                ("GetLinkedRef", PexFixture.runtimeFunction(
                    returnType: "ObjectReference", flags: .native, instructions: []
                )),
                ("Disable", PexFixture.runtimeFunction(
                    flags: .native, instructions: []
                ))
            ])]
        )
    }

    /// `LeverScript extends ObjectReference`, whose whole body is:
    ///
    /// ```papyrus
    /// Event OnActivate(ObjectReference akActionRef)
    ///     Probe.Seen(akActionRef)
    ///     ObjectReference linked = Self.GetLinkedRef()
    ///     linked.Disable()
    /// EndEvent
    /// ```
    ///
    /// assembled as the three instructions a compiler emits for it. The
    /// `Probe.Seen` call is the test's only addition, and it observes
    /// `akActionRef` without affecting the world.
    static func leverScript() -> PexObject {
        let body = PexFixture.runtimeFunction(
            parameters: [PexTypedName(name: "akActionRef", typeName: "ObjectReference")],
            locals: [PexTypedName(name: "linked", typeName: "ObjectReference")],
            instructions: [
                PapyrusTestSupport.instruction(
                    .assign,
                    .identifier("activationMarker"),
                    .integer(1)
                ),
                PapyrusTestSupport.instruction(
                    .callStatic,
                    .identifier("Probe"),
                    .identifier("Seen"),
                    .identifier("::nonevar"),
                    .integer(1),
                    .identifier("akActionRef")
                ),
                PapyrusTestSupport.instruction(
                    .callMethod,
                    .identifier("GetLinkedRef"),
                    .identifier("self"),
                    .identifier("linked"),
                    .integer(0)
                ),
                PapyrusTestSupport.instruction(
                    .callMethod,
                    .identifier("Disable"),
                    .identifier("linked"),
                    .identifier("::nonevar"),
                    .integer(0)
                )
            ]
        )
        return PexFixture.runtimeObject(
            name: "LeverScript",
            parent: "ObjectReference",
            variables: [PexVariable(
                name: "activationMarker",
                typeName: "Int",
                userFlags: 0,
                initialValue: .integer(0)
            )],
            states: [PapyrusTestSupport.state(functions: [("OnActivate", body)])]
        )
    }

    // MARK: - The rebuild's plugin

    /// The same two references the Papyrus session knows, spelled as a plugin
    /// the real `CellSceneBuilder` reads. Object IDs match, so the world-state
    /// snapshot the script wrote keys straight onto these records.
    static func rebuildPlugin(_ cells: CellSceneBuilderTests) -> Data {
        cells.plugin(
            grid: (0, 0),
            temporaryRefs: cells.refrRecord(
                formID: leverID, base: statID, position: leverPosition
            ) + cells.refrRecord(
                formID: doorID, base: statID, position: doorPosition
            ),
            statRecords: cells.statRecord(formID: statID, modelPath: "arch\\solid.nif")
        )
    }
}
