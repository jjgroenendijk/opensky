// Synthetic fixtures for the Papyrus world runtime (issue #171): VMAD-carrying
// REFR entries, event-handler scripts, and a note-recording native dispatch.
// Every byte is built in code; no game data is embedded.

import Foundation
@testable import opensky
import Testing

/// Records "Probe.Note" calls in dispatch order while forwarding everything
/// else (Utility.Wait among them) to the standard native registry, so tests
/// can assert global event order and latent resumes together.
nonisolated final class PapyrusWorldProbeDispatch: PapyrusNativeDispatch {
    private let registry: PapyrusNativeRegistry
    private(set) var notes: [String] = []
    /// Stands in for a not-yet-written native (issue #172): consulted before
    /// the "Probe.Note" recorder, so a test can implement one `Probe.*` call
    /// against the world through `context.world` without waiting for the real
    /// `ObjectReference` family.
    var probeHandler: (
        (PapyrusNativeCall, PapyrusNativeContext) -> PapyrusNativeResult?
    )?

    /// - Parameter context: pass a context carrying a `PapyrusWorldAccess` to
    ///   give both the standard natives and `probeHandler` world access.
    init(context: PapyrusNativeContext = PapyrusNativeContext()) {
        registry = .standard(context: context)
    }

    func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        if PapyrusRuntime.matches(call.scriptName, "Probe") {
            if let result = probeHandler?(call, registry.context) {
                return result
            }
            if case let .string(note) = call.arguments.first {
                notes.append(note)
            }
            return .returned(.none)
        }
        return registry.invoke(call)
    }
}

/// Synthetic `PapyrusWorldReferenceSource`: a fixed reference index that
/// answers as if every entry were resident in one cell. This is what lets a
/// natives test run with no `CellStreamer`, no scene, and no GPU.
nonisolated final class PapyrusWorldFixtureReferences: PapyrusWorldReferenceSource {
    var index: RuntimeReferenceIndex
    /// Cell every known reference reports as resident in; nil models a
    /// reference the streamer cannot attribute, so writes go unattributed.
    var cell: CellSceneLocation?

    init(
        entries: [RuntimeReferenceEntry],
        cell: CellSceneLocation? = PapyrusWorldFixture.cell
    ) {
        index = RuntimeReferenceIndex(entries: entries)
        self.cell = cell
    }

    func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        index.entry(for: formID)
    }

    func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        index[key]
    }

    func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        index[key] == nil ? nil : cell
    }
}

