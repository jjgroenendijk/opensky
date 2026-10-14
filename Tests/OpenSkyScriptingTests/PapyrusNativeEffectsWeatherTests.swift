// The `VisualEffect`, `EffectShader`, `ImageSpaceModifier`, and `Weather` natives
// over fakes of their two ports.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

private struct PlayingEffect {
    let effect: ReferenceKey
    let target: ReferenceKey
    let duration: Float?
}

@MainActor
private final class FakeEffects: PapyrusEffectPresenting {
    var playing: [PlayingEffect] = []
    var modifiers: [ReferenceKey: Bool] = [:]

    func playEffect(_ effect: ReferenceKey, on target: ReferenceKey, duration: Float?) -> Bool {
        playing.append(PlayingEffect(effect: effect, target: target, duration: duration))
        return true
    }

    func stopEffect(_ effect: ReferenceKey, on target: ReferenceKey) -> Bool {
        let before = playing.count
        playing.removeAll { $0.effect == effect && $0.target == target }
        return playing.count < before
    }

    func applyImageSpaceModifier(_ modifier: ReferenceKey, strength: Float, held: Bool) -> Bool {
        modifiers[modifier] = held
        return true
    }

    func removeImageSpaceModifier(_ modifier: ReferenceKey) {
        modifiers[modifier] = nil
    }
}

@MainActor
private final class FakeSky: PapyrusWeatherControlling {
    var currentWeather: ReferenceKey?
    var held = false
    var codes: [ReferenceKey: Int32] = [:]

    func setWeather(_ weather: ReferenceKey, held: Bool, instant _: Bool) -> Bool {
        guard codes[weather] != nil else { return false }
        currentWeather = weather
        self.held = held
        return true
    }

    func releaseWeather() {
        held = false
    }

    func candidateWeathers() -> [ReferenceKey] {
        codes.keys.sorted()
    }

    func classification(of weather: ReferenceKey) -> Int32? {
        codes[weather]
    }
}

@MainActor
struct PapyrusNativeEffectsWeatherTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    private func call(
        _ fixture: Fixture, _ script: String, _ name: String,
        on receiver: PapyrusObjectHandle?, _ arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            script, name, receiver: receiver, arguments: arguments, returnType: returnType
        ))
    }

    @Test func effectsPlayOnTheirTargetUntilStopped() throws {
        let fixture = try Fixture.make()
        let effects = FakeEffects()
        fixture.session.bridge.effectPresenter = effects
        let effect = fixture.handle(Fixture.doorID)
        let lever: [PapyrusValue] = [.object(fixture.receiver)]

        #expect(call(fixture, "VisualEffect", "Play", on: effect, lever) == .returned(.none))
        #expect(call(fixture, "EffectShader", "Play", on: effect, lever + [.float(4)])
            == .returned(.none))
        #expect(effects.playing.map(\.duration) == [nil, 4])
        #expect(effects.playing.allSatisfy { $0.target == fixture.key })
        #expect(call(fixture, "VisualEffect", "Stop", on: effect, lever) == .returned(.none))
        #expect(effects.playing.isEmpty)
        #expect(PapyrusWorldFixture.isInvalidArguments(
            call(fixture, "VisualEffect", "Play", on: effect)
        ))
    }

    @Test func aCrossFadeIsHeldUntilRemoved() throws {
        let fixture = try Fixture.make()
        let effects = FakeEffects()
        fixture.session.bridge.effectPresenter = effects
        let modifier = Fixture.key(Fixture.doorID)
        let handle = fixture.handle(Fixture.doorID)

        _ = call(fixture, "ImageSpaceModifier", "Apply", on: fixture.receiver)
        #expect(effects.modifiers[fixture.key] == false)
        _ = call(fixture, "ImageSpaceModifier", "ApplyCrossFade", on: handle)
        #expect(effects.modifiers[modifier] == true)
        _ = call(fixture, "ImageSpaceModifier", "RemoveCrossFade", on: nil)
        #expect(effects.modifiers[modifier] == nil)
        _ = call(fixture, "ImageSpaceModifier", "Remove", on: fixture.receiver)
        #expect(effects.modifiers.isEmpty)
    }

    @Test func weatherIsSetHeldReleasedAndFound() throws {
        let fixture = try Fixture.make()
        let sky = FakeSky()
        let rainy = Fixture.key(Fixture.doorID)
        sky.codes = [rainy: 2, fixture.key: 0]
        fixture.session.bridge.weather = sky
        let rain = fixture.handle(Fixture.doorID)

        #expect(call(fixture, "Weather", "SetActive", on: rain, [.boolean(true)])
            == .returned(.none))
        #expect(sky.held)
        #expect(call(
            fixture,
            "Weather",
            "GetCurrentWeather",
            on: nil,
            returnType: .object("Weather")
        )
            == .returned(.object(rain)))
        #expect(call(fixture, "Weather", "ReleaseOverride", on: nil) == .returned(.none))
        #expect(!sky.held)
        #expect(call(fixture, "Weather", "FindWeather", on: nil, [.integer(2)])
            == .returned(.object(rain)))
        #expect(call(fixture, "Weather", "GetClassification", on: rain, returnType: .integer)
            == .returned(.integer(2)))
    }

    @Test func weatherWithoutASkyFails() throws {
        let fixture = try Fixture.make()
        #expect(PapyrusWorldFixture.isInvalidArguments(
            call(fixture, "Weather", "ReleaseOverride", on: nil)
        ))
    }
}
