// The natives that show things to the player: `Debug.Notification`, the
// `Message` script, and the camera calls on `Game`. Each goes through the
// session's `PapyrusPresenting` port. Signatures are from the Creation Kit wiki.
// See docs/engine/messages.md and docs/engine/kill-cam.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// `Game.ShakeCamera` defaults: "afStrength = 0.5", and "afDuration = 0.0",
    /// which means "use the game setting".
    public static let defaultShakeStrength: Float = 0.5

    public static func installPresentation(into registry: inout PapyrusNativeRegistry) {
        installMessageNatives(into: &registry)
        installHelpMessageNatives(into: &registry)
        installCameraNatives(into: &registry)
    }

    private static func presenter(_ context: PapyrusNativeContext) -> (any PapyrusPresenting)? {
        (context.world as? PapyrusWorldStateBridge)?.presenter
    }

    private static func installMessageNatives(into registry: inout PapyrusNativeRegistry) {
        // `Function Notification(string asNotificationText) native global`
        registry
            .register(PapyrusNativeFunction(
                scriptName: "Debug",
                functionName: "Notification"
            ) { call, context in
                guard let text = string(call, at: 0) else {
                    return failure(call, "Notification needs a string")
                }
                context.log.append("Notification: \(text)")
                presenter(context)?.postNotification(text)
                return .returned(.none)
            })
        // `Function MessageBox(string asMessageBoxText) native global`: one OK
        // button, and the caller does not wait.
        registry
            .register(PapyrusNativeFunction(
                scriptName: "Debug",
                functionName: "MessageBox"
            ) { call, context in
                guard let text = string(call, at: 0) else {
                    return failure(call, "MessageBox needs a string message")
                }
                context.log.append("MessageBox: \(text)")
                presenter(context)?.showMessageBox(text)
                return .returned(.none)
            })
        // `int Function Show(float afArg1 = 0.0, ... float afArg9 = 0.0) native`:
        // "if a message box, waits til the user closes it and returns the button".
        registry
            .register(PapyrusNativeFunction(
                scriptName: "Message",
                functionName: "Show"
            ) { call, context in
                messageTarget(call, context) { presenter, message in
                    let arguments = (0 ..< 9).map { float(call, at: $0) ?? 0 }
                    switch presenter.showMessage(message, arguments: arguments) {
                    case .notFound:
                        return failure(call, "Show needs a MESG record")
                    case .posted:
                        return .returned(.integer(-1))
                    case let .awaitingButton(token):
                        return .suspended(.external(token))
                    }
                }
            })
    }

    private static func installHelpMessageNatives(into registry: inout PapyrusNativeRegistry) {
        // `Function ShowAsHelpMessage(string asEvent, float afDuration,
        // float afInterval, int aiMaxTimes) native`
        registry.register(PapyrusNativeFunction(
            scriptName: "Message",
            functionName: "ShowAsHelpMessage"
        ) { call, context in
            messageTarget(call, context) { presenter, message in
                guard let event = string(call, at: 0) else {
                    return failure(call, "ShowAsHelpMessage needs an event name")
                }
                presenter.showHelpMessage(PapyrusHelpMessageRequest(
                    message: message,
                    event: event,
                    duration: float(call, at: 1) ?? 0,
                    interval: float(call, at: 2) ?? 0,
                    maxTimes: Int(integer(call, at: 3) ?? 0)
                ))
                return .returned(.none)
            }
        })
        // `Function ResetHelpMessage(string asEvent) native global`
        registry.register(PapyrusNativeFunction(
            scriptName: "Message",
            functionName: "ResetHelpMessage"
        ) { call, context in
            guard let event = string(call, at: 0) else {
                return failure(call, "ResetHelpMessage needs an event name")
            }
            guard let presenter = presenter(context) else { return needsPresenter(call) }
            presenter.resetHelpMessage(event: event)
            return .returned(.none)
        })
    }

    private static func installCameraNatives(into registry: inout PapyrusNativeRegistry) {
        // `Function ShakeCamera(ObjectReference akSource = None,
        // float afStrength = 0.5, float afDuration = 0.0) native global`
        registry
            .register(PapyrusNativeFunction(
                scriptName: "Game",
                functionName: "ShakeCamera"
            ) { call, context in
                guard let presenter = presenter(context) else { return needsPresenter(call) }
                var source: ReferenceKey?
                if
                    call.arguments.indices.contains(0),
                    case let .object(handle) = call.arguments[0]
                {
                    source = context.world?.referenceKey(for: handle)
                }
                presenter.shakeCamera(
                    source: source,
                    strength: float(call, at: 1) ?? defaultShakeStrength,
                    duration: float(call, at: 2) ?? 0
                )
                return .returned(.none)
            })
        for (name, firstPerson) in [("ForceFirstPerson", true), ("ForceThirdPerson", false)] {
            registry
                .register(PapyrusNativeFunction(
                    scriptName: "Game",
                    functionName: name
                ) { call, context in
                    guard let presenter = presenter(context) else { return needsPresenter(call) }
                    presenter.forceCameraMode(firstPerson: firstPerson)
                    return .returned(.none)
                })
        }
    }

    private static func messageTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: (any PapyrusPresenting, ReferenceKey) -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        guard let presenter = presenter(context) else { return needsPresenter(call) }
        guard let target = worldTarget(call, context) else {
            return failure(call, "\(call.functionName) needs a Message receiver")
        }
        return body(presenter, target.key)
    }

    private static func needsPresenter(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(call, "\(call.functionName) needs a session that shows messages")
    }
}
