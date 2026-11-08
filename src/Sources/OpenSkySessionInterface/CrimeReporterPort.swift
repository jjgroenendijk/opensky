public import OpenSkyCrimeInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `CrimeReporter`.
public protocol CrimeReporterPort: AnyObject, CrimeReporting {
    func setReportsPlayerCrimes(_ reports: Bool)
    @discardableResult func reportHorseTheft(
        of horse: ReferenceKey,
        owner: ReferenceOwner?,
        by actor: ReferenceKey
    ) -> CrimeOutcome
    func verdict(on reference: ReferenceKey, item: FormID?, by actor: ReferenceKey)
        -> OwnershipVerdict
}

/// The default arguments a protocol requirement cannot carry.
extension CrimeReporterPort {
    @discardableResult public func reportHorseTheft(
        of horse: ReferenceKey,
        owner: ReferenceOwner?
    ) -> CrimeOutcome {
        reportHorseTheft(of: horse, owner: owner, by: .player)
    }
}
