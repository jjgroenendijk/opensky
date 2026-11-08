// A material's animation tracks as cache bytes: a track count, then per track the
// target, the clock, and the key times and values.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated extension ModelCacheCodec {
    static func encode(_ animation: MaterialAnimation?, into out: inout CachePayloadWriter) {
        let tracks = animation?.tracks ?? []
        out.value(UInt32(tracks.count))
        for track in tracks {
            out.value(track.target.rawValue)
            out.value(track.clock.cycle.rawValue)
            let clock = track.clock
            out.value(SIMD4(clock.frequency, clock.phase, clock.startTime, clock.stopTime))
            out.array(track.times)
            out.array(track.values)
        }
    }

    static func materialAnimation(_ input: inout CachePayloadReader) throws -> MaterialAnimation? {
        let count = try Int(input.value(UInt32.self))
        guard count > 0 else { return nil }
        guard count <= 64 else { throw CachePayloadError.badCount(count) }
        var tracks: [MaterialAnimation.Track] = []
        for _ in 0 ..< count {
            let rawTarget = try input.value(UInt8.self)
            let rawCycle = try input.value(UInt16.self)
            let timing = try input.value(SIMD4<Float>.self)
            let times = try input.array(Float.self)
            let values = try input.array(SIMD3<Float>.self)
            guard
                let target = MaterialAnimation.Target(rawValue: rawTarget),
                let cycle = ControllerClock.Cycle(rawValue: rawCycle)
            else { throw CachePayloadError.badCount(Int(rawTarget)) }
            let clock = ControllerClock(
                cycle: cycle, frequency: timing.x, phase: timing.y,
                startTime: timing.z, stopTime: timing.w
            )
            tracks.append(MaterialAnimation.Track(
                target: target, clock: clock, times: times, values: values
            ))
        }
        return MaterialAnimation(tracks: tracks)
    }
}
