public import OpenSkyMenusInterface

/// What the world adapters use of `SubtitleCoordinator`.
public protocol SubtitlePort: AnyObject {
    func apply(_ settings: SubtitleSettings)
    @discardableResult func say(
        _ text: String,
        kind: SubtitleKind,
        seconds: Double,
        now: Double,
        placement: SubtitlePlacement
    ) -> Bool
    var settings: SubtitleSettings { get }
    func advance(to now: Double)
}

/// The default arguments a protocol requirement cannot carry.
extension SubtitlePort {
    /// A line whose speaker is near, such as one in the player's own conversation.
    @discardableResult public func say(
        _ text: String, kind: SubtitleKind, seconds: Double, now: Double
    ) -> Bool {
        say(text, kind: kind, seconds: seconds, now: now, placement: .near)
    }
}
