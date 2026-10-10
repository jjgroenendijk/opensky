// The race menu movie bridge over a synthetic runtime: what the engine sends, and
// how the movie's calls change the player's identity.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyMenus
import Testing

@MainActor
private final class RequestLog {
    var requests: [RaceMenuMovieBridge.Request] = []
}

@MainActor
struct RaceMenuMovieBridgeTests {
    private static let model = RaceMenuModel(
        identity: PlayerIdentityState(race: FormID(0x13746), isFemale: false, name: "Prisoner"),
        races: [
            RaceChoice(formID: FormID(0x13746), name: "Nord"),
            RaceChoice(formID: FormID(0x13748), name: "Redguard")
        ],
        limited: false
    )

    @Test func publishSendsRacesSlidersAndTheName() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        var sent: [String: [AS2Value]] = [:]
        for name in ["SetCategoriesList", "SetRaceList", "SetOptionSliders", "SetNameText"] {
            AS2Natives.method(runtime.runtime, on: runtime.root.object, name: name) { context in
                sent[name] = context.arguments
                return .undefined
            }
        }
        RaceMenuMovieBridge.publish(Self.model, runtime: runtime)
        #expect(sent["SetRaceList"] == [
            .string("Nord"), .string(""), .integer(1), .string("Redguard"), .string(""), .integer(0)
        ])
        let sliders = try #require(sent["SetOptionSliders"])
        let sliderRows = Self.model.rows.filter {
            switch $0 {
            case .weight, .slider, .part: true
            default: false
            }
        }
        #expect(sliders.count == sliderRows.count * 8)
        #expect(sliders[2] == .string("ChangeWeight"))
        #expect(sent["SetNameText"] == [.string("Prisoner")])
    }

    @Test func movieCallsBecomeRequests() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        let log = RequestLog()
        RaceMenuMovieBridge.prepare(runtime: runtime) { log.requests.append($0) }
        runtime.callHost("ChangeDoubleMorph", arguments: [.number(0.5), .integer(5)])
        runtime.callHost("ChangeRace", arguments: [.integer(1)])
        runtime.callHost("ChangeName", arguments: [.string("Ada")])
        runtime.callHost("ConfirmDone", arguments: [])
        runtime.callHost("PlaySound", arguments: [.string("UIMenuOK")])
        #expect(log.requests == [.slider(id: 5, value: 0.5), .race(1), .name("Ada"), .done])
    }

    @Test func sliderValuesClampAndARaceIsPickedByPlace() throws {
        var model = Self.model
        let morph = try #require(model.rows.firstIndex(of: .slider(0)))
        model.set(model.rows[morph], to: 3)
        #expect(model.identity.face.morphs[0] == 1)
        model.set(.weight, to: 42)
        #expect(model.identity.face.weight == 42)
        model.selectRace(at: 1)
        #expect(model.identity.race == FormID(0x13748))
        model.selectRace(at: 9)
        #expect(model.identity.race == FormID(0x13748))
    }
}

extension RaceMenuMovieBridgeTests {
    @Test func aMovieWithoutItsPanelListsLeavesTheEngineRowsInCharge() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        #expect(!RaceMenuMovieBridge.listsBuilt(runtime: runtime))
    }
}
