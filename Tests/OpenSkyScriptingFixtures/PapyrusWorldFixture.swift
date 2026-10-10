// Synthetic fixtures for the Papyrus world runtime: VMAD-carrying
// REFR entries, event-handler scripts, and a note-recording native dispatch.
// Every byte is built in code; no game data is embedded.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

/// Records "Probe.Note" calls in dispatch order while forwarding everything
/// else (Utility.Wait among them) to the standard native registry, so tests
/// can assert global event order and latent resumes together.
@MainActor
public final class PapyrusWorldProbeDispatch: PapyrusNativeDispatch {
    private let registry: PapyrusNativeRegistry
    public private(set) var notes: [String] = []
    /// Stands in for a not-yet-written native: consulted before
    /// the "Probe.Note" recorder, so a test can implement one `Probe.*` call
    /// against the world through `context.world` without waiting for the real
    /// `ObjectReference` family.
    public var probeHandler: (
        (PapyrusNativeCall, PapyrusNativeContext) -> PapyrusNativeResult?
    )?

    /// - Parameter context: pass a context carrying a `PapyrusWorldBridge` to
    ///   give both the standard natives and `probeHandler` world access.
    public init(context: PapyrusNativeContext = PapyrusNativeContext()) {
        registry = .standard(context: context)
    }

    public func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
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

public enum PapyrusWorldFixture {
    public static let pluginName = "skyrim.esm"
    public static let cell = FakeWorldReferences.defaultCell

    public static var resolver: FormIDResolver {
        FormIDResolver(pluginName: pluginName, masters: [])
    }

    public static func key(objectID: UInt32, script: String) -> PapyrusInstanceKey {
        PapyrusInstanceKey(
            reference: .plugin(name: pluginName, objectID: objectID),
            scriptName: script
        )
    }

    /// One XLKR payload: keyword FormID then linked-reference FormID, or just
    /// the linked reference for the untagged short form.
    public static func linkedReferenceField(keyword: UInt32?, ref: UInt32) -> Data {
        var payload = Data()
        if let keyword {
            payload.appendUInt32(keyword)
        }
        payload.appendUInt32(ref)
        return ESMFixture.field("XLKR", payload)
    }

