public import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `ExplosionRuntime`.
public protocol ExplosionRuntimePort: AnyObject {
    @discardableResult func detonate(
        _ spec: ExplosionSpec,
        at position: SIMD3<Float>,
        cause: ExplosionCause,
        source: FormID?
    ) -> ExplosionReport
    func spec(itemLink id: FormID?) -> ExplosionSpec?
    func spec(for key: ReferenceKey) -> ExplosionSpec?

    func advance(_ seconds: Float)
    var debris: [DebrisPiece] { get }
    var itemPlugin: String { get }
}

/// The default arguments a protocol requirement cannot carry.
extension ExplosionRuntimePort {
    @discardableResult public func detonate(
        _ spec: ExplosionSpec,
        at position: SIMD3<Float>,
        cause: ExplosionCause
    ) -> ExplosionReport {
        detonate(spec, at: position, cause: cause, source: nil)
    }
}
