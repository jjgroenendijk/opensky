// The debug commands that change the world as a script would, and `state music`, as a
// script types them.

import Foundation
import OpenSkyAgentControl
import Testing

struct AgentWorldChangeCommandTests {
    private func parse(_ words: [String]) throws -> AgentDebugCommand {
        let request = try AgentCommandLine.request(["debug"] + words)
        return try AgentDebugCommand.parse(
            words[0], AgentArguments(command: "debug.\(words[0])", values: request.args)
        )
    }

    @Test func aModifierTakesItsStrengthFadeAndHold() throws {
        #expect(try parse(["imod", "1A2B", "--strength", "0.5", "--fade", "2", "--crossfade"])
            == .world(.imageSpaceModifier(AgentModifierRequest(
                modifier: "1A2B", strength: 0.5, fadeSeconds: 2, crossFade: true, remove: false
            ))))
        #expect(try parse(["imod", "1A2B", "--off"])
            == .world(.imageSpaceModifier(AgentModifierRequest(
                modifier: "1A2B", strength: 1, fadeSeconds: 0, crossFade: false, remove: true
            ))))
        #expect(throws: (any Error).self) { try parse(["imod", "1A2B", "--fade", "-1"]) }
    }

    @Test func spellsCastsAndEnableStateNameTheirForms() throws {
        #expect(try parse(["cast", "12FCD", "--target", "1A2B"])
            == .world(.cast(spell: "12FCD", caster: "player", target: "1A2B")))
        #expect(try parse(["spell", "12FCD", "off"])
            == .world(.spell(spell: "12FCD", reference: "player", known: false)))
        #expect(try parse(["disable", "1A2B"]) == .world(.enable(
            reference: "1A2B",
            enabled: false
        )))
        #expect(try parse(["enable", "1A2B"]) == .world(.enable(reference: "1A2B", enabled: true)))
        #expect(try parse(["delete", "1A2B"]) == .world(.delete(reference: "1A2B")))
        #expect(try parse(["lock", "1A2B"]) == .world(.lock(reference: "1A2B", locked: true)))
        #expect(try parse(["lock", "1A2B", "off"])
            == .world(.lock(reference: "1A2B", locked: false)))
        #expect(try parse(["activate", "1A2B"])
            == .world(.activate(reference: "1A2B", activator: "player")))
        #expect(try parse(["activate", "1A2B", "--by", "3C4D"])
            == .world(.activate(reference: "1A2B", activator: "3C4D")))
    }

    @Test func decalsAndSpawnsHaveDefaults() throws {
        #expect(try parse(["decal", "target"]) == .world(.decal(reference: "target", height: 100)))
        #expect(try parse(["spawn", "1A2B"]) == .world(.spawn(base: "1A2B", anchor: "player")))
        #expect(try parse(["spawn", "1A2B", "--at", "target"])
            == .world(.spawn(base: "1A2B", anchor: "target")))
        #expect(throws: (any Error).self) { try parse(["decal", "target", "--height", "-5"]) }
    }

    @Test func aConditionReadNamesItsFunctionReferenceAndParameter() throws {
        let request = try AgentCommandLine.request(
            ["state", "condition", "GetLocked", "--ref", "1A2B", "--param", "3C"]
        )
        let args = AgentArguments(command: "state.condition", values: request.args)
        #expect(try AgentStateQuery.parse("condition", args)
            == .condition(function: "GetLocked", reference: "1A2B", parameter: "3C"))
        let bare = AgentArguments(command: "state.condition", values: ["function": "GetLocked"])
        #expect(try AgentStateQuery.parse("condition", bare)
            == .condition(function: "GetLocked", reference: "player", parameter: nil))
    }

    @Test func musicIsAStateRead() throws {
        let args = AgentArguments(command: "state.music", values: [:])
        #expect(try AgentStateQuery.parse("music", args) == .music)
    }
}
