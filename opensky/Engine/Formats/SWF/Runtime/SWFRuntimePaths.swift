// Path resolution and dynamic members for the runtime display tree (milestone
// 8.3.2 phase 2).
//
// ActionScript addresses a clip three ways and all three arrive here: as a
// dotted or slash-separated path (`_root.menu.list`, `../list`), as one of the
// special targets, or as a plain member read on a clip object whose property
// table does not hold the name. The last case is how `clip.someChild` and
// `clip._x` both work, because `AS2Interpreter.getMember` consults the host
// only after the prototype chain misses.
//
// Text lives here too: a `DefineEditText` field's runtime content is either an
// explicit assignment (`field.text = "..."`, `field.SetText(...)`) or the
// value of the field's `VariableName` binding, which milestone 8.2 decoded and
// never read.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// Resolves a dotted or slash-separated path. A leading `/` or a leading
    /// `_root` / `_level0` component makes it absolute; `..` and `_parent` walk
    /// up. Returns nil when any component names nothing.
    func node(atPath path: String, from origin: SWFDisplayObject) -> SWFDisplayObject? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        var current = trimmed.hasPrefix("/") ? origin.rootObject : origin
        let components = SWFMovieRuntime.pathComponents(trimmed)
        guard !components.isEmpty else {
            return current
        }
        for component in components {
            guard let next = step(from: current, component: component) else {
                return nil
            }
            current = next
        }
        return current
    }

    /// Splits a path into components. Slash segments come first, because `..`
    /// only ever appears in the slash spelling and must not be split on its own
    /// dots; each remaining segment then splits on `.` for the dotted spelling.
    static func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/").flatMap { segment -> [String] in
            if segment == ".." || segment == "." {
                return [String(segment)]
            }
            return segment.split(separator: ".").map(String.init)
        }
    }

    private func step(from node: SWFDisplayObject, component: String) -> SWFDisplayObject? {
        switch component {
        case "", "this":
            node
        case "_root", "_level0":
            node.rootObject
        case "..", "_parent":
            node.parent
        default:
            node.child(named: component)
        }
    }

    // MARK: - Members

    /// A member of a display object the property table does not hold.
    func member(_ name: String, of node: SWFDisplayObject) -> AS2Value? {
        if let property = AS2DisplayProperty.named(name) {
            return displayProperty(property, of: node)
        }
        switch name {
        case "_root", "_level0":
            return .object(node.rootObject.object)
        case "_parent":
            return node.parent.map { .object($0.object) }
        case "text", "htmlText":
            return textMember(of: node)
        default:
            break
        }
        if let child = node.child(named: name) {
            return .object(child.object)
        }
        return builtinMethod(name, of: node)
    }

    /// A clip's built-in methods stay reachable even when `registerClass`
    /// replaced its `__proto__` with a class that does not `extend MovieClip`.
    /// Flash resolves those natively rather than through the prototype chain,
    /// so this is the equivalent fallback: the prototype chain is consulted
    /// first (a class may legitimately override `gotoAndStop`), and only a
    /// complete miss lands here.
    private func builtinMethod(_ name: String, of node: SWFDisplayObject) -> AS2Value? {
        let prototype = node.isClip ? movieClipPrototype : textFieldPrototype
        guard let found = prototype.lookup(name)?.property.value.functionValue else {
            return nil
        }
        return .object(found)
    }

    /// A member write on a display object. Returning false lets the write fall
    /// through to the ordinary property table, which is what makes CLIK's
    /// `__width` / `__height` pair — ordinary properties, not display
    /// properties — behave.
    func setMember(_ name: String, of node: SWFDisplayObject, to value: AS2Value) -> Bool {
        if let property = AS2DisplayProperty.named(name) {
            return setDisplayProperty(property, of: node, to: value)
        }
        switch name {
        case "text", "htmlText":
            guard case .editText = node.content else {
                return false
            }
            setText(runtime.coercion.toString(value), of: node)
            return true
        default:
            return false
        }
    }

    // MARK: - Text

    private func textMember(of node: SWFDisplayObject) -> AS2Value? {
        guard case .editText = node.content else {
            return nil
        }
        return .string(text(of: node) ?? "")
    }

    /// Assigns a field's runtime content and writes the bound variable back, so
    /// a movie that reads `_root.someVar` after setting `field.text` sees the
    /// same string.
    func setText(_ value: String, of node: SWFDisplayObject) {
        node.textOverride = value
        if
            let characterId = node.characterId,
            let field = movie.editText(characterId), !field.variableName.isEmpty
        {
            writeVariable(field.variableName, from: node, to: .string(value))
        }
        markDirty()
    }

    /// The string a field currently draws: an explicit assignment first, then
    /// its `VariableName` binding, then the character's `InitialText`.
    func text(of node: SWFDisplayObject) -> String? {
        if let override = node.textOverride {
            return override
        }
        guard let characterId = node.characterId, let field = movie.editText(characterId) else {
            return nil
        }
        if !field.variableName.isEmpty, let bound = readVariable(field.variableName, from: node) {
            if bound != .undefined {
                return runtime.coercion.toString(bound)
            }
        }
        return field.plainText
    }

    // MARK: - Variable bindings

    /// Splits `a.b.name` into the container path and the trailing property.
    private func binding(
        _ name: String,
        from node: SWFDisplayObject
    ) -> (container: AS2Object, property: String)? {
        var components = SWFMovieRuntime.pathComponents(name)
        guard let property = components.popLast(), !property.isEmpty else {
            return nil
        }
        guard !components.isEmpty else {
            return ((node.parent ?? node.rootObject).object, property)
        }
        let path = (name.hasPrefix("/") ? "/" : "") + components.joined(separator: ".")
        guard let container = self.node(atPath: path, from: node.parent ?? node.rootObject) else {
            return nil
        }
        return (container.object, property)
    }

    private func readVariable(_ name: String, from node: SWFDisplayObject) -> AS2Value? {
        guard let binding = binding(name, from: node) else {
            return nil
        }
        return binding.container.lookup(binding.property)?.property.value
    }

    private func writeVariable(_ name: String, from node: SWFDisplayObject, to value: AS2Value) {
        guard let binding = binding(name, from: node) else {
            return
        }
        binding.container.assign(value, for: binding.property)
    }
}
