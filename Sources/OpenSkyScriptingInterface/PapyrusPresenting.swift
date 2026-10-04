// The port Papyrus natives use to show things to the player: HUD notifications,
// help messages, message boxes, and camera effects. The menus layer conforms.
// See docs/engine/messages.md and docs/engine/kill-cam.md.

import Foundation
import OpenSkyFormatsESM

/// What `Message.Show` did with one MESG.
nonisolated public enum PapyrusMessageShowResult: Equatable, Sendable {
    /// No MESG record behind the form.
    case notFound
    /// A notification was posted; the call returns at once.
    case posted
    /// A message box opened. The caller waits until the engine answers the
    /// token with the original index of the chosen button.
    case awaitingButton(token: UInt64)
}

/// One `Message.ShowAsHelpMessage` call.
nonisolated public struct PapyrusHelpMessageRequest: Equatable, Sendable {
    public let message: ReferenceKey
    /// The input event name, such as "Jump"; counts are kept per event.
    public let event: String
    public let duration: Float
    public let interval: Float
    /// How many times this event may show it; 0 means no limit.
    public let maxTimes: Int

    public init(
        message: ReferenceKey,
        event: String,
        duration: Float,
        interval: Float,
        maxTimes: Int
    ) {
        self.message = message
        self.event = event
        self.duration = duration
        self.interval = interval
        self.maxTimes = maxTimes
    }
}

@MainActor
public protocol PapyrusPresenting: AnyObject {
    /// Queues a HUD notification. False when the text is empty or hidden.
    @discardableResult
    func postNotification(_ text: String) -> Bool

    /// Shows one MESG with its format arguments.
    func showMessage(_ message: ReferenceKey, arguments: [Float]) -> PapyrusMessageShowResult

    /// Opens a one-button box that does not block the caller.
    @discardableResult
    func showMessageBox(_ text: String) -> Bool

    @discardableResult
    func showHelpMessage(_ request: PapyrusHelpMessageRequest) -> Bool

    func resetHelpMessage(event: String)

    /// Shakes the camera; `source` nil shakes at full strength wherever the player is.
    @discardableResult
    func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool

    @discardableResult
    func forceCameraMode(firstPerson: Bool) -> Bool
}
