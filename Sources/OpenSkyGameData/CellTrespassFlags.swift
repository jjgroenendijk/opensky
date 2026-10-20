// The two CELL flags trespass reads. UESP "Skyrim Mod:Mod File Format/CELL": DATA
// `0x20` Public Area and record-header `0x20000` Off Limits. See docs/engine/crime.md.

/// How a cell treats a visitor its owner did not invite.
nonisolated public struct CellTrespassFlags: Equatable, Sendable {
    /// Anyone may be here, such as an inn: no trespass.
    public var isPublicArea = false
    /// Being seen here costs a bounty at once, with no warning.
    public var isOffLimits = false

    public init(isPublicArea: Bool = false, isOffLimits: Bool = false) {
        self.isPublicArea = isPublicArea
        self.isOffLimits = isOffLimits
    }
}
