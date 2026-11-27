public import OpenSkyMenusInterface

/// What the world adapters use of `SubtitleCoordinator`.
public protocol SubtitlePort: AnyObject {
    func apply(_ settings: SubtitleSettings)
    @discardableResult func say(
        _ text: String,
        kind: SubtitleKind,
        seconds: Double,
        now: Double
    ) -> Bool
    /// A `.general` line, shown only when its speaker stands near enough.
    @discardableResult func sayAround(
        _ text: String, placement: SubtitlePlacement, seconds: Double, now: Double
    ) -> Bool
    var settings: SubtitleSettings { get }
    func advance(to now: Double)
}
