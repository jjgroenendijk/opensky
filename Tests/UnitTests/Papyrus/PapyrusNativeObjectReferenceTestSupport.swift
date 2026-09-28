// Shared fixture for the `ObjectReference` native suites (issue #172): one
// scripted lever in a synthetic cell, the world-aware native registry over it,
// and the receiver handle a method call needs.
//
// Fixtures are built in code — never extracted game files (AGENTS.md "Legal &
// IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeReferenceFixture {
    static let leverID: UInt32 = 0x0000_0AAA
    static let doorID: UInt32 = 0x0000_0BBB
    static let keywordID: UInt32 = 0x0000_0CCC
    static let otherKeywordID: UInt32 = 0x0000_0DDD

    let session: PapyrusWorldFixture.Session
    let registry: PapyrusNativeRegistry
    let receiver: PapyrusObjectHandle
    let key: ReferenceKey

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }

    /// A lever at (1, 2, 3) carrying one script, optionally with XLKR links and
    /// event handlers. The attach events are drained, so `dispatch.notes` holds
    /// only what a test's own call produces.
    static func make(
        links: [(keyword: UInt32?, ref: UInt32)] = [],
        events: [(String, PexFunction)] = []
    ) throws -> Self {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: leverID,
            scripts: [VMADFixture.Script("Lever", properties: [])],
            placement: SIMD3<Float>(1, 2, 3),
            linkedReferences: links
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Lever", events: events)],
            entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        return Self(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            receiver: session.world.objectHandle(for: entry.key),
            key: entry.key
        )
    }

    func call(
        _ functionName: String,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        registry.invoke(PapyrusWorldFixture.methodCall(
            "ObjectReference",
            functionName,
            receiver: receiver,
            arguments: arguments,
            returnType: returnType
        ))
    }

    /// The session-stable handle naming another reference, for a keyword or
    /// activator argument.
    func handle(_ objectID: UInt32) -> PapyrusObjectHandle {
        session.world.objectHandle(for: Self.key(objectID))
    }
}
