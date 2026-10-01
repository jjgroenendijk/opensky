// The real `AS2Host`: answers interpreter requests from the runtime display
// tree. The runtime reference is weak to avoid a retain cycle; a host without
// an owner declines everything.

import Foundation

nonisolated public final class SWFRuntimeHost: AS2Host {
    public weak var owner: SWFMovieRuntime?

    public func perform(_ command: AS2TimelineCommand, target: AS2Object) {
        guard let owner, let node = SWFDisplayObject.resolve(target) else {
            return
        }
        owner.perform(command, on: node)
    }

    public func property(_ property: AS2DisplayProperty, of target: AS2Value) -> AS2Value? {
        guard let owner, let node = node(for: target) else {
            return nil
        }
        return owner.displayProperty(property, of: node)
    }

    public func setProperty(
        _ property: AS2DisplayProperty,
        of target: AS2Value,
        to value: AS2Value
    ) -> Bool {
        guard let owner, let node = node(for: target) else {
            return false
        }
        return owner.setDisplayProperty(property, of: node, to: value)
    }

    public func targetPath(of object: AS2Object) -> String? {
        SWFDisplayObject.resolve(object)?.targetPath
    }

    public func object(atPath path: String, from origin: AS2Object) -> AS2Object? {
        guard let owner else {
            return nil
        }
        let start = SWFDisplayObject.resolve(origin) ?? owner.root
        return owner.node(atPath: path, from: start)?.object
    }

    public func specialObject(
        _ kind: AS2SpecialTarget,
        relativeTo origin: AS2Object
    ) -> AS2Object? {
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

    public func member(_ name: String, of object: AS2Object) -> AS2Value? {
        guard let owner, let node = SWFDisplayObject.resolve(object) else {
            return nil
        }
        return owner.member(name, of: node)
    }

    public func setMember(_ name: String, of object: AS2Object, to value: AS2Value) -> Bool {
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
