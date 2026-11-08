// Line reader shared by the two `meshes\animationdata` text files.
// Layout: docs/formats/animation-data.md.

import Foundation

nonisolated public enum AnimationDataError: Error, Equatable, Sendable {
    /// The 1-based line, and what it should have held.
    case malformed(line: Int, expected: String)
}

/// The lines of a text file, without line ends, read front to back.
nonisolated struct AnimationDataLines {
    private let lines: [Substring]
    private(set) var position = 0

    init(_ text: String) {
        // `\r\n` is one `Character`, so split on any line end, not on `\n`.
        lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    var isAtEnd: Bool {
        lines[position...].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    mutating func text(_ expected: String) throws -> String {
        guard position < lines.count else { throw failure(expected) }
        defer { position += 1 }
        return String(lines[position])
    }

    mutating func integer(_ expected: String) throws -> Int {
        guard let value = try Int(text(expected).trimmingCharacters(in: .whitespaces)) else {
            throw AnimationDataError.malformed(line: position, expected: expected)
        }
        return value
    }

    /// A count that the rest of the file can hold; a wild count is a malformed file.
    mutating func count(_ expected: String) throws -> Int {
        let value = try integer(expected)
        guard value >= 0, value <= lines.count - position else {
            throw AnimationDataError.malformed(line: position, expected: expected)
        }
        return value
    }

    /// Whitespace-separated numbers, exactly `count` of them.
    mutating func floats(_ count: Int, _ expected: String) throws -> [Float] {
        let values = try text(expected).split(separator: " ").compactMap { Float($0) }
        guard values.count == count else {
            throw AnimationDataError.malformed(line: position, expected: expected)
        }
        return values
    }

    /// Skips the blank lines between blocks.
    mutating func skipBlank() {
        while position < lines.count, lines[position].trimmingCharacters(in: .whitespaces).isEmpty {
            position += 1
        }
    }

    func failure(_ expected: String) -> AnimationDataError {
        .malformed(line: position + 1, expected: expected)
    }
}
