// The M15 gate's input half (issue #198), in a satellite of
// `M15AcceptanceChain.swift` for the strict-lint type-length cap.
//
// Every press and click below goes into `GameMetalView`, which is the object
// the window hands an event to. Nothing here reaches `CameraInputState`
// directly: a route that set the latch itself would be testing the latch rather
// than the binding, and the binding is exactly what a gate about "drivable
// without knowing a key" has to prove.

import AppKit
@testable import opensky
import Testing

@MainActor
extension M15AcceptanceChain {
    // MARK: - Input, through the shipping path

    func press(_ key: Key) {
        route(key, down: true)
    }

    func release(_ key: Key) {
        route(key, down: false)
    }

    /// One left-click, which is the attack binding. The first click of a
    /// session captures the pointer instead of attacking, exactly as it does in
    /// the app, so the caller gets the capture out of the way with
    /// `capturePointer()` before the fight starts.
    func clickAttack() {
        guard let event = Self.mouseEvent(type: .leftMouseDown) else { return }
        view.mouseDown(with: event)
        guard let up = Self.mouseEvent(type: .leftMouseUp) else { return }
        view.mouseUp(with: up)
    }

    /// Holds the attack button down, which is what draws a bow.
    func holdAttack() {
        guard let event = Self.mouseEvent(type: .leftMouseDown) else { return }
        view.mouseDown(with: event)
    }

    func releaseAttack() {
        guard let event = Self.mouseEvent(type: .leftMouseUp) else { return }
        view.mouseUp(with: event)
    }

    /// Right button down and up, which is the block binding.
    func setBlocking(_ blocking: Bool) {
        let type: NSEvent.EventType = blocking ? .rightMouseDown : .rightMouseUp
        guard let event = Self.mouseEvent(type: type) else { return }
        if blocking {
            view.rightMouseDown(with: event)
        } else {
            view.rightMouseUp(with: event)
        }
    }

    /// The click that grabs the pointer. Every later click is an attack.
    func capturePointer() {
        guard let event = Self.mouseEvent(type: .leftMouseDown) else { return }
        view.mouseDown(with: event)
        guard let up = Self.mouseEvent(type: .leftMouseUp) else { return }
        view.mouseUp(with: up)
    }

    func route(_ key: Key, down: Bool) {
        guard let event = Self.keyEvent(type: down ? .keyDown : .keyUp, key: key) else {
            Issue.record("AppKit refused to build a key event for \(key)")
            return
        }
        if down {
            view.keyDown(with: event)
        } else {
            view.keyUp(with: event)
        }
    }

    static func keyEvent(type: NSEvent.EventType, key: Key) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: key.rawValue
        )
    }

    static func mouseEvent(type: NSEvent.EventType) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }
}
