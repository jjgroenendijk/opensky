/// What the world adapters use of `IdleWorldAdapter`.
public protocol IdleWorldPort: AnyObject {
    var idles: any IdlePort { get }
}
