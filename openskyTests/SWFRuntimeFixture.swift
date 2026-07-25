// Shared builders for the runtime display-list tests (milestone 8.3.2 phase 2).
// Every byte still comes from the two emitters milestone 8.3.1 added —
// `SWFDisplayFixture` for tags and `SWFActionFixture` for action records — so
// this file assembles them and never encodes anything itself. No test reads a
// real `.swf` (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky

enum SWFRuntimeFixture {
    typealias Action = AS2Fixture.Action

    static let ink = SWFColor(red: 220, green: 180, blue: 90, alpha: 255)

    /// `function <name>() { this.<marker> = 1 }` followed by
    /// `Object.registerClass("<linkage>", <name>)` — the shape every vanilla
    /// `DoInitAction` block ends in.
    static func registerClass(
        name: String,
        linkage: String,
        marker: String = "built"
    ) -> [Action] {
        let body: [Action] = [
            AS2Fixture.push([.string("this")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string(marker), .integer(1)]),
            AS2Fixture.opcode(0x4F)
        ]
        let define = SWFActionFixture.defineFunction(
            name: name, parameters: [], bodySize: UInt16(AS2Fixture.size(body))
        )
        return [define] + body + call(
            method: "registerClass",
            on: "Object",
            arguments: [
                [AS2Fixture.push([.string(linkage)])],
                [AS2Fixture.push([.string(name)]), AS2Fixture.opcode(0x1C)]
            ]
        )
    }

    /// `<receiver>.<method>(...)`, discarding the result. Each element of
    /// `arguments` is one argument expression in call order;
    /// `ActionCallMethod` pops the first argument first, so the expressions are
    /// emitted in reverse.
    static func call(
        method: String,
        on receiver: String,
        arguments: [[Action]] = []
    ) -> [Action] {
        var actions: [Action] = arguments.reversed().flatMap(\.self)
        actions.append(AS2Fixture.push([.integer(Int32(arguments.count))]))
        actions.append(AS2Fixture.push([.string(receiver)]))
        actions.append(AS2Fixture.opcode(0x1C))
        actions.append(AS2Fixture.push([.string(method)]))
        actions.append(AS2Fixture.opcode(0x52))
        actions.append(AS2Fixture.opcode(0x17))
        return actions
    }

    /// `this.<method>(<argument>)` on the running timeline, discarding the
    /// result.
    static func callOnThis(
        method: String,
        argument: SWFActionFixture.PushValue
    ) -> [Action] {
        [
            AS2Fixture.push([argument, .integer(1)]),
            AS2Fixture.push([.string("this")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string(method)]),
            AS2Fixture.opcode(0x52), AS2Fixture.opcode(0x17)
        ]
    }

    static func rectangle(id: UInt16, width: Int32 = 2000, height: Int32 = 1200)
        -> SWFFixture.Tag
    {
        SWFDisplayFixture.rectangleShapeTag(
            characterId: id, width: width, height: height, color: ink
        )
    }

    static func place(
        _ characterId: UInt16,
        depth: UInt16,
        name: String? = nil,
        translateX: Int32 = 0,
        translateY: Int32 = 0
    ) -> SWFFixture.Tag {
        var place = SWFDisplayFixture.Place2()
        place.depth = depth
        place.characterId = characterId
        place.name = name
        place.matrix = SWFDisplayFixture.MatrixSpec(
            translateX: translateX, translateY: translateY
        )
        return SWFDisplayFixture.placeObject2Tag(place)
    }

    /// A movie whose root places sprite 2 (a rectangle inside a sprite) under
    /// the instance name `panel`, with sprite 2 exported as `PanelClip` and a
    /// class registered against that linkage name.
    static func classMovieTags(marker: String = "built") -> [SWFFixture.Tag] {
        [
            rectangle(id: 1),
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 1, tags: [
                place(1, depth: 1, name: "art"),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.exportAssetsTag([(2, "PanelClip")]),
            SWFActionFixture.doInitActionTag(
                spriteId: 2, registerClass(name: "PanelClass", linkage: "PanelClip", marker: marker)
            ),
            place(2, depth: 1, name: "panel", translateX: 400, translateY: 300),
            SWFDisplayFixture.showFrameTag
        ]
    }

    static func runtime(tags: [SWFFixture.Tag], version: UInt8 = 6) throws -> SWFMovieRuntime {
        let movie = try SWFDisplayFixture.movie(tags: tags, version: version)
        return SWFMovieRuntime(movieScene: SWFMovieScene(movie: movie))
    }

    /// Runs the bring-up sequence and hands back the started runtime.
    static func started(tags: [SWFFixture.Tag], version: UInt8 = 6) throws -> SWFMovieRuntime {
        let runtime = try runtime(tags: tags, version: version)
        runtime.start()
        return runtime
    }

    /// Draw items of a generated scene, ignoring clip commands.
    static func drawItems(_ scene: SWFScene) -> [SWFSceneItem] {
        scene.commands.compactMap {
            guard case let .draw(item, _) = $0 else {
                return nil
            }
            return item
        }
    }
}
