// The structural rules. Each one names the decision page that holds its reason; the
// classification of every rule is on docs/decisions/code-health-automation.md.

import SwiftSyntax

let sourcesOnly = "^src/Sources/OpenSky([A-Z][A-Za-z]*)?/.*\\.swift$"
let wiringNames =
    "^(\\w+World|world|host|\\w+Host|port|\\w+Port|seam|\\w+Seam|globals|game|session)$"
let lateSetterTypes = "(Store|Settings|Texts|Runtime|Catalog|Resolver|World|Seam|Reporting|Presenting)"
let clockNames: Set = [
    "CACurrentMediaTime", "DispatchTime", "ContinuousClock", "SuspendingClock",
    "mach_absolute_time", "CFAbsoluteTimeGetCurrent", "systemUptime"
]
let impureModules: Set = [
    "AppKit", "Cocoa", "SwiftUI", "Metal", "MetalKit", "MetalFX", "QuartzCore", "AVFoundation",
    "AVFAudio", "AudioToolbox", "CoreAudio", "GameController", "Dispatch", "OpenSkyRendering"
]

let rules: [Rule] = architectureRules + recordRules + concurrencyRules

let architectureRules: [Rule] = [
    Rule(
        id: "game_view_controller_extension",
        message: "Put game logic in a coordinator in its feature module, not a GameViewController extension",
        excluded: "src/Sources/OpenSky/GameView/GameViewController\\.swift$"
    ) { tree in
        Finder<ExtensionDeclSyntax>.run(tree) { $0.extendedType.trimmedDescription == "GameViewController" }
    },
    Rule(
        id: "late_attached_world",
        message: "Take the world port in the initializer and return commands (docs/engine/coordinators.md)",
        included: sourcesOnly
    ) { tree in
        Finder<FunctionDeclSyntax>.run(tree) { function in
            Rule.matches("^(attach|wire|connect|bind|set|install)", function.name.text)
                && firstParameterName(function).map { Rule.matches(wiringNames, $0) } == true
        }
    },
    Rule(
        id: "late_setter_method",
        message: "Take the dependency in the initializer; no wire or install method (docs/decisions/session-scope.md)",
        included: sourcesOnly
    ) { tree in
        let allowed: Set = [
            "public", "open", "package", "internal", "final", "override", "nonisolated", "mutating"
        ]
        return Finder<FunctionDeclSyntax>.run(tree) { function in
            Rule.matches("^(wire|install)", function.name.text)
                && modifierNames(function.modifiers).allSatisfy(allowed.contains)
        }
    },
    Rule(
        id: "connection_step_type",
        message: "An adapter registers as it is built over the session stage; no connection step type (docs/decisions/session-scope.md)",
        included: sourcesOnly
    ) { tree in
        let allowed: Set = ["public", "package", "internal", "final", "nonisolated"]
        func wiring(_ name: TokenSyntax, _ modifiers: DeclModifierListSyntax) -> Bool {
            name.text.hasSuffix("Wiring") && modifierNames(modifiers).allSatisfy(allowed.contains)
        }
        return union(
            Finder<StructDeclSyntax>.run(tree) { wiring($0.name, $0.modifiers) },
            Finder<ClassDeclSyntax>.run(tree) { wiring($0.name, $0.modifiers) },
            Finder<EnumDeclSyntax>.run(tree) { wiring($0.name, $0.modifiers) },
            Finder<ActorDeclSyntax>.run(tree) { wiring($0.name, $0.modifiers) }
        )
    },
    Rule(
        id: "late_setter_property",
        message: "Take the dependency in the initializer, or make the property private(set) (docs/decisions/session-scope.md)",
        included: "src/Sources/OpenSky([A-Z][A-Za-z]*)?/(.*/)?[A-Za-z]*Coordinator(\\+[A-Za-z]+)?\\.swift$"
    ) { tree in
        Finder<VariableDeclSyntax>.run(tree, isLateSetterProperty)
    },
    Rule(
        id: "coordinator_outside_session_scope",
        message: "Only the session scope builds a game coordinator; the app shell builds app-scope ones (docs/decisions/session-scope.md)",
        included: "src/Sources/OpenSky/.*\\.swift$",
        excluded: "src/Sources/OpenSky/(Shell/.*|Launcher/.*|GameView/GameSessionScope[^/]*)\\.swift$"
    ) { tree in
        Finder<FunctionCallExprSyntax>.run(tree) { call in
            lastName(call.calledExpression).map { Rule.matches("^[A-Z]\\w*Coordinator$", $0) } == true
        }
    },
    Rule(
        id: "controller_outside_composition_root",
        message: "Only the composition root names GameViewController; reach the session through a host protocol (docs/engine/coordinators.md)",
        included: "src/Sources/.*\\.swift$",
        excluded: "src/Sources/OpenSky/(Shell/.*|GameView/GameViewController[A-Za-z]*)\\.swift$"
    ) { tree in
        Finder<TokenSyntax>.run(tree) { $0.tokenKind == .identifier("GameViewController") }
    },
    Rule(
        id: "action_returns_text",
        message: "Return a typed outcome and build its line in a formatter (docs/engine/coordinators.md)",
        excluded: "(src/Sources/OpenSky/|src/Tests/).*$"
    ) { tree in
        let allowed: Set = ["public", "internal", "package"]
        return Finder<FunctionDeclSyntax>.run(tree) { function in
            hasAttribute(function.attributes, "discardableResult")
                && modifierNames(function.modifiers).allSatisfy(allowed.contains)
                && function.signature.returnClause?.type.trimmedDescription == "String"
        }
    },
    Rule(
        id: "pure_core_side_effect",
        message: "A core is pure: no AppKit, Metal, audio, or clock; the shell passes the time in (docs/engine/coordinators.md)",
        included: "src/Sources/OpenSky([A-Z][A-Za-z]*)?/(.*/)?[A-Za-z]+Core(\\+[A-Za-z]+)?\\.swift$"
    ) { tree in
        union(
            Finder<ImportDeclSyntax>.run(tree) { impureModules.contains($0.path.first?.name.text ?? "") },
            Finder<FunctionCallExprSyntax>.run(tree) { call in
                call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Date"
                    && call.arguments.isEmpty
            },
            Finder<MemberAccessExprSyntax>.run(tree) { isMember($0, base: "Date", name: "now") },
            Finder<TokenSyntax>.run(tree) { token in
                if case let .identifier(name) = token.tokenKind {
                    return clockNames.contains(name)
                }
                return false
            }
        )
    },
    Rule(
        id: "renderer_downcast",
        message: "Read game state from RenderFrameInput, never by casting the renderer or its driver (docs/engine/architecture.md)",
        included: "src/Sources/.*\\.swift$"
    ) { tree in
        Finder<SequenceExprSyntax>.run(tree, castsRenderer)
    },
    Rule(
        id: "papyrus_loose_closure",
        message: "Give the bridge a collaborator through a native family value, not a closure property (docs/engine/coordinators.md)",
        included: "src/Sources/OpenSkyScripting/PapyrusWorld[A-Za-z]*Bridge[^/]*\\.swift$"
    ) { tree in
        Finder<VariableDeclSyntax>.run(tree) { variable in
            variable.bindings.contains { binding in
                isStored(binding) && binding.typeAnnotation.map { containsFunctionType($0.type) } == true
            }
        }
    },
    Rule(
        id: "frame_callback_property",
        message: "Join the frame through a phase of a FrameSchedule, not a callback (docs/engine/architecture.md)",
        included: "src/Sources/.*\\.swift$",
        excluded: "src/Sources/OpenSky(GameData/FrameSchedule|/(Shell|Launcher)/.*)\\.swift$"
    ) { tree in
        Finder<VariableDeclSyntax>.run(tree) { variable in
            variable.bindingSpecifier.text == "var" && variable.bindings.contains { binding in
                bindingName(binding).map { Rule.matches("(Frame|frame|Tick|tick|Update|update)", $0) } == true
                    && isStored(binding)
                    && binding.typeAnnotation.map { containsFunctionType($0.type) } == true
            }
        }
    },
    Rule(
        id: "adapter_unowned_reference",
        message: "An adapter holds its host strongly and no reference to its owner (docs/decisions/ports-and-adapters.md, rule 9)",
        included: "^src/Sources/[A-Za-z]*Adapters/.*\\.swift$"
    ) { tree in
        Finder<TokenSyntax>.run(tree) { $0.tokenKind == .keyword(.unowned) }
    }
]

