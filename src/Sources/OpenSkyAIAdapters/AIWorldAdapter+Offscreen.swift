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

    public func offscreenArrival(_ actor: ReferenceKey) -> OffscreenActor? {
        offscreen.offscreenArrival(actor)
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
        OffscreenReads(owner: self).offscreenTimescale
    }

    public func offscreenLevel(of actor: OffscreenActor) -> AIProcessLevel {
        OffscreenReads(owner: self).offscreenLevel(of: actor)
    }

    public func offscreenStopwatch() -> () -> Double {
        let watch = Stopwatch()
        return { watch.milliseconds }
    }
}

extension AIWorldAdapter.Worlds {
    /// Reads the offscreen timescale and an actor's process level.
    struct OffscreenReads {
        let owner: AIWorldAdapter.Worlds

        var offscreenTimescale: Float {
            let packageState = owner.packageState
            return packageState.game.gameSession?.currentTimescale ?? GameClock.defaultTimescale
        }

        func offscreenLevel(of actor: OffscreenActor) -> AIProcessLevel {
            let packageState = owner.packageState
            return OffscreenScheduleCore.level(
                of: actor.place, residentWorldspace: packageState.game.streamer.residentWorldspace
            )
        }
    }
}
