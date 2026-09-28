// The mutable runtime display list (milestone 8.3.2 phase 2): bring-up,
// instantiation of registered classes, timeline stepping, the goto forms, path
// resolution, and scene regeneration.
//
// Every movie here is assembled in code from `SWFDisplayFixture` tags and
// `SWFActionFixture` action records — no test reads a real `.swf`
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct SWFMovieRuntimeTests {
    // MARK: - Bring-up

    @Test func bringUpBuildsTheRootDisplayListFromFrameOne() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        #expect(runtime.root.childCount == 1)
        let panel = try #require(runtime.root.child(named: "panel"))
        #expect(panel.isClip)
        #expect(panel.child(named: "art") != nil)
        #expect(runtime.tally.faultTotal == 0)
    }

    /// The whole point of phase 2: a class registered by `DoInitAction` runs
    /// with the placed display object as `this`.
    @Test func placingAnExportedSpriteRunsItsRegisteredClass() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: SWFRuntimeFixture.classMovieTags(marker: "wasConstructed")
        )
        let panel = try #require(runtime.root.child(named: "panel"))
        #expect(panel.object.lookup("wasConstructed")?.property.value == .number(1))
        #expect(runtime.runtime.registeredClassNames == ["PanelClip"])
    }

    @Test func aSpriteWithNoLinkageNameStillInstantiates() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 1, tags: [
                SWFRuntimeFixture.place(1, depth: 1),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFRuntimeFixture.place(2, depth: 1, name: "plain"),
            SWFDisplayFixture.showFrameTag
        ])
        let plain = try #require(runtime.root.child(named: "plain"))
        #expect(plain.object.prototype === runtime.movieClipPrototype)
    }

    @Test func startIsIdempotent() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let blocks = runtime.tally.blocksExecuted
        runtime.start()
        #expect(runtime.tally.blocksExecuted == blocks)
    }

    // MARK: - Timeline

    private static func threeFrameMovie() -> [SWFFixture.Tag] {
        [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFRuntimeFixture.place(1, depth: 1, name: "first"),
            SWFDisplayFixture.showFrameTag,
            SWFRuntimeFixture.place(1, depth: 2, name: "second"),
            SWFDisplayFixture.showFrameTag,
            SWFDisplayFixture.frameLabelTag("end"),
            SWFRuntimeFixture.place(1, depth: 3, name: "third"),
            SWFDisplayFixture.showFrameTag
        ]
    }

    @Test func advancingStepsOneFrameAndAppliesItsControlTags() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.threeFrameMovie())
        #expect(runtime.root.currentFrame == 0)
        #expect(runtime.root.childCount == 1)
        runtime.advance()
        #expect(runtime.root.currentFrame == 1)
        #expect(runtime.root.childCount == 2)
        runtime.advance()
        #expect(runtime.root.currentFrame == 2)
        #expect(runtime.root.childCount == 3)
        // The playhead wraps, which rebuilds the list from frame 1.
        runtime.advance()
        #expect(runtime.root.currentFrame == 0)
        #expect(runtime.root.childCount == 1)
        #expect(runtime.tickCount == 3)
    }

    @Test func aStoppedClipDoesNotAdvance() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.threeFrameMovie())
        runtime.perform(.stop, on: runtime.root)
        runtime.advance()
        runtime.advance()
        #expect(runtime.root.currentFrame == 0)
        #expect(runtime.root.isPlaying == false)
    }

    @Test func gotoByNumberRebuildsTheDisplayListForABackwardJump() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.threeFrameMovie())
        runtime.gotoFrame(2, of: runtime.root, play: false)
        #expect(runtime.root.childCount == 3)
        runtime.gotoFrame(0, of: runtime.root, play: false)
        #expect(runtime.root.childCount == 1)
        #expect(runtime.root.child(named: "second") == nil)
    }

    @Test func gotoByLabelFindsTheLabelledFrame() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.threeFrameMovie())
        runtime.gotoLabel("end", of: runtime.root, play: false)
        #expect(runtime.root.currentFrame == 2)
        #expect(runtime.root.child(named: "third") != nil)
    }

    @Test func anUnknownLabelIsTalliedAndLeavesThePlayheadAlone() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.threeFrameMovie())
        runtime.gotoLabel("nowhere", of: runtime.root, play: false)
        #expect(runtime.root.currentFrame == 0)
        #expect(runtime.tally.missingNames["gotoAndStop(nowhere)"] == 1)
    }

    /// `ActionGoToLabel` (0x8C) through the host, rather than the Swift API.
    @Test func actionGoToLabelReachesTheTimeline() throws {
        var tags = Self.threeFrameMovie()
        tags.insert(
            SWFActionFixture.doActionTag([SWFActionFixture.goToLabel("end")]),
            at: 2
        )
        let runtime = try SWFRuntimeFixture.started(tags: tags)
        #expect(runtime.root.currentFrame == 2)
        #expect(runtime.root.child(named: "third") != nil)
    }

    /// `gotoAndStop("end")` through the `MovieClip` method, which takes a
    /// one-based frame number when it is given one.
    @Test func gotoAndStopMethodAcceptsLabelsAndOneBasedNumbers() throws {
        var byLabel = Self.threeFrameMovie()
        byLabel.insert(
            SWFActionFixture.doActionTag(
                SWFRuntimeFixture.callOnThis(method: "gotoAndStop", argument: .string("end"))
            ),
            at: 2
        )
        let labelled = try SWFRuntimeFixture.started(tags: byLabel)
        #expect(labelled.root.currentFrame == 2)
        #expect(labelled.root.isPlaying == false)

        var byNumber = Self.threeFrameMovie()
        byNumber.insert(
            SWFActionFixture.doActionTag(
                SWFRuntimeFixture.callOnThis(method: "gotoAndPlay", argument: .integer(2))
            ),
            at: 2
        )
        let numbered = try SWFRuntimeFixture.started(tags: byNumber)
        #expect(numbered.root.currentFrame == 1)
        #expect(numbered.root.isPlaying)
    }

    // MARK: - Paths

    @Test func resolvesRootParentAndInstanceNamePaths() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let panel = try #require(runtime.root.child(named: "panel"))
        let art = try #require(panel.child(named: "art"))
        #expect(runtime.node(atPath: "panel", from: runtime.root) === panel)
        #expect(runtime.node(atPath: "_root.panel.art", from: art) === art)
        #expect(runtime.node(atPath: "/panel/art", from: runtime.root) === art)
        #expect(runtime.node(atPath: "_parent", from: art) === panel)
        #expect(runtime.node(atPath: "../..", from: art) === runtime.root)
        #expect(runtime.node(atPath: "panel.missing", from: runtime.root) == nil)
        #expect(runtime.node(atPath: "  ", from: runtime.root) == nil)
    }

    @Test func targetPathsSpellTheSlashForm() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let panel = try #require(runtime.root.child(named: "panel"))
        let art = try #require(panel.child(named: "art"))
        #expect(runtime.root.targetPath == "/")
        #expect(panel.targetPath == "/panel")
        #expect(art.targetPath == "/panel/art")
    }

    @Test func membersResolveChildrenAndSpecialTargets() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let panel = try #require(runtime.root.child(named: "panel"))
        #expect(runtime.member("panel", of: runtime.root)?.objectValue === panel.object)
        #expect(runtime.member("_parent", of: panel)?.objectValue === runtime.root.object)
        #expect(runtime.member("_root", of: panel)?.objectValue === runtime.root.object)
        #expect(runtime.member("nothingHere", of: panel) == nil)
    }

    // MARK: - Scene regeneration

    @Test func generatesDrawCommandsFromTheLiveTree() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let scene = runtime.makeScene()
        let items = SWFRuntimeFixture.drawItems(scene)
        #expect(items.count == 1)
        #expect(items.first?.content == .shape(1))
        // The panel's translation (400, 300) reaches the item transform.
        #expect(items.first?.transform.translateX == 400)
        #expect(items.first?.transform.translateY == 300)
        #expect(scene.skippedPlacements == 0)
    }

    @Test func hidingAClipRemovesItsSubtreeFromTheScene() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let panel = try #require(runtime.root.child(named: "panel"))
        panel.isVisible = false
        #expect(SWFRuntimeFixture.drawItems(runtime.makeScene()).isEmpty)
        panel.isVisible = true
        #expect(SWFRuntimeFixture.drawItems(runtime.makeScene()).count == 1)
    }

    @Test func theRuntimeSceneMatchesTheStaticSceneAtFrameOne() throws {
        let tags = SWFRuntimeFixture.classMovieTags()
        let movie = try SWFDisplayFixture.movie(tags: tags)
        let statically = SWFScene.build(movie: movie)
        let runtime = try SWFRuntimeFixture.started(tags: tags)
        #expect(runtime.makeScene().commands == statically.commands)
    }

    @Test func dirtyTrackingOnlyRegeneratesAfterAChange() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.threeFrameMovie())
        #expect(runtime.sceneIfChanged() != nil)
        #expect(runtime.sceneIfChanged() == nil)
        runtime.advance()
        #expect(runtime.sceneIfChanged() != nil)
    }

    // MARK: - Clip layers

    @Test func clipDepthStillProducesBeginAndEndCommands() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFRuntimeFixture.rectangle(id: 2, width: 800, height: 500),
            maskPlacement(characterId: 2, depth: 1, clipDepth: 2),
            SWFRuntimeFixture.place(1, depth: 2, name: "masked"),
            SWFDisplayFixture.showFrameTag
        ])
        let commands = runtime.makeScene().commands
        #expect(commands.count == 3)
        if case .beginClip = commands[0] {} else {
            Issue.record("expected a beginClip first, got \(commands[0])")
        }
        if case .endClip = commands[2] {} else {
            Issue.record("expected an endClip last, got \(commands[2])")
        }
    }

    private func maskPlacement(
        characterId: UInt16,
        depth: UInt16,
        clipDepth: UInt16
    ) -> SWFFixture.Tag {
        var place = SWFDisplayFixture.Place2()
        place.depth = depth
        place.characterId = characterId
        place.clipDepth = clipDepth
        return SWFDisplayFixture.placeObject2Tag(place)
    }
}
