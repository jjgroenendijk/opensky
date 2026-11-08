public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What the world adapters use of `LockCoordinator`.
public protocol LockPort: AnyObject, Sendable {
    func difficulty(of state: ReferenceLockState) -> LockDifficulty
    func gate(_ target: InteractionTarget) -> InventoryResult<ActivationRefusal?>
    func lock(of interaction: PlacedInteraction) -> ResolvedLock?
    var lockpickItem: FormID? { get }
    var selectedInteraction: PlacedInteraction? { get }
    func setLocked(
        _ interaction: PlacedInteraction,
        locked: Bool
    ) -> InventoryResult<LockActionOutcome>

    func beginLockpicking(_ target: InteractionTarget) throws(LockpickingRefusal)
    func cancelLockpicking() -> InventoryResult<[LockpickingEvent]>
    func closeLockpicking()
    var lastOutcome: LockpickingOutcome? { get }
    @discardableResult func record(_ outcome: LockActionOutcome) -> LockActionOutcome
    func refusalNotice(level: UInt8, pursued: Bool) -> LockNotice?
    var session: LockpickingSession? { get }
    var sessionTarget: InteractionTarget? { get }
    func stepLockpicking(
        _ seconds: Float,
        input: LockpickingInput
    ) -> InventoryResult<[LockpickingEvent]>
    var texts: LockTexts { get }
}

/// The default arguments a protocol requirement cannot carry.
extension LockPort {
    @discardableResult public func refusalNotice(level: UInt8) -> LockNotice? {
        refusalNotice(level: level, pursued: false)
    }
}
