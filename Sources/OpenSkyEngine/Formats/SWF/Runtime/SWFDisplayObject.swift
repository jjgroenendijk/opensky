// The mutable runtime display list (milestone 8.3.2 phase 2). Everything under
// `Formats/SWF/` up to now was immutable: `SWFMovie.frame1` is resolved once and
// `SWFScene.build(movie:)` is a pure function of it. ActionScript needs a tree
// it can move, hide, retarget, and re-parent, so this is that tree.
//
// One node is one placed character. A clip node additionally owns a timeline
// (its own frames, their control tags, and their DoAction blocks) and a
// playhead. Every node carries an `AS2Object` face so ActionScript can address
// it; the two point at each other through `SWFDisplayHandle`, which holds the
// display object weakly so the AS2 object graph cannot keep a removed clip
// alive.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 3 "The
// display list" for depth semantics, and chapter 13 "Sprites and movie clips"
// for a sprite owning its own timeline and playhead.

import Foundation

/// The back-pointer stored in `AS2Object.hostPayload`. Weak, because the
/// display object owns its `AS2Object` and a strong pair would never be freed.
nonisolated final class SWFDisplayHandle {
    weak var target: SWFDisplayObject?

    init(_ target: SWFDisplayObject) {
        self.target = target
    }
}

/// One node of the runtime display list.
nonisolated final class SWFDisplayObject {
    /// What the node draws. A clip draws nothing itself; its children do.
    enum Content: Equatable {
        /// A sprite instance, or the root when the id is nil.
        case clip(UInt16?)
        case shape(UInt16)
        case staticText(UInt16)
        case editText(UInt16)
    }

    let content: Content
    /// The ActionScript face of this node. Its `hostPayload` is a
    /// `SWFDisplayHandle` pointing back here and its `typeOverride` is
    /// `"movieclip"` for clips.
    let object: AS2Object

    weak var parent: SWFDisplayObject?
    var depth: UInt16
    /// PlaceObject2 `Name` — the instance name ActionScript addresses.
    var name: String?
    var matrix = SWFMatrix.identity
    var colorTransform = SWFColorTransform.identity
    /// PlaceObject `ClipDepth`: this node masks depths (depth, clipDepth].
    var clipDepth: UInt16?
    var ratio: UInt16?
    var isVisible = true
    /// Runtime text for an edit-text node, overriding the character's
    /// `InitialText`.
    var textOverride: String?
    /// CLIPACTIONS handlers the placement attached, if any. Parsed since
    /// milestone 8.3.1 and dispatched since phase 3.
    var clipActions: SWFClipActions?

    /// The sprite's frames; nil for a leaf.
    let timeline: SWFTimeline?
    /// Declared frame count, at least 1 for a clip and 0 for a leaf.
    let frameCount: Int
    /// Zero-based playhead. -1 until the first frame executes.
    var currentFrame = -1
    var isPlaying = true

    private var byDepth: [UInt16: SWFDisplayObject] = [:]
    private var sortedChildren: [SWFDisplayObject]?

    /// Guard against a malformed tree built by bytecode: no node may sit deeper
    /// than this below the root.
    static let maximumTreeDepth = 32

    init(content: Content, depth: UInt16 = 0, timeline: SWFTimeline? = nil, frameCount: Int = 0) {
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
    static func resolve(_ object: AS2Object?) -> SWFDisplayObject? {
        guard let handle = object?.hostPayload as? SWFDisplayHandle else {
            return nil
        }
        return handle.target
    }

    var characterId: UInt16? {
        switch content {
        case let .clip(id): id
        case let .shape(id), let .staticText(id), let .editText(id): id
        }
    }

    var isClip: Bool {
        if case .clip = content {
            return true
        }
        return false
    }

    /// Children in depth-ascending order — the paint order.
    var children: [SWFDisplayObject] {
        if let sortedChildren {
            return sortedChildren
        }
        let sorted = byDepth.values.sorted { $0.depth < $1.depth }
        sortedChildren = sorted
        return sorted
    }

    var childCount: Int {
        byDepth.count
    }

    func child(atDepth depth: UInt16) -> SWFDisplayObject? {
        byDepth[depth]
    }

    /// Instance-name lookup. Ties break on the lowest depth so the result is
    /// stable when a movie reuses a name.
    func child(named name: String) -> SWFDisplayObject? {
        children.first { $0.name == name }
    }

    /// Places `child` at `depth`, replacing whatever occupied it.
    func addChild(_ child: SWFDisplayObject, atDepth depth: UInt16) {
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
    func removeChild(atDepth depth: UInt16) -> SWFDisplayObject? {
        guard let removed = byDepth.removeValue(forKey: depth) else {
            return nil
        }
        removed.parent = nil
        unbindName(of: removed)
        sortedChildren = nil
        return removed
    }

    func removeAllChildren() {
        for child in byDepth.values {
            child.parent = nil
            unbindName(of: child)
        }
        byDepth.removeAll()
        sortedChildren = nil
    }

    /// A named instance is a property of its parent timeline, which is what
    /// makes both `panel._x` and a bare `panel` resolve from a frame action.
    /// Hidden from enumeration, matching how Flash reports a timeline's own
    /// variables.
    func bindName(of child: SWFDisplayObject) {
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
    func swapChild(_ child: SWFDisplayObject, toDepth depth: UInt16) {
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
    func nodeCount(remainingDepth: Int = SWFDisplayObject.maximumTreeDepth) -> Int {
        guard remainingDepth > 0 else {
            return 1
        }
        return children.reduce(1) { $0 + $1.nodeCount(remainingDepth: remainingDepth - 1) }
    }

    /// The topmost ancestor — `_root` for anything in one movie's tree.
    var rootObject: SWFDisplayObject {
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
    var targetPath: String {
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
