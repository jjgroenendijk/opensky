public import OpenSkyCrimeInterface

/// What the world adapters use of `CrimeWorldAdapter`.
public protocol CrimeWorldPort: AnyObject {
    func run(_ commands: [CrimeCommand])
}
