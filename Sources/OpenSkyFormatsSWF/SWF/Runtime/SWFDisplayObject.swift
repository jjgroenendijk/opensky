// The mutable runtime display list: a tree ActionScript can move, hide, and
// re-parent. One node is one placed character; a clip node also owns a timeline
// and a playhead. `SWFDisplayHandle` links a node and its `AS2Object` weakly,
// so script objects cannot keep a removed clip alive (SWF spec v19, ch. 3, 13).

import Foundation

/// The back-pointer stored in `AS2Object.hostPayload`. Weak, because the
/// display object owns its `AS2Object` and a strong pair would never be freed.
nonisolated public final class SWFDisplayHandle {
    public weak var target: SWFDisplayObject?

    public init(_ target: SWFDisplayObject) {
        self.target = target
    }
}

/// One node of the runtime display list.
nonisolated public final class SWFDisplayObject {
    /// What the node draws. A clip draws nothing itself; its children do.
    public enum Content: Equatable, Sendable {
        /// A sprite instance, or the root when the id is nil.
        case clip(UInt16?)
        case shape(UInt16)
        case staticText(UInt16)
        case editText(UInt16)
    }

    public let content: Content
    /// The ActionScript face of this node. Its `hostPayload` is a
    /// `SWFDisplayHandle` pointing back here and its `typeOverride` is
    /// `"movieclip"` for clips.
    public let object: AS2Object

    public weak var parent: SWFDisplayObject?
    public var depth: UInt16
    /// PlaceObject2 `Name` — the instance name ActionScript addresses.
    public var name: String?
    public var matrix = SWFMatrix.identity
    public var colorTransform = SWFColorTransform.identity
    /// PlaceObject `ClipDepth`: this node masks depths (depth, clipDepth].
    public var clipDepth: UInt16?
    public var isVisible = true
    /// Runtime text for an edit-text node, overriding the character's
    /// `InitialText`.
    public var textOverride: String?
    /// CLIPACTIONS handlers the placement attached, if any.
    public var clipActions: SWFClipActions?

    /// The sprite's frames; nil for a leaf.
    public let timeline: SWFTimeline?
    /// Declared frame count, at least 1 for a clip and 0 for a leaf.
    public let frameCount: Int
    /// Zero-based playhead. -1 until the first frame executes.
    public var currentFrame = -1
    public var isPlaying = true

    private var byDepth: [UInt16: SWFDisplayObject] = [:]
    private var sortedChildren: [SWFDisplayObject]?

    /// Guard against a malformed tree built by bytecode: no node may sit deeper
    /// than this below the root.
    public static let maximumTreeDepth = 32

    public init(
        content: Content,
        depth: UInt16 = 0,
        timeline: SWFTimeline? = nil,
        frameCount: Int = 0
    ) {
        self.content = content
        self.depth = depth
        self.timeline = timeline
        self.frameCount = frameCount
        object = AS2Object()
        if case .clip = content {
            object.typeOverride = "movieclip"
        }
        object.hostPayload = SWFDisplayHandle(self)
    }

    /// The display object an ActionScript value refers to, or nil when the
    /// value is not a display object.
    public static func resolve(_ object: AS2Object?) -> SWFDisplayObject? {
        guard let handle = object?.hostPayload as? SWFDisplayHandle else {
            return nil
        }
        return handle.target
    }

    public var characterId: UInt16? {
        switch content {
        case let .clip(id): id
        case let .shape(id), let .staticText(id), let .editText(id): id
        }
    }

    public var isClip: Bool {
        if case .clip = content {
            return true
        }
        return false
    }

    /// Children in depth-ascending order — the paint order.
    public var children: [SWFDisplayObject] {
        if let sortedChildren {
            return sortedChildren
        }
        let sorted = byDepth.values.sorted { $0.depth < $1.depth }
        sortedChildren = sorted
        return sorted
    }

    public var childCount: Int {
        byDepth.count
    }

    public func child(atDepth depth: UInt16) -> SWFDisplayObject? {
        byDepth[depth]
    }

    /// Instance-name lookup. Ties break on the lowest depth so the result is
    /// stable when a movie reuses a name.
    public func child(named name: String) -> SWFDisplayObject? {
        children.first { $0.name == name }
    }

    /// Places `child` at `depth`, replacing whatever occupied it.
    public func addChild(_ child: SWFDisplayObject, atDepth depth: UInt16) {
        if let previous = byDepth[depth] {
            previous.parent = nil
            unbindName(of: previous)
        }
        child.depth = depth
        child.parent = self
        byDepth[depth] = child
        sortedChildren = nil
        bindName(of: child)
    }

    @discardableResult
    public func removeChild(atDepth depth: UInt16) -> SWFDisplayObject? {
        guard let removed = byDepth.removeValue(forKey: depth) else {
            return nil
        }
        removed.parent = nil
        unbindName(of: removed)
        sortedChildren = nil
        return removed
    }

    /// A named instance is a property of its parent timeline, which is what
    /// makes both `panel._x` and a bare `panel` resolve from a frame action.
    /// Hidden from enumeration, matching how Flash reports a timeline's own
    /// variables.
    public func bindName(of child: SWFDisplayObject) {
        guard let name = child.name, !name.isEmpty else {
            return
        }
        object.define(.object(child.object), for: name, flags: .dontEnumerate)
    }

    private func unbindName(of child: SWFDisplayObject) {
        guard
            let name = child.name,
            object.ownProperty(name)?.value.objectValue === child.object
        else {
            return
        }
        object.removeProperty(name)
    }

    /// Moves an existing child to a new depth, swapping with any occupant.
    public func swapChild(_ child: SWFDisplayObject, toDepth depth: UInt16) {
        guard child.parent === self, child.depth != depth else {
            return
        }
        let origin = child.depth
        let occupant = byDepth[depth]
        byDepth[origin] = occupant
        occupant?.depth = origin
        byDepth[depth] = child
        child.depth = depth
        if occupant == nil {
            byDepth[origin] = nil
        }
        sortedChildren = nil
    }

    /// Total nodes in this subtree, including self. Bounded by the tree-depth
    /// guard so a cycle cannot hang the walk.
    public func nodeCount(remainingDepth: Int = SWFDisplayObject.maximumTreeDepth) -> Int {
        guard remainingDepth > 0 else {
            return 1
        }
        return children.reduce(1) { $0 + $1.nodeCount(remainingDepth: remainingDepth - 1) }
    }

    /// The topmost ancestor — `_root` for anything in one movie's tree.
    public var rootObject: SWFDisplayObject {
        var current = self
        var steps = 0
        while let parent = current.parent, steps < SWFDisplayObject.maximumTreeDepth {
            current = parent
            steps += 1
        }
        return current
    }

    /// `ActionTargetPath` (0x45) and the `_target` property: the slash path from
    /// the root, which is `"/"` for the root itself.
    public var targetPath: String {
        var components: [String] = []
        var current: SWFDisplayObject? = self
        var steps = 0
        while let node = current, node.parent != nil, steps < SWFDisplayObject.maximumTreeDepth {
            components.append(node.name ?? "instance\(node.depth)")
            current = node.parent
            steps += 1
        }
        return components.isEmpty ? "/" : "/" + components.reversed().joined(separator: "/")
    }
}
