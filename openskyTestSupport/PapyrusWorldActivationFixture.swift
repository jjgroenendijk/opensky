// The activation fixtures for issue #172: the placed interaction, the
// `OnActivate` script and the door session every activation test builds on.
// The M11 and M13 scripted-world chains reuse `interaction(reference:action:)`,
// and those chains are compiled into openskyRealDataTests as well, so the
// fixture half of the suite lives in the folder both test targets compile.
// The suite's tests are extensions of this type in
// `openskyTests/PapyrusWorldActivationTests.swift`; nothing here is private,
// because the two halves are no longer one file. See
// openskyTestSupport/AGENTS.md.

import Foundation
@testable import opensky
import simd

@MainActor
struct PapyrusWorldActivationTests {
    // MARK: - Fixtures

    static let doorID: UInt32 = 0x21
    static let leverID: UInt32 = 0x22

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }

    static func interaction(
        reference: UInt32,
        action: InteractionAction
    ) -> PlacedInteraction {
        PlacedInteraction(
            reference: FormID(reference),
            base: FormID(0x100),
            position: .zero,
            name: "Test Object",
            action: action,
            actionLabel: action == .open ? "Open" : "Activate",
            sounds: nil
        )
    }

    static func event(
        reference: UInt32,
        action: InteractionAction = .open
    ) -> InteractionEvent {
        InteractionEvent(target: InteractionTarget(
            interaction: interaction(reference: reference, action: action),
            hitPosition: .zero,
            distance: 1
        ))
    }

    /// `OnActivate(ObjectReference akActionRef)` forwarding its activator to
    /// `Probe.Seen`, so a test can watch the exact handle script code sees.
    static func onActivateScript(_ name: String) -> PexObject {
        let body = PexFixture.runtimeFunction(
            parameters: [PexTypedName(name: "akActionRef", typeName: "ObjectReference")],
            instructions: [PapyrusTestSupport.instruction(
                .callStatic,
                .identifier("Probe"),
                .identifier("Seen"),
                .identifier("::nonevar"),
                .integer(1),
                .identifier("akActionRef")
            )]
        )
        return PapyrusWorldFixture.eventScript(name, events: [("OnActivate", body)])
    }

    static func doorSession(
        scripts: [String]
    ) throws -> PapyrusWorldFixture.Session {
        try PapyrusWorldFixture.session(
            objects: scripts.map { onActivateScript($0) },
            entries: [PapyrusWorldFixture.referenceEntry(
                objectID: doorID,
                scripts: scripts.map { .init($0, properties: []) }
            )]
        )
    }
}
