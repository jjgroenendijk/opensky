// The activation fixtures: the placed interaction, the `OnActivate` script and
// the door session every activation test builds on. The M11 and M13
// scripted-world chains reuse `interaction(reference:action:)`.

@testable import FormatsESMTesting
import FormatsPEXTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
@testable import OpenSkyWorldInterface
import simd

@MainActor
public enum PapyrusWorldActivationFixture {
    // MARK: - Fixtures

    public static let doorID: UInt32 = 0x21
    public static let leverID: UInt32 = 0x22

    public static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }

    public static func interaction(
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

    public static func event(
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
    public static func onActivateScript(_ name: String) -> PexObject {
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

    public static func doorSession(
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
