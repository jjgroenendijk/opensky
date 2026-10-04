// The name a readout shows for one resident actor, kept as parts and formatted
// only when read. Per-frame rosters copy it; only panels and overlays read the text.

import OpenSkyFormatsESM

nonisolated public struct ActorLabel: Equatable, Sendable {
    private let fixed: String?
    private let key: ReferenceKey?
    private let base: FormID?

    /// A label that reads `name` as given.
    public init(_ name: String) {
        fixed = name
        key = nil
        base = nil
    }

    /// A label that reads "key (base form)".
    public init(key: ReferenceKey, base: FormID) {
        fixed = nil
        self.key = key
        self.base = base
    }

    /// Never empty, so a readout line always names something.
    public var text: String {
        if let fixed {
            return fixed
        }
        guard let key, let base else { return "—" }
        return "\(key.description) (base \(base))"
    }
}
