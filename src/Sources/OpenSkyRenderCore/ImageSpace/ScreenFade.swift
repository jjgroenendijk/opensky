// The fader `Game.FadeOutGame` drives: wait, then fade the frame to black or white, or
// back. Pure. See docs/engine/papyrus-session-natives.md.

import simd

nonisolated public struct ScreenFade: Equatable, Sendable {
    public private(set) var colour = SIMD3<Float>.zero
    /// How much of the frame the colour covers, from 0 to 1.
    public private(set) var cover: Float = 0
    private var from: Float = 0
    private var target: Float = 0
    private var delay: Float = 0
    private var duration: Float = 0
    private var elapsed: Float = 0

    public init() {}

    /// A fade in starts covered, so its wait shows the colour, as the wiki example says.
    public mutating func start(fadingOut: Bool, black: Bool, delay: Float, duration: Float) {
        colour = black ? .zero : SIMD3(repeating: 1)
        from = fadingOut ? cover : 1
        target = fadingOut ? 1 : 0
        self.delay = Self.seconds(delay)
        self.duration = Self.seconds(duration)
        elapsed = 0
        cover = from
        advance(0)
    }

    public mutating func advance(_ deltaTime: Float) {
        elapsed += Self.seconds(deltaTime)
        let progress = duration > 0 ? (elapsed - delay) / duration : (elapsed >= delay ? 1 : 0)
        cover = simd_mix(from, target, simd_clamp(progress, 0, 1))
    }

    /// Whether the fade still changes the cover.
    public var isRunning: Bool {
        elapsed < delay + duration
    }

    /// The colour in RGB and the cover in `w`, as `ImageSpaceParameters.fade` takes it.
    public var fade: SIMD4<Float> {
        SIMD4(colour, cover)
    }

    private static func seconds(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}