    /// Decodes a synthetic REFR with the given VMAD scripts into the runtime
    /// entry a cell build produces. `placement` is the DATA position.
    /// `linkedReferences` are XLKR `(keyword, ref)` pairs; a nil keyword is an
    /// untagged link. `activateParents` become `XAPR` fields with no delay.
    public static func referenceEntry(
        objectID: UInt32,
        scripts: [VMADFixture.Script],
        isPersistent: Bool = false,
        placement: SIMD3<Float> = .zero,
        linkedReferences: [(keyword: UInt32?, ref: UInt32)] = [],
        activateParents: [UInt32] = []
    ) throws -> RuntimeReferenceEntry {
        var name = Data()
        name.appendUInt32(0x100)
        var data = Data()
        for component in [placement.x, placement.y, placement.z] {
            data.appendUInt32(component.bitPattern)
        }
        data.append(Data(count: 12))
        var links = linkedReferences.reduce(into: Data()) { bytes, link in
            bytes += linkedReferenceField(keyword: link.keyword, ref: link.ref)
        }
        links += activateParentFields(activateParents)
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

    /// The same thing as an ACHR rather than a REFR, which is what
    /// the `Actor` natives need: only a placed actor carries the NPC_ base an
    /// `ActorValueHolder` derives its baseline from.
    public static func actorEntry(
        objectID: UInt32,
        base: UInt32,
        scripts: [VMADFixture.Script],
        isPersistent: Bool = false
    ) throws -> RuntimeReferenceEntry {
        var name = Data()
        name.appendUInt32(base)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
            + ESMFixture.field("VMAD", VMADFixture.payload(scripts: scripts))
        let bytes = ESMFixture.record("ACHR", formID: objectID, data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce an ACHR record")
        }
        return try RuntimeReferenceEntry(
            key: .plugin(name: pluginName, objectID: objectID),
            formID: FormID(objectID),
            isPersistent: isPersistent,
            record: .actor(PlacedActor(record: record))
        )
    }

    public static func index(_ entries: [RuntimeReferenceEntry]) -> RuntimeReferenceIndex {
        RuntimeReferenceIndex(entries: entries)
    }

    /// Event-handler body: optionally `Utility.Wait(waitSeconds)`, then a
    /// "Probe.Note" call recording `note`.
    public static func probeBody(note: String, waitSeconds: Float? = nil) -> PexFunction {
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

    public static func eventScript(
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
    public static func fullEventScript(_ name: String) -> PexObject {
        let key = PapyrusRuntime.key(name)
        return eventScript(name, events: [
            ("OnInit", probeBody(note: "\(key).oninit")),
            ("OnCellAttach", probeBody(note: "\(key).oncellattach")),
            ("OnLoad", probeBody(note: "\(key).onload"))
        ])
    }

    @MainActor
    public static func worldRuntime(
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

    /// A whole world-aware Papyrus session over synthetic data:
    /// the store the natives write through, the bridge they reach it by, the
    /// reference source standing in for the streamer, and the runtime.
    public struct Session {
        public let world: PapyrusWorldRuntime
        public let bridge: PapyrusWorldStateBridge
        public let worldState: WorldStateStore
        public let references: FakeWorldReferences
        public let dispatch: PapyrusWorldProbeDispatch

        public init(
            world: PapyrusWorldRuntime,
            bridge: PapyrusWorldStateBridge,
            worldState: WorldStateStore,
            references: FakeWorldReferences,
            dispatch: PapyrusWorldProbeDispatch
        ) {
            self.world = world
            self.bridge = bridge
            self.worldState = worldState
            self.references = references
            self.dispatch = dispatch
        }
    }

    /// Builds the session and attaches `entries` to the cell, leaving
    /// `OnInit`/`OnCellAttach`/`OnLoad` queued; `drain(_:)` clears them. Pass
    /// `worldState` to build a second session over state a first one wrote.
    @MainActor
    public static func session(
        objects: [PexObject],
        entries: [RuntimeReferenceEntry],
        cell: CellSceneLocation? = cell,
        globals: GlobalStore? = nil,
        worldState: WorldStateStore = WorldStateStore(),
        attach: Bool = true
    ) -> Session {
        let references = FakeWorldReferences(entries: entries, cell: cell)
        let bridge = PapyrusWorldStateBridge(
            worldState: worldState, references: references, globals: globals
        )
        bridge.formIDResolver = resolver
        let dispatch = PapyrusWorldProbeDispatch(
            context: PapyrusNativeContext(world: bridge)
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

    /// The standard native registry over a session's world, which
    /// is how a natives test invokes one function directly instead of through
    /// compiled bytecode.
    @MainActor
    public static func registry(for session: Session) -> PapyrusNativeRegistry {
        .standard(context: PapyrusNativeContext(
            world: session.bridge
        ))
    }

    /// One `.method` native call, the shape the interpreter builds for
    /// `someReference.Disable()`.
    public static func methodCall(
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
    public static func isInvalidArguments(_ result: PapyrusNativeResult) -> Bool {
        guard case .failed(.invalidArguments) = result else { return false }
        return true
    }

    /// Steps until a tick neither dispatches, resumes, nor leaves anything
    /// queued, bounded so a broken queue fails the test instead of hanging.
    /// A world with two attached instances, references 1 (`AScript`) and 2
    /// (`BScript`), whose `OnLoad` notes "a.onload" and "b.onload". The attach
    /// events are dropped, so nothing is pending and nothing has run.
    @MainActor
    public static func twoInstanceWorld(
        probe: PapyrusWorldProbeDispatch
    ) throws -> PapyrusWorldRuntime {
        let aScript = eventScript("AScript", events: [("OnLoad", probeBody(note: "a.onload"))])
        let bScript = eventScript("BScript", events: [("OnLoad", probeBody(note: "b.onload"))])
        let world = worldRuntime(objects: [aScript, bScript], nativeDispatch: probe)
        let references = try index([
            referenceEntry(objectID: 1, scripts: [.init("AScript", properties: [])]),
            referenceEntry(objectID: 2, scripts: [.init("BScript", properties: [])])
        ])
        world.attach(
            cell: cell,
            references: references,
            formIDResolver: resolver,
            firstIntegration: true
        )
        world.eventQueue.removeAll()
        return world
    }

    @MainActor
    public static func drain(_ world: PapyrusWorldRuntime, maxSteps: Int = 64) {
        for _ in 0 ..< maxSteps {
            let report = world.stepFixed()
            if report.dispatched == 0, report.resumed == 0, report.queued == 0 {
                return
            }
        }
        Issue.record("Papyrus world queue did not drain in \(maxSteps) steps")
    }
}

extension PapyrusWorldFixture {
    /// One `XAPR` field per parent: its FormID, then a zero delay.
    static func activateParentFields(_ parents: [UInt32]) -> Data {
        parents.reduce(into: Data()) { bytes, parent in
            var payload = Data()
            payload.appendUInt32(parent)
            payload.appendUInt32(Float(0).bitPattern)
            bytes += ESMFixture.field("XAPR", payload)
        }
    }
}
