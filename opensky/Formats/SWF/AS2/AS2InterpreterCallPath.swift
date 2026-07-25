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

extension AS2Interpreter {
    /// Starts a call. A built-in runs immediately; a bytecode body becomes a
    /// frame the interpreter loop picks up next, and `completion` says where
    /// its return value goes. A non-callable object is not an error in
    /// ActionScript: the call yields `undefined`.
    func startCall(
        _ function: AS2Object,
        thisValue: AS2Value,
        arguments: [AS2Value],
        offset: Int,
        completion: AS2FrameCompletion = .value
    ) throws(AS2Fault) -> AS2CallStart {
        guard let callable = function.callable else {
            return .value(.undefined)
        }
        runtime.noteCall()
        guard callDepth < limits.callDepth else {
            throw AS2Fault.callDepthExceeded(offset: offset)
        }
        switch callable {
        case let .native(body):
            return try .value(
                runNative(
                    body,
                    function: function,
                    thisValue: thisValue,
                    arguments: arguments,
                    completion: completion
                )
            )
        case let .bytecode(body):
            guard
                let frame = try makeFrame(
                    body, function: function, thisValue: thisValue, arguments: arguments
                )
            else {
                return .value(.undefined)
            }
            frame.completion = completion
            frame.isCall = true
            callDepth += 1
            frames.append(frame)
            return .pushed
        }
    }

    private func runNative(
        _ body: AS2NativeBody,
        function: AS2Object,
        thisValue: AS2Value,
        arguments: [AS2Value],
        completion: AS2FrameCompletion
    ) throws(AS2Fault) -> AS2Value {
        var constructing = false
        if case .construct = completion {
            constructing = true
        }
        let context = AS2CallContext(
            interpreter: self,
            callee: function,
            thisValue: thisValue,
            arguments: arguments,
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
        offset: Int
    ) throws(AS2Fault) -> AS2Value {
        guard reentryDepth < limits.reentryDepth else {
            throw AS2Fault.reentryDepthExceeded(offset: offset)
        }
        reentryDepth += 1
        defer { reentryDepth -= 1 }
        let base = frames.count
        switch try startCall(function, thisValue: thisValue, arguments: arguments, offset: offset) {
        case let .value(value):
            return value
        case .pushed:
            return try runFrames(baseDepth: base)
        }
    }

    /// Starts a call whose result belongs on `frame`'s operand stack — the
    /// shape every call opcode has.
    func callPushingResult(
        _ function: AS2Object,
        thisValue: AS2Value,
        arguments: [AS2Value],
        offset: Int,
        frame: AS2Frame
    ) throws(AS2Fault) -> AS2Flow {
        let start = try startCall(
            function, thisValue: thisValue, arguments: arguments, offset: offset, completion: .push
        )
        switch start {
        case let .value(value):
            try frame.push(value)
            return .next
        case .pushed:
            return .called
        }
    }
}
