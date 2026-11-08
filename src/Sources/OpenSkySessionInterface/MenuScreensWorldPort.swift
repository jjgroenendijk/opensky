/// What the world adapters use of `MenuScreensWorldAdapter`.
public protocol MenuScreensWorldPort: AnyObject {
    func passTime(hours: Int, sleeping: Bool)
}