enum PapyrusWorldFixture {
    static let pluginName = "skyrim.esm"
    static let cell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))
    static let otherCell = CellSceneLocation.interior(FormID(0x2000))

    static var resolver: FormIDResolver {
        FormIDResolver(pluginName: pluginName, masters: [])
    }

    static func key(objectID: UInt32, script: String) -> PapyrusInstanceKey {
        PapyrusInstanceKey(
            reference: .plugin(name: pluginName, objectID: objectID),
            scriptName: script
        )
    }

    /// One XLKR payload: keyword FormID then linked-reference FormID, or just
    /// the linked reference for the untagged short form.
    static func linkedReferenceField(keyword: UInt32?, ref: UInt32) -> Data {
        var payload = Data()
        if let keyword {
            payload.appendUInt32(keyword)
        }
        payload.appendUInt32(ref)
        return ESMFixture.field("XLKR", payload)
    }

    /// Decodes a synthetic REFR record carrying the given VMAD scripts into a
    /// runtime reference entry, the exact shape a cell build produces.
    ///
    /// - Parameter placement: DATA position, so a test can assert a
    ///   `SetPosition` write against something other than the origin.
    /// - Parameter linkedReferences: XLKR entries in file order, each a
    ///   `(keyword, ref)` pair of raw FormID values with a nil keyword meaning
    ///   an untagged link.
    static func referenceEntry(
        objectID: UInt32,
        scripts: [VMADFixture.Script],
        isPersistent: Bool = false,
        placement: SIMD3<Float> = .zero,
        linkedReferences: [(keyword: UInt32?, ref: UInt32)] = []
    ) throws -> RuntimeReferenceEntry {
        var name = Data()
        name.appendUInt32(0x100)
        var data = Data()
        for component in [placement.x, placement.y, placement.z] {
            data.appendUInt32(component.bitPattern)
        }
        data.append(Data(count: 12))
        let links = linkedReferences.reduce(into: Data()) { bytes, link in
            bytes += linkedReferenceField(keyword: link.keyword, ref: link.ref)
        }
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", data)
            + links
            + ESMFixture.field("VMAD", VMADFixture.payload(scripts: scripts))
        let bytes = ESMFixture.record("REFR", formID: objectID, data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a REFR record")
        }
        return try RuntimeReferenceEntry(
            key: .plugin(name: pluginName, objectID: objectID),
            formID: FormID(objectID),
            isPersistent: isPersistent,
            record: .reference(PlacedReference(record: record))
        )
    }

    static func index(_ entries: [RuntimeReferenceEntry]) -> RuntimeReferenceIndex {
        RuntimeReferenceIndex(entries: entries)
    }

    /// Event-handler body: optionally `Utility.Wait(waitSeconds)`, then a
    /// "Probe.Note" call recording `note`.
    static func probeBody(note: String, waitSeconds: Float? = nil) -> PexFunction {
        var instructions: [PexInstruction] = []
        if let waitSeconds {
            instructions.append(PapyrusTestSupport.instruction(
                .callStatic,
                .identifier("Utility"),
                .identifier("Wait"),
                .identifier("::nonevar"),
                .integer(1),
                .float(waitSeconds)
            ))
        }
        instructions.append(PapyrusTestSupport.instruction(
            .callStatic,
            .identifier("Probe"),
            .identifier("Note"),
            .identifier("::nonevar"),
            .integer(1),
            .string(note)
        ))
        return PexFixture.runtimeFunction(instructions: instructions)
    }

    static func eventScript(
        _ name: String,
        events: [(String, PexFunction)],
        variables: [PexVariable] = [],
        properties: [PexProperty] = []
    ) -> PexObject {
        PexFixture.runtimeObject(
            name: name,
            variables: variables,
            properties: properties,
            states: [PapyrusTestSupport.state(functions: events)]
        )
    }

    /// Script whose `OnInit`, `OnCellAttach`, and `OnLoad` each record
    /// "<name>.<event>", lowercased.
    static func fullEventScript(_ name: String) -> PexObject {
        let key = PapyrusRuntime.key(name)
        return eventScript(name, events: [
            ("OnInit", probeBody(note: "\(key).oninit")),
            ("OnCellAttach", probeBody(note: "\(key).oncellattach")),
            ("OnLoad", probeBody(note: "\(key).onload"))
        ])
    }

    @MainActor
    static func worldRuntime(
        objects: [PexObject],
        nativeDispatch: PapyrusNativeDispatch,
        fixedStepSeconds: Double = 1.0 / 30.0
    ) -> PapyrusWorldRuntime {
        PapyrusWorldRuntime(
            runtime: PapyrusRuntime(
                files: [PexFixture.runtimeFile(objects: objects)],
                nativeDispatch: nativeDispatch
            ),
            fixedStepSeconds: fixedStepSeconds
        )
    }

    /// A whole world-aware Papyrus session over synthetic data (issue #172):
    /// the store the natives write through, the bridge they reach it by, the
    /// reference source standing in for the streamer, and the runtime.
    struct Session {
        let world: PapyrusWorldRuntime
        let bridge: PapyrusWorldStateBridge
        let worldState: WorldStateStore
        let references: PapyrusWorldFixtureReferences
        let dispatch: PapyrusWorldProbeDispatch
    }

    /// Builds that session and attaches `entries` to the cell, so every VMAD
    /// script on them has a live instance.
    ///
    /// The attach leaves `OnInit`/`OnCellAttach`/`OnLoad` queued; call
    /// `drain(_:)` first when a test only cares about later events.
    @MainActor
    static func session(
        objects: [PexObject],
        entries: [RuntimeReferenceEntry],
        cell: CellSceneLocation? = cell,
        globals: GlobalStore? = nil,
        attach: Bool = true
    ) -> Session {
        let worldState = WorldStateStore()
        let references = PapyrusWorldFixtureReferences(entries: entries, cell: cell)
        let bridge = PapyrusWorldStateBridge(
            worldState: worldState, references: references, globals: globals
        )
        bridge.formIDResolver = resolver
        let dispatch = PapyrusWorldProbeDispatch(
            context: PapyrusNativeContext(world: PapyrusWorldAccess(bridge: bridge))
        )
        let world = worldRuntime(objects: objects, nativeDispatch: dispatch)
        bridge.world = world
        if attach, let cell {
            world.attach(
                cell: cell,
                references: RuntimeReferenceIndex(entries: entries),
                formIDResolver: resolver,
                firstIntegration: true
            )
        }
        return Session(
            world: world,
            bridge: bridge,
            worldState: worldState,
            references: references,
            dispatch: dispatch
        )
    }

    /// The standard native registry over a session's world (issue #172), which
    /// is how a natives test invokes one function directly instead of through
    /// compiled bytecode.
    @MainActor
    static func registry(for session: Session) -> PapyrusNativeRegistry {
        .standard(context: PapyrusNativeContext(
            world: PapyrusWorldAccess(bridge: session.bridge)
        ))
    }

    /// One `.method` native call, the shape the interpreter builds for
    /// `someReference.Disable()`.
    static func methodCall(
        _ scriptName: String,
        _ functionName: String,
        receiver: PapyrusObjectHandle?,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeCall {
        PapyrusNativeCall(
            kind: .method,
            scriptName: scriptName,
            functionName: functionName,
            receiver: receiver,
            arguments: arguments,
            returnType: returnType
        )
    }

    /// True when `result` is a failure of the invalid-arguments kind, which is
    /// what every world native returns rather than crashing or guessing.
    static func isInvalidArguments(_ result: PapyrusNativeResult) -> Bool {
        guard case .failed(.invalidArguments) = result else { return false }
        return true
    }

    /// Steps until a tick neither dispatches, resumes, nor leaves anything
    /// queued, bounded so a broken queue fails the test instead of hanging.
    @MainActor
    static func drain(_ world: PapyrusWorldRuntime, maxSteps: Int = 64) {
        for _ in 0 ..< maxSteps {
            let report = world.stepFixed()
            if report.dispatched == 0, report.resumed == 0, report.queued == 0 {
                return
            }
        }
        Issue.record("Papyrus world queue did not drain in \(maxSteps) steps")
    }
}
