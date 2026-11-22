// The off-screen schedule's world, forwarded to its adapter.

public import OpenSkyAIPackages
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkySessionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension AIWorldAdapter.Worlds {
    var offscreen: AIOffscreenScheduleAdapter {
        AIOffscreenScheduleAdapter(game: packageState.game, cache: offscreenHomes)
    }

    public func offscreenActors() -> [OffscreenActor] {
        offscreen.offscreenActors()
    }

    public func offscreenPlace(
        of location: Package.Location, actor: OffscreenActor
    ) -> OffscreenPlace? {
        offscreen.offscreenPlace(of: location, actor: actor)
    }

    public func isLoaded(_ place: OffscreenPlace) -> Bool {
        offscreen.isLoaded(place)
    }

    public func loadedExit(from cell: FormID) -> OffscreenPlace? {
        offscreen.loadedExit(from: cell)
    }

    public func placeOffscreenActor(_ actor: ReferenceKey, at place: OffscreenPlace) {
        offscreen.placeOffscreenActor(actor, at: place)
    }

    public var offscreenTimescale: Float {
        packageState.game.gameSession?.currentTimescale ?? GameClock.defaultTimescale
    }

    public func offscreenLevel(of actor: OffscreenActor) -> AIProcessLevel {
        OffscreenScheduleCore.level(
            of: actor.place, residentWorldspace: packageState.game.streamer.residentWorldspace
        )
    }

    public func offscreenStopwatch() -> () -> Double {
        let watch = Stopwatch()
        return { watch.milliseconds }
    }
}
