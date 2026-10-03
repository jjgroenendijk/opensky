// Effective enabled state through the `XESP` enable-parent chain. The CK wiki says
// Enable and Disable on a child have no effect, so a resolved parent decides alone.
// See docs/engine/traps.md.

import Foundation
import OpenSkyFormatsESM

nonisolated extension RuntimeReferenceEntry {
    /// The `XESP` link of the placed record, if any.
    public var enableParent: EnableParent? {
        switch record {
        case let .reference(reference): reference.enableParent
        case let .actor(actor): actor.enableParent
        }
    }
}

/// Resolves effective enabled state. Pure: entries and deltas in, a flag out.
nonisolated public struct EnableParentResolver {
    /// A chain longer than this is treated as broken. Vanilla chains are short.
    public static let maximumDepth = 16

    private let parent: (FormID) -> RuntimeReferenceEntry?
    private let delta: (ReferenceKey) -> ReferenceStateDelta?

    /// - Parameter parent: finds a parent's entry by the FormID its child names.
    public init(
        delta: @escaping (ReferenceKey) -> ReferenceStateDelta?,
        parent: @escaping (FormID) -> RuntimeReferenceEntry?
    ) {
        self.delta = delta
        self.parent = parent
    }

    public init(
        deltas: [ReferenceKey: ReferenceStateDelta],
        parent: @escaping (FormID) -> RuntimeReferenceEntry?
    ) {
        self.init(delta: { deltas[$0] }, parent: parent)
    }

    /// The reference's own state, or its parent's (flipped by the opposite flag)
    /// when the parent can be found. An unresolved parent leaves the own state.
    public func isEnabled(_ entry: RuntimeReferenceEntry) -> Bool {
        isEnabled(
            key: entry.key,
            initiallyDisabled: Self.startsDisabled(entry),
            link: entry.enableParent
        )
    }

    /// The same for a placement that has no index entry, such as a `PHZD`.
    public func isEnabled(
        key: ReferenceKey, initiallyDisabled: Bool, link: EnableParent?
    ) -> Bool {
        isEnabled(key: key, initiallyDisabled: initiallyDisabled, link: link, depth: 0)
    }

    /// True when the entry names a parent this resolver cannot find.
    public func hasUnresolvedParent(_ entry: RuntimeReferenceEntry) -> Bool {
        guard let link = entry.enableParent else { return false }
        return parent(link.parent) == nil
    }

    private func isEnabled(
        key: ReferenceKey, initiallyDisabled: Bool, link: EnableParent?, depth: Int
    ) -> Bool {
        guard
            let link,
            depth < Self.maximumDepth,
            let parentEntry = parent(link.parent),
            parentEntry.key != key
        else {
            return delta(key)?.component(ReferenceEnableState.self)?.isEnabled
                ?? !initiallyDisabled
        }
        let parentEnabled = isEnabled(
            key: parentEntry.key,
            initiallyDisabled: Self.startsDisabled(parentEntry),
            link: parentEntry.enableParent,
            depth: depth + 1
        )
        return link.isOppositeOfParent ? !parentEnabled : parentEnabled
    }

    private static func startsDisabled(_ entry: RuntimeReferenceEntry) -> Bool {
        switch entry.record {
        case let .reference(reference): reference.isInitiallyDisabled
        case let .actor(actor): actor.isInitiallyDisabled
        }
    }
}
