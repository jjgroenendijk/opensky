// One running movie: the decoded movie, one `AS2Runtime` and so one `_global`,
// the mutable display tree, and an explicit tick. Bring-up runs every
// DoInitAction, then the root's frame-1 control tags, then its frame-1 DoAction
// blocks. Nothing reads a clock (docs/rendering/swf-layer.md).

import Foundation

nonisolated public final class SWFMovieRuntime {
    /// The decoded movie plus its resolved external fonts.
    public let movieScene: SWFMovieScene
    public let runtime: AS2Runtime

    /// `_root` / `_level0`.
    public let root: SWFDisplayObject
    /// `MovieClip.prototype` — where the clip methods live, and what a class
    /// registered against a sprite ultimately inherits from.
    public let movieClipPrototype: AS2Object
    /// `TextField.prototype`.
    public let textFieldPrototype: AS2Object

    /// Ticks applied since bring-up. Reported, never used as a time source.
    public private(set) var tickCount = 0
    /// True when the display tree changed since the last `makeScene()`.
    public private(set) var isDirty = true
    /// Instantiations refused because the tree hit `maximumNodes`.
    public private(set) var droppedInstantiations = 0
    /// Frame DoAction blocks skipped because a frame action re-entered its own
    /// clip past `maximumGotoDepth`.
    public private(set) var droppedFrameActions = 0
    /// True once `start()` has run.
    public private(set) var isStarted = false
    /// What `Selection.setFocus` last pointed at. An unconsumed key falls back
    /// to this node's own handler; the CLIK framework does its own focus
    /// bookkeeping on top.
    public weak var focusTarget: SWFDisplayObject?
    /// Accepted `Selection.setFocus` calls, so a test can assert focus moved
    /// without depending on which node it moved to.
    public var focusChanges = 0
    /// Nesting guard for a frame action that jumps the same clip again.
    public var gotoDepth = 0
    /// Live pointer and key state.
    public let input = SWFRuntimeInputState()
    /// `setInterval` / `setTimeout` callbacks, fired from `advance()`.
    public let timers = SWFRuntimeTimers()
    /// Both directions of the `GameDelegate` bridge, bounded.
    public private(set) var invokeLog = SWFInvokeLog()
    /// Resolves a `$TOKEN` text when a field is read, as Scaleform's translator does.
    /// Nil shows every text as written.
    public var textTranslator: ((String) -> String)?
    /// Engine-side handlers a movie may call by name.
    public var hostFunctions: [String: SWFHostFunction] = [:]
    /// The last arguments of each handled call. A main-actor answer reads a list the
    /// movie passed from here, because the values cannot cross actors.
    public var lastHostArguments: [String: [AS2Value]] = [:]
    /// Placements that attached a key CLIPACTIONS handler. Zero across the whole
    /// vanilla install, which is what lets key dispatch skip the tree walk.
    public private(set) var keyClipHandlers = 0
    /// Clips that currently expose one of Flash's three global mouse handlers.
    public let globalMouseHandlers = SWFGlobalMouseHandlerRegistry()

    /// Display nodes one movie may hold. Vanilla menus build a few hundred; a
    /// runaway `attachMovie` loop is what this stops.
    public static let maximumNodes = 4096
    /// How deep a `gotoAndStop` inside a frame action may re-enter.
    public static let maximumGotoDepth = 8
    /// How far below the root the engine looks for a menu's `handleInput`.
    public static let maximumHandlerDepth = 3
    /// Longest interval a movie may schedule, in ticks. A minute at 60 frames
    /// per second, which is far past anything a menu waits for.
    public static let maximumTimerTicks = 3600

    public var movie: SWFMovie {
        movieScene.movie
    }

    public var tally: AS2Tally {
        runtime.tally
    }

    public var traceLog: AS2TraceLog {
        runtime.traceLog
    }

    /// Live node count, walked on demand (the tree is small).
    public var nodeCount: Int {
        root.nodeCount()
    }

    public var globalMouseHandlerClips: Int {
        globalMouseHandlers.count
    }

    public init(movieScene: SWFMovieScene, limits: AS2Limits = .standard) {
        self.movieScene = movieScene
        let host = SWFRuntimeHost()
        runtime = AS2Runtime(
            swfVersion: movieScene.movie.version, host: host, limits: limits
        )
        root = SWFDisplayObject(
            content: .clip(nil),
            timeline: movieScene.movie.timeline,
            frameCount: max(1, movieScene.movie.timeline.frames.count)
        )
        let natives = SWFRuntimeNatives.install(into: runtime, movie: movieScene.movie)
        movieClipPrototype = natives.movieClipPrototype
        textFieldPrototype = natives.textFieldPrototype
        root.object.prototype = movieClipPrototype
        host.owner = self
    }

    /// Runs the bring-up sequence. Safe to call once; later calls are ignored.
    public func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        for initAction in movie.initActions {
            runtime.execute(initAction, target: root.object)
        }
        enterFrame(0, of: root)
        markDirty()
    }

    /// One explicit tick: every playing clip advances one frame. Call it from
    /// the engine's frame loop, never from a timer inside the layer.
    public func advance() {
        guard isStarted else {
            start()
            return
        }
        tickCount += 1
        advancePlayhead(of: root)
        dispatchEnterFrame(of: root, remainingDepth: SWFDisplayObject.maximumTreeDepth)
        fireDueTimers()
    }

    /// Advances a clip and then its children, so a parent that replaced its
    /// children this tick does not also step the replacements.
    private func advancePlayhead(of node: SWFDisplayObject) {
        let children = node.children
        if node.isClip, node.isPlaying, node.frameCount > 1 {
            let next = (node.currentFrame + 1) % node.frameCount
            enterFrame(next, of: node)
        }
        for child in children where child.isClip {
            advancePlayhead(of: child)
        }
    }

    /// Calls an ActionScript function the movie defined, with the root clip as
    /// the default receiver — the engine-to-movie direction of the bridge.
    @discardableResult
    public func invoke(
        _ name: String,
        on target: SWFDisplayObject? = nil,
        arguments: [AS2Value] = []
    ) -> AS2ExecutionResult {
        let receiver = target ?? root
        guard let function = receiver.object.lookup(name)?.property.value.functionValue else {
            runtime.noteMissing(name)
            return .empty
        }
        markDirty()
        return runtime.invoke(
            .object(function), thisValue: .object(receiver.object), arguments: arguments
        )
    }

    public func markDirty() {
        isDirty = true
    }

    public func noteDroppedFrameActions(_ count: Int) {
        droppedFrameActions += count
    }

    /// Records one bridge call. The log is bounded and drops oldest first.
    public func noteInvoke(_ entry: SWFInvokeEntry) {
        invokeLog.append(entry)
    }

    public func clearInvokeLog() {
        invokeLog.clear()
    }

    public func noteKeyClipHandler() {
        keyClipHandlers += 1
    }

    /// Clears the dirty flag; the scene generator calls it after it reads the
    /// tree.
    public func clearDirty() {
        isDirty = false
    }

    // MARK: - Instantiation

    /// Builds the display object for a character id, wiring its ActionScript
    /// face. Returns nil for a character that cannot be placed (a font, a
    /// bitmap, or an id the dictionary does not hold).
    public func makeDisplayObject(characterId: UInt16) -> SWFDisplayObject? {
        guard nodeCount < SWFMovieRuntime.maximumNodes else {
            droppedInstantiations += 1
            return nil
        }
        switch movie.characters[characterId] {
        case let .sprite(sprite):
            let node = SWFDisplayObject(
                content: .clip(characterId),
                timeline: sprite.timeline,
                frameCount: max(1, Int(sprite.frameCount))
            )
            node.object.prototype = movieClipPrototype
            globalMouseHandlers.observe(node)
            return node
        case .shape:
            return SWFDisplayObject(content: .shape(characterId))
        case .staticText:
            return SWFDisplayObject(content: .staticText(characterId))
        case let .editText(text):
            let node = SWFDisplayObject(content: .editText(characterId))
            node.object.prototype = textFieldPrototype
            node.object.typeOverride = nil
            if !text.variableName.isEmpty {
                node.object.define(.string(text.variableName), for: "variable")
            }
            return node
        default:
            return nil
        }
    }

    /// Runs the class registered against a placed character's linkage name,
    /// with the display object as `this`. This plus running DoInitAction first
    /// is the whole reason a vanilla menu comes alive.
    public func constructRegisteredClass(for node: SWFDisplayObject) {
        guard
            let characterId = node.characterId,
            let linkage = movie.exportedIds[characterId],
            let constructor = runtime.registeredClass(named: linkage)
        else {
            return
        }
        if let prototype = constructor.lookup("prototype")?.property.value.objectValue {
            node.object.prototype = prototype
        }
        node.object.define(
            .object(constructor), for: "__constructor__", flags: [.dontEnumerate, .dontDelete]
        )
        runtime.invoke(.object(constructor), thisValue: .object(node.object))
    }

    /// `attachMovie(linkageName, instanceName, depth)`: instantiates an exported
    /// character into a parent clip. Returns the new node, or nil when the
    /// linkage name names nothing placeable.
    public func attach(
        linkage: String,
        into parent: SWFDisplayObject,
        depth: UInt16,
        name: String?
    ) -> SWFDisplayObject? {
        guard
            let characterId = movie.exportedNames[linkage],
            let node = makeDisplayObject(characterId: characterId)
        else {
            runtime.noteMissing(linkage)
            return nil
        }
        node.name = name
        parent.addChild(node, atDepth: depth)
        bringUp(node)
        markDirty()
        return node
    }
}
