// Rules that keep `openskycli gaps` complete, and the concurrency rules
// (docs/decisions/concurrency.md, "Rules for new code").

import SwiftSyntax

/// Each file reads its settings once and `GapsGatherer.settingsRead` lists it.
let settingReaders =
    "(src/Tests/.*|src/Sources/OpenSky(Combat/ImpulseSettings|Effects/BloodEffectSettings|AIPackages/(SandboxSettings|BumpReaction|FollowSettings)|CrimeInterface/(CrimeTexts|CrimeSettings)|CombatInterface/(Death|Impulse|Archery|Arrow|Combat|CombatAI|Difficulty|FallDamage|MeleeSkillUse|PowerAttack|Stagger|WeaponDamage)Settings|Camera/KillCamTrigger|AIPackages/GuardWarningSettings|Dialogue/SpeechTimerSettings|DialogueInterface/SpeechTimerSettings|WorldInterface/(DoorSettings|FollowSettings|FollowerCommandSettings|MountSettings)|GameData/(ActorValueDerivation|FaceMorphCounts|BarterPricing|CalendarTexts|CharacterLeveling|CraftingSkillUseSettings|InventoryMenuTexts|ItemDefinitionStore\\+EnchantedValue|ItemNoticeTexts|LeveledListSettings|MagicTexts|MenuRecordData|PickpocketSettings|ProgressionTexts|RegenerationSettings|SaveTexts|SkillAdvancement|SocialSettings|SoulTexts|SpellCostSettings|SpeechCheckSettings|StaminaSettings|TopicSubtypeTexts|TradeTexts|TrainingSettings)|Inventory/AlchemyRules|ActorPresentation/(FaceAnimationSettings|HeadTrackingSettings)|Magic/(EnchantingSettings|MagicHoldCore|RuneCore|ShoutCore|ShoutRumbleSettings|SoulTrap)|MagicInterface/(MagicWorldSettings|MagicHoldSettings)|InventoryInterface/(LockpickingSettings|LockTexts|TemperingTexts|VendorRestock)|PerceptionInterface/(DetectionSettings|StealthPoints)|Player/(PlayerBreath|PlayerMovementConfiguration)|RenderCore/Weather/SkySettings|WorldState/CellResetLedger)\\.swift)$"

/// Each file creates a queue that has its row in docs/decisions/concurrency.md.
let queueOwners =
    "src/Sources/(OpenSkyGameData/AssetLoader|OpenSkyAudio/WorldAudioEngine|OpenSkyCells/CellBuildRunner)\\.swift$"

let recordRules: [Rule] = [
    Rule(
        id: "perk_entry_point_literal",
        message: "Name the entry point in PerkEntryPoint+Engine.swift and add it to engineRead, so openskycli gaps sees it",
        excluded: "(src/Sources/OpenSkyProgressionInterface/PerkEntryPoint\\+Engine\\.swift|src/Tests/.*)$"
    ) { tree in
        Finder<FunctionCallExprSyntax>.run(tree) { call in
            ["PerkEntryPoint", "PerkEntryPoint.init"].contains(call.calledExpression.trimmedDescription)
                && call.arguments.first?.label?.text == "rawValue"
                && call.arguments.first?.expression.is(IntegerLiteralExprSyntax.self) == true
        }
    },
    Rule(
        id: "papyrus_event_literal",
        message: "Name the event in PapyrusEngineEvents and add it to sent, so openskycli gaps sees it",
        included: "src/Sources/OpenSkyScripting/.*\\.swift$",
        excluded: "src/Sources/OpenSkyScripting/PapyrusEngineEvents\\.swift$"
    ) { tree in
        Finder<StringLiteralExprSyntax>.run(tree) { literal in
            guard literal.segments.count == 1,
                  let segment = literal.segments.first?.as(StringSegmentSyntax.self)
            else { return false }
            return Rule.matches("^On[A-Z][A-Za-z]+$", segment.content.text)
        }
    },
    Rule(
        id: "shader_flag_mask",
        message: "Read a shader flag through has(_:) and a NIFShaderFlag constant, and list it in lightingRead or effectRead",
        excluded: "src/Tests/.*$"
    ) { tree in
        Finder<SequenceExprSyntax>.run(tree) { sequence in
            let elements = Array(sequence.elements)
            return zip(elements, elements.dropFirst()).contains { left, right in
                guard let name = lastName(left), ["shaderFlags1", "shaderFlags2"].contains(name),
                      let operation = right.as(BinaryOperatorExprSyntax.self)
                else { return false }
                return ["&", "&="].contains(operation.operator.text)
            }
        }
    },
    Rule(
        id: "game_setting_reader",
        message: "A new settings reader: call it in GapsGatherer.settingsRead and add its file to this rule, so openskycli gaps sees what it reads",
        excluded: settingReaders
    ) { tree in
        union(
            Finder<FunctionCallExprSyntax>.run(tree) { call in
                call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "setting"
                    && call.arguments.first?.label?.text == "editorID"
            },
            Finder<FunctionDeclSyntax>.run(tree) { function in
                let parameters = function.signature.parameterClause.parameters
                return function.name.text == "resolve" && parameters.count == 1
                    && parameters.first?.firstName.text == "store"
                    && parameters.first?.type.trimmedDescription == "GameSettingStore"
            }
        )
    }
]

let concurrencyRules: [Rule] = [
    Rule(
        id: "unchecked_sendable",
        message: "Keep shared state in a Mutex or make the type a Sendable value (docs/decisions/concurrency.md)",
        included: "src/Sources/.*\\.swift$"
    ) { tree in
        Finder<AttributedTypeSyntax>.run(tree) { type in
            hasAttribute(type.attributes, "unchecked") && type.baseType.trimmedDescription == "Sendable"
        }
    },
    Rule(
        id: "detached_task",
        message: "Load through a serial worker or a @concurrent function (docs/decisions/concurrency.md)",
        included: "src/Sources/.*\\.swift$"
    ) { tree in
        Finder<MemberAccessExprSyntax>.run(tree) { isMember($0, base: "Task", name: "detached") }
    },
    Rule(
        id: "main_queue_or_semaphore",
        message: "The main actor never waits for a worker; drain a Mutex mailbox instead (docs/decisions/concurrency.md)",
        included: "src/Sources/.*\\.swift$"
    ) { tree in
        union(
            Finder<MemberAccessExprSyntax>.run(tree) { isMember($0, base: "DispatchQueue", name: "main") },
            Finder<TokenSyntax>.run(tree) { $0.tokenKind == .identifier("DispatchSemaphore") }
        )
    },
    Rule(
        id: "new_dispatch_queue",
        message: "Use an existing worker; a new queue needs a row in docs/decisions/concurrency.md and its file in this rule",
        included: "src/Sources/.*\\.swift$",
        excluded: queueOwners
    ) { tree in
        union(
            Finder<FunctionCallExprSyntax>.run(tree) { call in
                call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "DispatchQueue"
            },
            Finder<MemberAccessExprSyntax>.run(tree) { isMember($0, base: "DispatchQueue", name: "global") }
        )
    }
]
