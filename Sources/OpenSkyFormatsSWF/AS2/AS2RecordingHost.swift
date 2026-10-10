// A host that answers nothing and records everything: each request goes into a
// bounded event list and is declined, so a movie's demands are measurable
// without a display layer.

import Foundation

/// One request the interpreter made of the host.
nonisolated public enum AS2HostEvent: Equatable, Sendable {
    case timeline(AS2TimelineCommand)
    case propertyRead(AS2DisplayProperty)
    case propertyWrite(AS2DisplayProperty)
    case pathRequest(String)
    case specialRequest(AS2SpecialTarget)
    case memberRead(String)
    case memberWrite(String)
}

/// Records host traffic and declines all of it.
nonisolated public final class AS2RecordingHost: AS2Host {
    /// Events kept; the oldest are dropped once the list is full.
    public let eventLimit: Int

    public private(set) var events: [AS2HostEvent] = []
    /// Every event, including ones already dropped.
    public private(set) var eventTotal = 0

    public init(eventLimit: Int = 1024) {
        self.eventLimit = max(1, eventLimit)
    }

    public var timelineCommands: [AS2TimelineCommand] {
        events.compactMap {
            guard case let .timeline(command) = $0 else {
                return nil
            }
            return command
        }
    }

    public func perform(_ command: AS2TimelineCommand, target: AS2Object) {
        _ = target
        record(.timeline(command))
    }

    public func property(_ property: AS2DisplayProperty, of target: AS2Value) -> AS2Value? {
        _ = target
        record(.propertyRead(property))
        return nil
    }

    public func setProperty(
        _ property: AS2DisplayProperty,
        of target: AS2Value,
        to value: AS2Value
    ) -> Bool {
        _ = (target, value)
        record(.propertyWrite(property))
        return false
    }

    public func targetPath(of object: AS2Object) -> String? {
        _ = object
        return nil
    }

    public func object(atPath path: String, from origin: AS2Object) -> AS2Object? {
        _ = origin
        record(.pathRequest(path))
        return nil
    }

    public func specialObject(
        _ kind: AS2SpecialTarget,
        relativeTo origin: AS2Object
    ) -> AS2Object? {
        _ = origin
        record(.specialRequest(kind))
        return nil
    }

    public func member(_ name: String, of object: AS2Object) -> AS2Value? {
        _ = object
        record(.memberRead(name))
        return nil
    }

    public func setMember(_ name: String, of object: AS2Object, to value: AS2Value) -> Bool {
        _ = (object, value)
        record(.memberWrite(name))
        return false
    }

    private func record(_ event: AS2HostEvent) {
        eventTotal += 1
        events.append(event)
        if events.count > eventLimit {
            events.removeFirst(events.count - eventLimit)
        }
    }
}
