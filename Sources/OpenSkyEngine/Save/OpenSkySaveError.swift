// Failure modes of the OpenSky native save container (issue #161).
//
// The decoder never lets a `BinaryReaderError` escape: a reader failure means
// the file ran out of bytes somewhere the format required more, which is
// exactly `truncated(context:)`, and the context string names the structure
// that was being read. Callers therefore only ever have to switch over this
// one enum, and every case is `Equatable` so tests can assert the precise
// failure a given corruption produces.

import Foundation

nonisolated enum OpenSkySaveError: Error, Equatable {
    /// The first four bytes are not ASCII "OSAV".
    case badMagic
    /// The file declares a layout version this build does not implement.
    case unsupportedVersion(found: UInt32)
    /// The file ends inside a structure that required more bytes. `context`
    /// names that structure, for example "chunk header" or "plugin name".
    case truncated(context: String)
    /// A declared element count cannot fit in the bytes that remain, caught
    /// before any storage is reserved for it.
    case invalidCount(chunk: String, count: UInt32, remaining: Int)
    /// A field holds a value the format does not define — a boolean byte that
    /// is neither 0 nor 1, an unknown tag, or out-of-order component kinds.
    case invalidValue(context: String)
    /// A chunk's declared payload length runs past the end of the file.
    case chunkBoundsViolation(tag: String)
    /// The save was written against a different load order than the one now
    /// installed. `reason` explains the first difference in plain words.
    case fingerprintMismatch(reason: String)
}
