public import OpenSkyConditions
public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `CrimeCoordinator`.
public protocol CrimePort: CrimeArrestSession {
    associatedtype CrimeReporter: CrimeReporterPort
    func clearPrison()
    func conditionResolution(owning references: [ReferenceKey]) -> CrimeConditionResolution
    func crimeActor(_ key: ReferenceKey) -> CrimeActor
    func crimeOwner(of key: ReferenceKey) -> ReferenceOwner?
    var crimeTexts: CrimeTexts { get }
    var isPlayerPursued: Bool { get }
    var isPlayerTrespassing: Bool { get }
    var isPlayerWarnedToLeave: Bool { get }
    var jailStay: JailStay? { get }
    func killStatus(of victim: ReferenceKey, by killer: ReferenceKey?) -> StoryKillStatus
    func ownershipVerdict(on reference: ReferenceKey) -> OwnershipVerdict
    func reportAssault(on target: ReferenceKey, wasHostile: Bool, aggressor: ReferenceKey)
    @discardableResult func reportLockpicking(of lock: ReferenceKey) -> Int32
    func reportMurder(of victim: ReferenceKey)
    var reporter: CrimeReporter? { get }
    func restoreJailStay(_ stay: JailStay?)
    var scriptedOwner: ((ReferenceKey) -> ReferenceOwner??)? { get set }
    var scriptedOwnerRevision: (() -> UInt64)? { get set }
    func theftBounty(of item: FormID, from reference: ReferenceKey) -> Int32
    func advanceTrespass(by seconds: Double)
    @discardableResult func serveSentence() -> Bool

    func advanceFavour()

    func advanceReports()

    func advanceJail()

    func advanceGuardResponse() -> [CrimeCommand]
}

/// The default arguments a protocol requirement cannot carry.
extension CrimePort {
    @discardableResult public func conditionResolution() -> CrimeConditionResolution {
        conditionResolution(owning: [])
    }

    public func reportAssault(on target: ReferenceKey, wasHostile: Bool) {
        reportAssault(on: target, wasHostile: wasHostile, aggressor: .player)
    }

    public func advanceTrespass() {
        advanceTrespass(by: 0)
    }
}
