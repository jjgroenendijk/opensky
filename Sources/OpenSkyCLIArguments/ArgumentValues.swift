// Typed option values. The parser rejects a bad value before a command loads any game
// data, and the help lists every choice.

import ArgumentParser
import Foundation

/// `WxH`, such as `1280x720`. Each side is 1 to 8192, so a typo cannot ask the GPU for a
/// texture it can never allocate.
public struct PixelSize: ExpressibleByArgument, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public init?(argument: String) {
        let parts = argument.lowercased().split(separator: "x")
        guard
            parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]),
            (1 ... 8192).contains(width), (1 ... 8192).contains(height)
        else { return nil }
        self.init(width: width, height: height)
    }

    public static let defaultView = PixelSize(width: 1280, height: 720)
}

/// A comma-separated list, such as `a,b,c`. Empty items are dropped.
public struct CommaList: ExpressibleByArgument, Equatable, Sendable {
    public let items: [String]

    public init(_ items: [String]) {
        self.items = items
    }

    public init?(argument: String) {
        let items = argument.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        self.init(items)
    }
}

public enum GraphicsPresetName: String, CaseIterable, ExpressibleByArgument, Sendable {
    case low, medium, high, ultra
}

public enum PreviewStage: String, CaseIterable, ExpressibleByArgument, Sendable {
    case studio, cell
}

public enum TextureQualityName: String, CaseIterable, ExpressibleByArgument, Sendable {
    case original, high, medium, low
}

public enum BenchmarkPresetName: String, CaseIterable, ExpressibleByArgument, Sendable {
    case quick, standard, full
}

public enum SurvivalModeAnswer: String, CaseIterable, ExpressibleByArgument, Sendable {
    case on, off, ask
}

public enum ContainerMenuMode: String, CaseIterable, ExpressibleByArgument, Sendable {
    case container, barter
}

public enum ContainerMenuSide: String, CaseIterable, ExpressibleByArgument, Sendable {
    case container, player
}

public enum ObjectiveStateName: String, CaseIterable, ExpressibleByArgument, Sendable {
    case completed, failed
}

/// Range checks shared by `validate()` implementations, so each error names its option.
enum OptionCheck {
    static func range<Value: Comparable>(
        _ value: Value?, _ range: ClosedRange<Value>, _ option: String
    ) throws {
        guard let value, !range.contains(value) else { return }
        throw ValidationError(
            "\(option) expects \(range.lowerBound) to \(range.upperBound), got \(value)"
        )
    }

    static func atLeast<Value: Comparable>(
        _ value: Value?,
        _ minimum: Value,
        _ option: String
    ) throws {
        guard let value, value < minimum else { return }
        throw ValidationError("\(option) expects at least \(minimum), got \(value)")
    }
}
