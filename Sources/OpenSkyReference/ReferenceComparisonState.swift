// What the comparison view shows: both captures side by side, one at a time with a flip
// between them, or their difference picture. The launcher page draws it.

import Foundation

nonisolated public enum ReferenceComparisonMode: Equatable, Sendable {
    case sideBySide
    case flip
    case difference
}

nonisolated public enum ReferenceComparisonImage: Equatable, Sendable {
    case opensky
    case reference
    case difference
}

nonisolated public struct ReferenceComparisonState: Equatable, Sendable {
    public private(set) var mode = ReferenceComparisonMode.sideBySide
    /// In flip mode, whether the reference game shows instead of OpenSky.
    public private(set) var showsReference = false

    public init() {}

    /// Choosing flip again while in flip swaps the two games.
    public mutating func select(_ next: ReferenceComparisonMode) {
        showsReference = next == .flip && mode == .flip ? !showsReference : false
        mode = next
    }

    /// The first image, then the second one only side by side.
    public var images: [ReferenceComparisonImage] {
        switch mode {
        case .sideBySide: [.opensky, .reference]
        case .flip: [showsReference ? .reference : .opensky]
        case .difference: [.difference]
        }
    }

    public var caption: String {
        switch mode {
        case .sideBySide: "Left: OpenSky. Right: the reference game."
        case .flip: showsReference
            ? "The reference game. Flip again for OpenSky."
            : "OpenSky. Flip again for the reference game."
        case .difference: "Bright where the two differ, 4 times the channel difference."
        }
    }
}
