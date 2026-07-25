// Function definition and invocation (milestone 8.3.2): closing over the
// defining scope, allocating the register file, running the preload flags, and
// binding parameters.
//
// `ActionDefineFunction2` outnumbers `ActionDefineFunction` eight to one in the
// vanilla movies (10,575 against 1,323), so the register path is the common
// one. The preload flags fill registers from register 1 upward in the order the
// specification lists them; getting that order wrong silently shifts every
// parameter register, which is why it is written out one flag at a time.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionDefineFunction" (p. 92) and "ActionDefineFunction2"
// (p. 111), including the `PreloadThis`, `PreloadArguments`, `PreloadSuper`,
// `PreloadRoot`, `PreloadParent`, and `PreloadGlobal` field order.

import Foundation

extension AS2Interpreter {
    /// `ActionDefineFunction` (0x9B) and `ActionDefineFunction2` (0x8E). The
    /// body is the next `bodySize` bytes of the same stream, so execution
    /// resumes after it.
    func defineFunction(
        _ record: SWFActionRecord,
        frame: AS2Frame
    ) throws(AS2Fault) -> AS2Flow {
        guard case let .defineFunction(definition) = record.operands else {
            return .next
        }
        let body = AS2BytecodeBody(
            definition: definition,
            block: frame.block,
            bodyOffset: record.endOffset,
            usesRegisters: record.code == AS2Opcode.defineFunction2,
            constantPool: frame.constantPool,
            scope: frame.scope,
            target: frame.target
        )
        let function = runtime.makeFunction(.bytecode(body))
        if definition.name.isEmpty {
            try frame.push(.object(function))
        } else {
            frame.localScope.define(.object(function), for: definition.name)
        }
        return try skipBody(record, definition: definition, frame: frame)
    }

    private func skipBody(
        _ record: SWFActionRecord,
        definition: SWFActionFunction,
        frame: AS2Frame
    ) throws(AS2Fault) -> AS2Flow {
        guard definition.bodySize > 0 else {
            return .next
        }
        let body = frame.block.records(from: record.endOffset, byteCount: definition.bodySize)
        guard !body.isEmpty, body.endIndex <= frame.range.upperBound else {
            throw AS2Fault.truncatedBody(offset: record.offset)
        }
        return .jump(body.endIndex)
    }

    /// Builds the frame a bytecode function body runs in. Returns nil for an
    /// empty body, which calls to `undefined` without ever entering the loop.
    func makeFrame(
        _ body: AS2BytecodeBody,
        function: AS2Object,
        site: AS2CallSite
    ) throws(AS2Fault) -> AS2Frame? {
        guard body.definition.bodySize > 0 else {
            return nil
        }
        let records = body.block.records(from: body.bodyOffset, byteCount: body.definition.bodySize)
        guard !records.isEmpty else {
            throw AS2Fault.truncatedBody(offset: body.bodyOffset)
        }
        let activation = AS2Object()
        let frame = AS2Frame(
            runtime: runtime, block: body.block, target: body.target, thisValue: site.thisValue
        )
        frame.stackLimit = limits.stackDepth
        frame.constantPool = body.constantPool
        frame.scope = body.scope + [activation]
        frame.registers = Array(repeating: .undefined, count: registerCount(for: body))
        // Before `bind`: the `PreloadSuper` register is built from it.
        frame.basePrototype = site.base
        bind(site.arguments, body: body, frame: frame, function: function)
        frame.range = records.startIndex ..< records.endIndex
        frame.index = records.startIndex
        return frame
    }

    private func registerCount(for body: AS2BytecodeBody) -> Int {
        guard body.usesRegisters else {
            return AS2Frame.defaultRegisterCount
        }
        let requested = Int(body.definition.registerCount)
        return max(1, min(requested, limits.registerCount))
    }

    /// Fills the preload registers, then binds each parameter to a register or
    /// to a named local, then installs the `arguments` object.
    ///
    /// `suppressThis` and `suppressSuper` are deliberately not honored: `this`
    /// and `super` stay reachable as names because `AS2InterpreterVariables`
    /// answers them from the frame, and suppressing them would only save an
    /// activation slot.
    private func bind(
        _ arguments: [AS2Value],
        body: AS2BytecodeBody,
        frame: AS2Frame,
        function: AS2Object
    ) {
        let activation = frame.localScope
        let flags = body.definition.flags
        if body.usesRegisters {
            preload(flags: flags, frame: frame, arguments: arguments, function: function)
        }
        bindParameters(arguments, body: body, frame: frame, activation: activation)
        if !body.usesRegisters || !flags.contains(.suppressArguments) {
            activation.define(
                .object(makeArguments(arguments, function: function)), for: "arguments"
            )
        }
    }

    /// Registers 1 upward, in the order the specification lists the flags.
    private func preload(
        flags: SWFDefineFunctionFlags,
        frame: AS2Frame,
        arguments: [AS2Value],
        function: AS2Object
    ) {
        var next = 1
        if flags.contains(.preloadThis) {
            frame.setRegister(next, to: frame.thisValue)
            next += 1
        }
        if flags.contains(.preloadArguments) {
            frame.setRegister(next, to: .object(makeArguments(arguments, function: function)))
            next += 1
        }
        if flags.contains(.preloadSuper) {
            let binding = superBinding(for: frame.thisValue, base: frame.basePrototype)
            frame.setRegister(next, to: binding.map(AS2Value.object) ?? .undefined)
            next += 1
        }
        _ = preloadTargets(flags: flags, frame: frame, from: next)
    }

    /// `_root`, `_parent`, and `_global` — the three preloads that need the
    /// host, and the two that get `undefined` until a display list exists.
    private func preloadTargets(
        flags: SWFDefineFunctionFlags,
        frame: AS2Frame,
        from start: Int
    ) -> Int {
        var next = start
        let host = runtime.host
        if flags.contains(.preloadRoot) {
            let root = host.specialObject(.root, relativeTo: frame.target)
            frame.setRegister(next, to: root.map(AS2Value.object) ?? .undefined)
            next += 1
        }
        if flags.contains(.preloadParent) {
            let parent = host.specialObject(.parent, relativeTo: frame.target)
            frame.setRegister(next, to: parent.map(AS2Value.object) ?? .undefined)
            next += 1
        }
        if flags.contains(.preloadGlobal) {
            frame.setRegister(next, to: .object(runtime.globalObject))
            next += 1
        }
        return next
    }

    private func bindParameters(
        _ arguments: [AS2Value],
        body: AS2BytecodeBody,
        frame: AS2Frame,
        activation: AS2Object
    ) {
        let names = body.definition.parameterNames
        let registers = body.definition.parameterRegisters
        for (index, name) in names.enumerated() {
            let value = arguments.indices.contains(index) ? arguments[index] : .undefined
            let register = registers.indices.contains(index) ? Int(registers[index]) : 0
            if body.usesRegisters, register > 0 {
                frame.setRegister(register, to: value)
            } else {
                activation.define(value, for: name)
            }
        }
    }

    /// The `arguments` object: an array of the actual arguments plus `callee`.
    private func makeArguments(_ arguments: [AS2Value], function: AS2Object) -> AS2Object {
        let object = runtime.makeArray(arguments)
        object.define(.object(function), for: "callee", flags: .dontEnumerate)
        return object
    }
}
