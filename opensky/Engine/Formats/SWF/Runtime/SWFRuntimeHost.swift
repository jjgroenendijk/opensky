// The real `AS2Host` (milestone 8.3.2 phase 2), replacing `AS2RecordingHost`.
// Everything the interpreter cannot answer from its own object model —
// timeline control, numbered display properties, target paths, `_root` /
// `_parent` / `_level0`, and members of host-backed objects — lands here and is
// answered from the runtime display tree.
//
// The back-reference to the runtime is weak: `AS2Runtime` holds its host
// strongly and `SWFMovieRuntime` holds the `AS2Runtime`, so a strong pair would
// never be freed. A host with no owner declines everything, which is exactly
// the `AS2RecordingHost` behavior the interpreter already tolerates.

import Foundation

nonisolated final class SWFRuntimeHost: AS2Host {
    weak var owner: SWFMovieRuntime?

    func perform(_ command: AS2TimelineCommand, target: AS2Object) {
        guard let owner, let node = SWFDisplayObject.resolve(target) else {
            return
        }
        owner.perform(command, on: node)
    }

    func property(_ property: AS2DisplayProperty, of target: AS2Value) -> AS2Value? {
        guard let owner, let node = node(for: target) else {
            return nil
        }
        return owner.displayProperty(property, of: node)
    }

    func setProperty(
        _ property: AS2DisplayProperty,
        of target: AS2Value,
        to value: AS2Value
    ) -> Bool {
        guard let owner, let node = node(for: target) else {
            return false
        }
        return owner.setDisplayProperty(property, of: node, to: value)
    }

    func targetPath(of object: AS2Object) -> String? {
        SWFDisplayObject.resolve(object)?.targetPath
    }

    func object(atPath path: String, from origin: AS2Object) -> AS2Object? {
        guard let owner else {
            return nil
        }
        let start = SWFDisplayObject.resolve(origin) ?? owner.root
        return owner.node(atPath: path, from: start)?.object
    }

    func specialObject(_ kind: AS2SpecialTarget, relativeTo origin: AS2Object) -> AS2Object? {
        guard let owner else {
            return nil
        }
        let node = SWFDisplayObject.resolve(origin)
        switch kind {
        case .root, .level0:
            return (node?.rootObject ?? owner.root).object
        case .parent:
            return node?.parent?.object
        }
    }

    func member(_ name: String, of object: AS2Object) -> AS2Value? {
        guard let owner, let node = SWFDisplayObject.resolve(object) else {
            return nil
        }
        return owner.member(name, of: node)
    }

    func setMember(_ name: String, of object: AS2Object, to value: AS2Value) -> Bool {
        guard let owner, let node = SWFDisplayObject.resolve(object) else {
            return false
        }
        return owner.setMember(name, of: node, to: value)
    }

    /// `ActionGetProperty`/`ActionSetProperty` push the raw stack operand, which
    /// is either the display object itself or a path string.
    private func node(for target: AS2Value) -> SWFDisplayObject? {
        guard let owner else {
            return nil
        }
        switch target {
        case let .object(object):
            return SWFDisplayObject.resolve(object)
        case let .string(path):
            return owner.node(atPath: path, from: owner.root)
        default:
            return nil
        }
    }
}
