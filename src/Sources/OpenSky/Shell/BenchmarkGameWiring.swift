// Connects each new game window to the benchmark host.

import AppKit
import OpenSkyWorld
import OpenSkyWorldInterface

/// Starts the pending tour once the new game's session starts.
struct BenchmarkGameWiring {
    init(_ host: BenchmarkRunHost, game: GameViewController, window: NSWindow) {
        game.onSessionStart = { [weak host, weak window] session in
            // Muted before the first frame, so the world's first sounds stay silent too.
            if host?.pending?.muted == true {
                session.audio.outputMuted = true
            }
            guard let window else { return }
            host?.attach(tour: session.benchmarkWorld, window: window)
        }
    }
}
