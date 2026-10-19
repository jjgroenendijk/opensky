// The weather clock in game hours: a fade lasts its `WTHR` Trans Delta in game hours, and
// the reroll interval follows the climate's volatility. Synthetic fixtures only.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWeather
import Testing

struct WeatherGameTimeTests {
    @Test func aFadeLastsItsTransDeltaInGameHours() throws {
        let system = try WeatherSystem(store: WeatherRuntimeTests.store(), worldspaceFormID: 0x500)
        system.forceWeather(FormID(0x100), transition: .instant)
        // Weather 0x200 has the largest Trans Delta, 0.25 game hours.
        system.forceWeather(FormID(0x200), transition: .timed)
        system.update(hour: 12, elapsedGameHours: 0.125)
        #expect(abs(system.transitionFraction - 0.5) < 1e-4)
        system.update(hour: 12, elapsedGameHours: 0.125)
        #expect(system.transitionFraction == 1)
    }

    @Test func aStillClockHoldsTheFadeHowEverMuchRealTimePasses() throws {
        let system = try WeatherSystem(store: WeatherRuntimeTests.store(), worldspaceFormID: 0x500)
        system.forceWeather(FormID(0x100), transition: .instant)
        system.forceWeather(FormID(0x200), transition: .timed)
        for _ in 0 ..< 1000 {
            system.update(hour: 12)
        }
        #expect(system.transitionFraction == 0)
    }

    @Test func theRerollIntervalFollowsTheClimateVolatility() throws {
        let interval = { (volatility: UInt8?) in
            try WeatherSystem(
                store: WeatherRuntimeTests.store(volatility: volatility), worldspaceFormID: 0x500
            ).rerollInterval
        }
        #expect(try interval(nil) == WeatherSystem.rerollGameHours)
        #expect(try interval(50) == 6)
        #expect(try interval(100) == 3)
        #expect(try interval(0) == nil)
    }

    @Test func aStillClimateNeverRerollsOnItsOwn() throws {
        let system = try WeatherSystem(
            store: WeatherRuntimeTests.store(volatility: 0), worldspaceFormID: 0x500
        )
        let settled = system.currentWeatherID
        for _ in 0 ..< 100 {
            system.update(hour: 12, elapsedGameHours: 1)
        }
        #expect(system.currentWeatherID == settled)
        #expect(system.transitionFraction == 1)
    }
}
