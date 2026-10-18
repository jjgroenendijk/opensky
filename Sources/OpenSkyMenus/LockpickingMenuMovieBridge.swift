// The measured AS2 contract of `Interface\lockpickingmenu.swf`. The movie draws the
// skill and lock panel and the button bar; the lock itself is the overlay scene.
// See docs/engine/locks.md#lockpicking-menu.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyInventoryInterface

/// The panel text `SetLockInfo` shows.
nonisolated public struct LockpickingMovieInfo: Equatable, Sendable {
    public var skillLevel: Int
    /// 0 to 1 towards the next skill level.
    public var skillProgress: Float
    /// The level's name from the load order, such as "Adept".
    public var lockLevel: String
    public var picksRemaining: Int32

    public init(skillLevel: Int, skillProgress: Float, lockLevel: String, picksRemaining: Int32) {
        self.skillLevel = skillLevel
        self.skillProgress = skillProgress
        self.lockLevel = lockLevel
        self.picksRemaining = picksRemaining
    }
}

nonisolated public enum LockpickingMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\lockpickingmenu.swf"
    public static let sinkHostFunctions = ["PlaySound", "myLog"]
    /// A full lock turn, in degrees, for the movie's debug readout.
    static let lockTurnDegrees: Double = 90

    /// The root `InitExtensions` registers the callbacks; `SetPlatform` lays out the buttons.
    public static func activate(runtime: SWFMovieRuntime) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        runtime.callMovie("InitExtensions")
        runtime.callMovie(
            "SetPlatform",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
    }

    /// `SetLockInfo(skill, nextSkill, percent, lockLevel, picks)`.
    public static func publish(_ info: LockpickingMovieInfo, runtime: SWFMovieRuntime) {
        runtime.callMovie("SetLockInfo", arguments: [
            .integer(info.skillLevel),
            .integer(info.skillLevel + 1),
            .number(Double(min(max(info.skillProgress, 0), 1)) * 100),
            .string(info.lockLevel),
            .integer(Int(info.picksRemaining))
        ])
    }

    /// The debug readout: pick and lock angles in degrees, pick health in percent.
    public static func publish(_ frame: LockpickingMenuPresentation, runtime: SWFMovieRuntime) {
        runtime.callMovie("UpdatePickAngle", arguments: [.number(Double(frame.pickAngle))])
        runtime.callMovie(
            "UpdateLockAngle",
            arguments: [.number(Double(frame.lockRotation) * lockTurnDegrees)]
        )
        runtime.callMovie("UpdatePickHealth", arguments: [.number(Double(frame.pickHealth) * 100)])
    }
}
