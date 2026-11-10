// Float sentinels shared by NIF blocks. Layout: docs/formats/nif.md.

nonisolated enum NIFFloat {
    /// nif.xml `#INV_FLT#`: the pose value is unset.
    static let invalid: Float = -3.402823466e+38
}