func isLateSetterProperty(_ variable: VariableDeclSyntax) -> Bool {
    let names = modifierNames(variable.modifiers)
    let others: Set = ["final", "nonisolated", "weak", "unowned", "lazy"]
    guard
        variable.bindingSpecifier.text == "var",
        names.contains(where: { ["public", "open", "package"].contains($0) }),
        names.allSatisfy({ ["public", "open", "package"].contains($0) || others.contains($0) })
    else { return false }
    return variable.bindings.contains { binding in
        if let name = bindingName(binding), Rule.matches("^on[A-Z]", name) {
            return true
        }
        if let type = binding.typeAnnotation?.type {
            return isStored(binding) && Rule.matches("\\b\\w*\(lateSetterTypes)\\b", type.trimmedDescription)
        }
        guard let value = binding.initializer?.value, let first = value.firstToken(viewMode: .sourceAccurate)
        else { return false }
        return Rule.matches("^\\w*\(lateSetterTypes)$", first.text)
    }
}

/// `renderer as? T`, `renderer as! T`, or `frameDriver is T`, before operators are folded.
func castsRenderer(_ sequence: SequenceExprSyntax) -> Bool {
    let elements = Array(sequence.elements)
    return zip(elements, elements.dropFirst()).contains { left, right in
        guard let name = lastName(left), ["renderer", "frameDriver"].contains(name) else { return false }
        if let cast = right.as(UnresolvedAsExprSyntax.self) {
            return cast.questionOrExclamationMark != nil
        }
        return right.is(UnresolvedIsExprSyntax.self)
    }
}
