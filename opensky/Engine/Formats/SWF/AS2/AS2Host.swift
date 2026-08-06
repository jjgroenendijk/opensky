// The host seam (milestone 8.3.2). Everything the AS2 interpreter cannot
// answer from its own object model — timeline control, display properties,
// target paths, and members of host-backed objects — leaves through this
// protocol.
//
// This milestone implements the interpreter only. `MovieClip`, `TextField`,
// `Stage`, and `Selection` arrive in a later one and will be an `AS2Host`
// backed by a mutable display list; until then `AS2RecordingHost` answers
// every request with "not mine", which the interpreter records in the tally.
// Keeping the boundary here means the interpreter never learns what a display
// object is.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionGotoFrame", "ActionGoToLabel", "ActionPlay",
// "ActionStop", "ActionGetProperty", "ActionSetProperty", and
// "ActionTargetPath". The specification defines the opcodes and that
// get/set-property take a numeric index; the index-to-name table below is
// recorded as observed from ActionScript's property list, not quoted from the
// specification.

import Foundation

/// A timeline request an action made against its target.
nonisolated enum AS2TimelineCommand: Equatable {
    /// `ActionStop` (0x07).
    case stop
    /// `ActionPlay` (0x06).
    case play
    /// `ActionGotoFrame` (0x81); the frame number is zero-based.
    case gotoFrame(Int)
    /// `ActionGoToLabel` (0x8C).
    case gotoLabel(String)
}

/// The objects a bare `_root` / `_parent` / `_level0` reference resolves to.
nonisolated enum AS2SpecialTarget: String, CaseIterable {
    case root = "_root"
    case parent = "_parent"
    case level0 = "_level0"
}

/// The numbered display properties `ActionGetProperty` (0x22) and
/// `ActionSetProperty` (0x23) address.
nonisolated enum AS2DisplayProperty: Int, CaseIterable {
    case positionX = 0
    case positionY
    case scaleX
    case scaleY
    case currentFrame
    case totalFrames
    case alpha
    case visible
    case width
    case height
    case rotation
    case target
    case framesLoaded
    case name
    case dropTarget
    case url
    case highQuality
    case focusRect
    case soundBufferTime
    case quality
    case mouseX
    case mouseY

    /// The ActionScript spelling, which is also the member name the same
    /// property is reachable under (`clip._x`).
    var actionScriptName: String {
        AS2DisplayProperty.names[rawValue]
    }

    static func named(_ name: String) -> AS2DisplayProperty? {
        guard let index = names.firstIndex(of: name) else {
            return nil
        }
        return AS2DisplayProperty(rawValue: index)
    }

    private static let names = [
        "_x", "_y", "_xscale", "_yscale", "_currentframe", "_totalframes",
        "_alpha", "_visible", "_width", "_height", "_rotation", "_target",
        "_framesloaded", "_name", "_droptarget", "_url", "_highquality",
        "_focusrect", "_soundbuftime", "_quality", "_xmouse", "_ymouse"
    ]
}

/// What the interpreter asks the engine. Every method may decline (nil or
/// false); declining is normal while the display layer does not exist, and the
/// interpreter turns it into a tally entry rather than an error.
nonisolated protocol AS2Host: AnyObject {
    /// `ActionStop`, `ActionPlay`, `ActionGotoFrame`, `ActionGoToLabel`.
    func perform(_ command: AS2TimelineCommand, target: AS2Object)

    /// `ActionGetProperty`. `target` is the raw stack operand: a display object
    /// or a path string.
    func property(_ property: AS2DisplayProperty, of target: AS2Value) -> AS2Value?

    /// `ActionSetProperty`. Returns whether the write was accepted.
    func setProperty(
        _ property: AS2DisplayProperty,
        of target: AS2Value,
        to value: AS2Value
    ) -> Bool

    /// `ActionTargetPath` (0x45): the slash path of a display object.
    func targetPath(of object: AS2Object) -> String?

    /// Resolves a dotted or slash-separated path such as `_root.menu.list`
    /// relative to the running action's target.
    func object(atPath path: String, from origin: AS2Object) -> AS2Object?

    /// Resolves `_root`, `_parent`, or `_level0`.
    func specialObject(_ kind: AS2SpecialTarget, relativeTo origin: AS2Object) -> AS2Object?

    /// A member of a host-backed object (`AS2Object.hostPayload` is set) that
    /// the property table does not hold.
    func member(_ name: String, of object: AS2Object) -> AS2Value?

    /// A member write on a host-backed object. Returns whether it was accepted;
    /// declining lets the write fall back to the ordinary property table.
    func setMember(_ name: String, of object: AS2Object, to value: AS2Value) -> Bool
}
