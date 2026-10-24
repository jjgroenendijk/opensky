// A session scope built over synthetic stores builds every coordinator from
// its initializer, with no renderer, no streamer, and no late setter.

@testable import OpenSky
@testable import OpenSkyCells
import OpenSkyCrime
import OpenSkyFormatsESM
import Testing

@MainActor
struct GameSessionScopeTests {
    private static func scope() -> GameSessionScope {
        let data = WorldDataStores(
            scriptFormIDResolver: FormIDResolver(pluginName: "Skyrim.esm", masters: [])
        )
        return GameSessionScope(
            worldData: data, cellRunner: nil, gameSession: nil, services: GameAppServices()
        )
    }

    @Test func everyCoordinatorBuildsFromTheScope() {
        let scope = Self.scope()
        #expect(scope.worldData != nil)
        _ = scope.actorValues
        _ = scope.factions
        _ = scope.perception
        _ = scope.perks
        _ = scope.progression
        _ = scope.combat
        _ = scope.ragdoll
        _ = scope.packages
        _ = scope.idleWorld.idles
        _ = scope.player
        #expect(scope.streamer == nil)
    }

    @Test func crimeReportsStoryEventsToTheScopesStoryWorld() {
        let scope = Self.scope()
        #expect((scope.crime.storyEvents as AnyObject?) === scope.storyWorld)
    }
}
