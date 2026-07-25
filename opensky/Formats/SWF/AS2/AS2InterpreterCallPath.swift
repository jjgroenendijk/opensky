// The interpreter's call path (issue #132): starting a call, the two shapes a
// call's result can take, and the one place Swift recursion is still used.
//
// `startCall` never recurses — a bytecode callee becomes a frame on
// `AS2Interpreter.frames` and the loop in `AS2Interpreter.runFrames` picks it
// up. `call` is the exception: a built-in re-entering bytecode
// (`Function.prototype.apply`) or a property accessor answering a member read
// needs the value inside a Swift call, so it runs a nested loop and is bounded
// by `AS2Limits.reentryDepth` rather than by `callDepth`.

import Foundation

/// Everything a call needs besides the function object: the receiver, the
/// arguments, the site that issued it, where the result goes, and the class
/// prototype the callee was found on.
nonisolated struct AS2CallSite {
    let thisValue: AS2Value
    let arguments: [AS2Value]
    /// Byte offset of the calling record, so a depth fault can name it.
    let offset: Int
    var completion: AS2FrameCompletion = .value
    /// The prototype the callee lives on. It becomes the called frame's
    /// `AS2Frame.basePrototype`, which is where its `super` starts walking.
    var base: AS2Object?
}

extension AS2Interpreter {
    /// Starts a call. A built-in runs immediately; a bytecode body becomes a
    /// frame the interpreter loop picks up next, and `site.completion` says
    /// where its return value goes. A non-callable object is not an error in
    /// ActionScript: the call yields `undefined`.
    func startCall(
        _ function: AS2Object,
        _ site: AS2CallSite
    ) throws(AS2Fault) -> AS2CallStart {
        guard let callable = function.callable else {
            return .value(.undefined)
        }
        runtime.noteCall()
        guard callDepth < limits.callDepth else {
            throw AS2Fault.callDepthExceeded(offset: site.offset)
        }
        switch callable {
        case let .native(body):
            return try .value(runNative(body, function: function, site: site))
        case let .bytecode(body):
            guard let frame = try makeFrame(body, function: function, site: site) else {
                return .value(.undefined)
            }
            frame.completion = site.completion
            frame.isCall = true
            callDepth += 1
            frames.append(frame)
            return .pushed
        }
    }

    private func runNative(
        _ body: AS2NativeBody,
        function: AS2Object,
        site: AS2CallSite
    ) throws(AS2Fault) -> AS2Value {
        var constructing = false
        if case .construct = site.completion {
            constructing = true
        }
        let context = AS2CallContext(
            interpreter: self,
            callee: function,
            thisValue: site.thisValue,
            arguments: site.arguments,
            isConstructing: constructing
        )
        callDepth += 1
        defer { callDepth -= 1 }
        return try invokeNative(body, context: context)
    }

    /// Calls `function` and returns its value to Swift. This is the re-entrant
    /// path — a built-in or a property accessor that cannot continue without
    /// the result — and the only one that costs Swift stack, so it carries
    /// `AS2Limits.reentryDepth` on top of the ordinary call-depth cap.
    func call(
        _ function: AS2Object,
        thisValue: AS2Value,
        arguments: [AS2Value],
        offset: Int,
        base: AS2Object? = nil
    ) throws(AS2Fault) -> AS2Value {
        guard reentryDepth < limits.reentryDepth else {
            throw AS2Fault.reentryDepthExceeded(offset: offset)
        }
        reentryDepth += 1
        defer { reentryDepth -= 1 }
        let depth = frames.count
        let site = AS2CallSite(
            thisValue: thisValue, arguments: arguments, offset: offset, base: base
        )
        switch try startCall(function, site) {
        case let .value(value):
            return value
        case .pushed:
            return try runFrames(baseDepth: depth)
        }
    }

    /// Starts a call whose result belongs on `frame`'s operand stack — the
    /// shape every call opcode has.
    func callPushingResult(
        _ function: AS2Object,
        _ site: AS2CallSite,
        frame: AS2Frame
    ) throws(AS2Fault) -> AS2Flow {
        var pushing = site
        pushing.completion = .push
        let start = try startCall(function, pushing)
        switch start {
        case let .value(value):
            try frame.push(value)
            return .next
        case .pushed:
            return .called
        }
    }
}
