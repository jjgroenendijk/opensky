// The world reads over the synthetic lever: its editor location, shared location
// parents, whether a cell is an interior, and who an actor talks to.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
import OpenSkyDialogueInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeWorldReadTests {
    private typealias Fixture = PapyrusNativeReferenceFixture
    private static let holdID: UInt32 = 0x0000_0E10
    private static let townID: UInt32 = 0x0000_0E20
    private static let farmID: UInt32 = 0x0000_0E21
    private static let caveID: UInt32 = 0x0000_0E22
    private static let cellID: UInt32 = 0x0000_0E30
    private static let holdKeywordID: UInt32 = 0x0000_0E50

    @Test func editorLocationComesFromThePlaceSnapshot() throws {
        let fixture = try Fixture.make()
        fixture.session.bridge.conditionData = {
            ConditionDataResolution(editorLocations: [
                fixture.key: ResolvedFormID(plugin: "Skyrim.esm", objectID: Self.townID)
            ])
        }
        #expect(fixture.call("GetEditorLocation", returnType: .object("Location"))
            == .returned(.object(fixture.handle(Self.townID))))
        fixture.session.bridge.conditionData = { .empty }
        #expect(fixture.call("GetEditorLocation", returnType: .object("Location"))
            == .returned(.none))
    }

    /// The town and farm sit in the hold, which carries the keyword; the cave has no parent.
    @Test func commonParentNeedsASharedParentAndItsKeyword() throws {
        let fixture = try Fixture.make()
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "LCTN",
            contents: LocationFixture.recordBytes(
                Self.holdID, "Hold", keywords: [Self.holdKeywordID]
            )
                + LocationFixture.recordBytes(Self.townID, "Town", parent: Self.holdID)
                + LocationFixture.recordBytes(Self.farmID, "Farm", parent: Self.holdID)
                + LocationFixture.recordBytes(Self.caveID, "Cave")
        ))
        let store = LocationStore(plugins: [("Skyrim.esm", file)])
        fixture.session.bridge.conditionData = { ConditionDataResolution(locations: store) }
        let keyword = PapyrusValue.object(fixture.handle(Self.holdKeywordID))
        let other = PapyrusValue.object(fixture.handle(Self.cellID))

        #expect(commonParent(fixture, Self.townID, Self.farmID) == .returned(.boolean(true)))
        #expect(commonParent(fixture, Self.townID, Self.farmID, keyword)
            == .returned(.boolean(true)))
        #expect(commonParent(fixture, Self.townID, Self.farmID, other)
            == .returned(.boolean(false)))
        #expect(commonParent(fixture, Self.townID, Self.holdID) == .returned(.boolean(false)))
        #expect(commonParent(fixture, Self.townID, Self.caveID) == .returned(.boolean(false)))
    }

    @Test func aCellIsAnInteriorWithoutAWorldspace() throws {
        let fixture = try Fixture.make()
        fixture.session.bridge.formIDResolver = PapyrusWorldFixture.resolver
        for worldspace in [nil, FormID(0x3C)] {
            fixture.session.bridge.conditionData = {
                ConditionDataResolution(cells: [
                    fixture.key: ReferenceCell(cell: FormID(Self.cellID), worldspace: worldspace)
                ])
            }
            #expect(isInterior(fixture) == .returned(.boolean(worldspace == nil)))
        }
        fixture.session.bridge.conditionData = { .empty }
        #expect(PapyrusWorldFixture.isInvalidArguments(isInterior(fixture)))
    }

    @Test func theDialogueTargetOfTheSpeakerIsThePlayer() throws {
        let fixture = try Fixture.make()
        var context = ConditionContext()
        context.dialogue = DialogueResolution(speakerInDialogue: fixture.key)
        let speaking = context
        fixture.session.bridge.conditionEvaluator = {
            ConditionEvaluator(context: speaking, registry: ConditionFunctionRegistry())
        }
        let player = fixture.session.world.objectHandle(for: .player)
        #expect(dialogueTarget(fixture, fixture.receiver) == .returned(.object(player)))
        #expect(dialogueTarget(fixture, fixture.handle(Fixture.doorID)) == .returned(.none))
        #expect(dialogueTarget(fixture, player) == .returned(.none))
    }

    @Test func theBribeAmountIsTheSpeechCheckPrice() throws {
        let fixture = try Fixture.make()
        let player = Self.actor(level: 30, speech: 50)
        let npc = Self.actor(level: 10, speech: 20)
        var context = ConditionContext()
        context.actors = ActorStateResolution(states: [.player: player, fixture.key: npc])
        context.speechChecks = SpeechCheckResolution(settings: .fallback, bribeFactor: 0.5)
        let priced = context
        fixture.session.bridge.conditionEvaluator = {
            ConditionEvaluator(context: priced, registry: ConditionFunctionRegistry())
        }
        let price = SpeechCheckSettings.fallback.bribeAmount(SpeechCheckActors(
            playerLevel: 30, playerSpeech: 50, npcLevel: 10, npcSpeech: 20,
            npcMorality: 0, npcConfidence: 0
        ))
        #expect(fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", "GetBribeAmount", receiver: fixture.receiver, returnType: .integer
        )) == .returned(.integer(Int32(price * 0.5))))
    }

    @Test func sizeReadsTheBaseBoundsTimesTheScale() throws {
        let fixture = try Fixture.make()
        var bounds = Data()
        for value: Int16 in [-2, -4, -6, 2, 4, 6] {
            bounds.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        }
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "MISC",
            contents: ESMFixture.record(
                "MISC",
                formID: 0x100,
                data: ESMFixture.field("OBND", bounds)
            )
        ))
        fixture.session.bridge.keywordStore = KeywordStore(index: RecordIndex(
            plugins: [("Skyrim.esm", file)], recordTypes: RecordIndex.referenceRecordTypes
        ))
        fixture.session.bridge.write(ReferenceTransformOverride(
            position: SIMD3(1, 2, 3), rotation: .zero, scale: 2
        ).erased, for: fixture.key)
        for (name, size) in [("GetWidth", 8), ("GetLength", 16), ("GetHeight", 24)] as [(
            String,
            Float
        )] {
            #expect(fixture.call(name, returnType: .float) == .returned(.float(size)))
        }
        fixture.session.bridge.keywordStore = nil
        #expect(PapyrusWorldFixture.isInvalidArguments(fixture.call(
            "GetWidth",
            returnType: .float
        )))
    }

    private static func actor(level: Int, speech: Float) -> ActorConditionState {
        let values = ActorValues(repeating: 100)
        return ActorConditionState(
            current: values, maximums: values, combatActivity: .notFighting,
            generalBaseline: [SpeechCheckValues.speechcraft: speech], level: level
        )
    }

    private func commonParent(
        _ fixture: Fixture, _ location: UInt32, _ other: UInt32, _ filter: PapyrusValue = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Location", "HasCommonParent", receiver: fixture.handle(location),
            arguments: [.object(fixture.handle(other)), filter], returnType: .boolean
        ))
    }

    private func isInterior(_ fixture: Fixture) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Cell", "IsInterior", receiver: fixture.handle(Self.cellID), returnType: .boolean
        ))
    }

    private func dialogueTarget(
        _ fixture: Fixture, _ actor: PapyrusObjectHandle
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", "GetDialogueTarget", receiver: actor, returnType: .object("Actor")
        ))
    }
}
