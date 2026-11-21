// PlaceObject3 filter lists and how their shadows, glows, blurs, and blend mode reach the
// scene draws. Filter bytes are built in code.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFFilterTests {
    private static let red = SWFColor(red: 255, green: 0, blue: 0, alpha: 255)

    private static func fixed(_ value: Float) -> [UInt8] {
        let raw = UInt32(bitPattern: Int32(value * 65536))
        return (0 ..< 4).map { UInt8(truncatingIfNeeded: raw >> ($0 * 8)) }
    }

    private static func fixed8(_ value: Float) -> [UInt8] {
        let raw = UInt16(bitPattern: Int16(value * 256))
        return [UInt8(truncatingIfNeeded: raw), UInt8(truncatingIfNeeded: raw >> 8)]
    }

    private static func dropShadow(
        rgba: [UInt8] = [0, 0, 0, 255], blur: Float = 0, angle: Float = 0,
        distance: Float = 2, flags: UInt8 = 0x21
    ) -> [UInt8] {
        [0] + rgba + fixed(blur) + fixed(blur) + fixed(angle) + fixed(distance) + fixed8(1)
            + [flags]
    }

    private static func tags(filters: [[UInt8]], blendMode: UInt8? = nil) -> [SWFFixture.Tag] {
        var place3 = SWFDisplayFixture.Place3()
        place3.place.depth = 1
        place3.place.characterId = 10
        place3.filters = filters
        place3.blendMode = blendMode
        return [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 10, width: 1000, height: 1000, color: red
            ),
            SWFDisplayFixture.placeObject3Tag(place3),
            SWFDisplayFixture.showFrameTag
        ]
    }

    private static func item(alpha: Float = 1) -> SWFSceneItem {
        var color = SWFColorTransform.identity
        color.multiply.w = alpha
        return SWFSceneItem(content: .shape(1), transform: .identity, colorTransform: color)
    }

    @Test func aFilterListKeepsShadowGlowAndBlurValuesAndSkipsOtherKinds() throws {
        let glow = [2, 255, 255, 0, 128] + Self.fixed(6) + Self.fixed(6) + Self.fixed8(2) + [0x80]
        let blur = [1] + Self.fixed(2) + Self.fixed(3) + [0x08]
        let bevel = [UInt8(3)] + [UInt8](repeating: 0, count: 27)
        let shadow = Self.dropShadow(blur: 4, angle: 0.5, flags: 0x41)
        var bits = SWFBitReader(Data([4] + shadow + blur + glow + bevel))

        let filters = try SWFFilter.parseList(&bits)

        #expect(bits.remainingData.isEmpty)
        #expect(filters.map(\.id) == [0, 1, 2, 3])
        guard case let .shadow(dropShadow) = filters[0], case let .shadow(glowFilter) = filters[2]
        else {
            Issue.record("expected a drop shadow and a glow")
            return
        }
        #expect(dropShadow.blurX == 4 && dropShadow.angle == 0.5 && dropShadow.distance == 2)
        #expect(dropShadow.strength == 1 && dropShadow.isKnockout && !dropShadow.drawsSource)
        #expect(filters[1] == .blur(x: 2, y: 3))
        #expect(glowFilter.isGlow && glowFilter.isInner && glowFilter.strength == 2)
        #expect(glowFilter.color == SWFColor(red: 255, green: 255, blue: 0, alpha: 128))
    }

    @Test func aDropShadowDrawsATintedCopyUnderTheShape() throws {
        let movie = try SWFDisplayFixture.movie(tags: Self.tags(filters: [Self.dropShadow()]))
        let items = SWFRuntimeFixture.drawItems(SWFScene.build(movie: movie))

        #expect(items.count == 2)
        #expect(items[0].transform.translateX == 40, "2 pixels along angle 0")
        #expect(items[0].colorTransform.multiply == SIMD4(0, 0, 0, 1))
        #expect(items[1].transform.translateX == 0)
        #expect(items[1].colorTransform == .identity)
        #expect(movie.tally.shadowFlags == ["drop shadow": 1])
    }

    @Test func theRunningMovieDrawsTheSameShadowAndBlendMode() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.tags(filters: [Self.dropShadow()], blendMode: 8)
        )
        let items = SWFRuntimeFixture.drawItems(runtime.makeScene())

        #expect(items.count == 2)
        #expect(items.filter(\.isAdditive).count == 2)
        #expect(items[0].colorTransform.add == SIMD4(0, 0, 0, 0))
    }

    @Test func aBlurSpreadsFadedCopiesThatAddUpToNearlyOpaque() {
        let effects = SWFSceneEffects(filters: [.blur(x: 4, y: 2)])
        let items = SWFRuntimeFixture.drawItems(
            SWFScene(
                commands: effects.apply(to: [.draw(item: Self.item(), clipCount: 0)]),
                skippedPlacements: 0
            )
        )

        #expect(items.count == SWFSceneEffects.blurCopies)
        #expect(items[0].transform.translateX == 40, "half of 4 pixels")
        let alpha = items[0].colorTransform.multiply.w
        let total = 1 - pow(1 - alpha, Float(items.count))
        #expect(abs(total - SWFSceneEffects.blurredAlpha) < 1e-4)
    }

    @Test func aShadowThatHidesTheObjectDrawsOnlyTheShadow() {
        var hidden = SWFShadowFilter(color: Self.red)
        hidden.strength = 0.5
        hidden.drawsSource = false
        let commands: [SWFSceneCommand] = [
            .beginClip(masks: [Self.item()]), .draw(item: Self.item(alpha: 0.5), clipCount: 1),
            .endClip(masks: [Self.item()])
        ]

        let drawn = SWFSceneEffects(filters: [.shadow(hidden)]).apply(to: commands)
        let items = SWFRuntimeFixture.drawItems(SWFScene(commands: drawn, skippedPlacements: 0))

        #expect(drawn.count == 3)
        #expect(items.count == 1)
        #expect(items[0].colorTransform.multiply == SIMD4(0, 0, 0, 0.25))
        #expect(items[0].colorTransform.add == SIMD4(1, 0, 0, 0))
    }

    @Test func innerShadowsAndUnknownKindsLeaveTheObjectAsItWas() {
        var inner = SWFShadowFilter(color: Self.red)
        inner.isInner = true
        inner.isGlow = true
        let commands: [SWFSceneCommand] = [.draw(item: Self.item(), clipCount: 0)]

        let effects = SWFSceneEffects(filters: [.shadow(inner), .other(id: 6)])

        #expect(effects.apply(to: commands) == commands)
        #expect(SWFSceneEffects(blendMode: 2).isEmpty)
    }
}
