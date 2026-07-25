// The stand-in host for milestone 8.3.2: it answers nothing and records
// everything. Every request the interpreter makes is appended to a bounded
// event list and declined, so a movie's demands on the display layer are
// measurable before the display layer exists.
//
// A later milestone replaces this with a host backed by a mutable display
// list. Nothing in the interpreter changes when it does.

import Foundation

/// One request the interpreter made of the host.
nonisolated enum AS2HostEvent: Equatable {
    case timeline(AS2TimelineCommand)
    case propertyRead(AS2DisplayProperty)
    case propertyWrite(AS2DisplayProperty)
    case pathRequest(String)
    case specialRequest(AS2SpecialTarget)
    case memberRead(String)
    case memberWrite(String)
}

/// Records host traffic and declines all of it.
nonisolated final class AS2RecordingHost: AS2Host {
    /// Events kept; the oldest are dropped once the list is full.
    let eventLimit: Int

    private(set) var events: [AS2HostEvent] = []
    /// Every event, including ones already dropped.
    private(set) var eventTotal = 0

    init(eventLimit: Int = 1024) {
        self.eventLimit = max(1, eventLimit)
    }

    var timelineCommands: [AS2TimelineCommand] {
        events.compactMap {
            guard case let .timeline(command) = $0 else {
                return nil
            }
            return command
        }
    }

    func perform(_ command: AS2TimelineCommand, target: AS2Object) {
        _ = target
        record(.timeline(command))
    }

    func property(_ property: AS2DisplayProperty, of target: AS2Value) -> AS2Value? {
        _ = target
        record(.propertyRead(property))
        return nil
    }

    func setProperty(
        _ property: AS2DisplayProperty,
        of target: AS2Value,
        to value: AS2Value
    ) -> Bool {
        _ = (target, value)
        record(.propertyWrite(property))
        return false
    }

    func targetPath(of object: AS2Object) -> String? {
        _ = object
        return nil
    }

    func object(atPath path: String, from origin: AS2Object) -> AS2Object? {
        _ = origin
        record(.pathRequest(path))
        return nil
    }

    func specialObject(_ kind: AS2SpecialTarget, relativeTo origin: AS2Object) -> AS2Object? {
        _ = origin
        record(.specialRequest(kind))
        return nil
    }

    func member(_ name: String, of object: AS2Object) -> AS2Value? {
        _ = object
        record(.memberRead(name))
        return nil
    }

    func setMember(_ name: String, of object: AS2Object, to value: AS2Value) -> Bool {
        _ = (object, value)
        record(.memberWrite(name))
        return false
    }

    func clear() {
        events.removeAll()
        eventTotal = 0
    }

    private func record(_ event: AS2HostEvent) {
        eventTotal += 1
        events.append(event)
        if events.count > eventLimit {
            events.removeFirst(events.count - eventLimit)
        }
    }
}
