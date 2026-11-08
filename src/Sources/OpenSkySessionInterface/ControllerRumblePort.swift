public import OpenSkyAudio
public import OpenSkyFormatsESM
public import OpenSkyMagicInterface

/// What the world adapters use of `ControllerRumble`.
public protocol ControllerRumblePort: AnyObject {
    var lastRumble: ShoutRumble? { get }
    func shout(words: Int)
    var soundMotors: SoundRumble { get }
    func weapon(_ rumble: Weapon.Rumble)
    var lastRumbleCause: String? { get }

    func follow(_ motors: SoundRumble)
}
