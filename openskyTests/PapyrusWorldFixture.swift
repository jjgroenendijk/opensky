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
    private let registry = PapyrusNativeRegistry.standard
    private(set) var notes: [String] = []

    func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        if PapyrusRuntime.matches(call.scriptName, "Probe") {
            if case let .string(note) = call.arguments.first {
                notes.append(note)
            }
            return .returned(.none)
        }
        return registry.invoke(call)
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

    /// Decodes a synthetic REFR record carrying the given VMAD scripts into a
    /// runtime reference entry, the exact shape a cell build produces.
    static func referenceEntry(
        objectID: UInt32,
        scripts: [VMADFixture.Script],
        isPersistent: Bool = false
    ) throws -> RuntimeReferenceEntry {
        var name = Data()
        name.appendUInt32(0x100)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
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
