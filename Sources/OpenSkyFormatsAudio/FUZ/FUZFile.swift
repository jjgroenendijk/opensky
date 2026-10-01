// `.fuz` voice file framing: the `FUZE` header, the optional `.lip` blob, and
// the xWMA payload. It only frames: `audioData` goes to `XWMFile`, and
// `lipData` is passed on unread. Layout and sources: docs/formats/fuz.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum FUZError: Error, Equatable, Sendable {
    /// Input violates the documented layout.
    case malformed(String)
    /// Structurally valid `.fuz` in a variant OpenSky declines.
    case unsupported(String)
}

/// A framed `.fuz` file: the container version, the lip-sync blob and the
/// encoded audio payload. Parsing is bounds-checked throughout; malformed
/// input throws `FUZError` rather than trapping.
nonisolated public struct FUZFile: Sendable {
    private enum Layout {
        static let magic: FourCC = "FUZE"
        /// Magic + `Version` + `LIP Size`.
        static let headerSize = 12
        /// The only container version vanilla Skyrim SE writes, and the value
        /// xEdit's definition carries as the field default.
        static let supportedVersion: UInt32 = 1
    }

    /// `Version`. Always `1` in the vanilla corpus.
    public let version: UInt32
    /// `LIP Data`, or nil when `LIP Size` is zero. A voice line whose INFO sets
    /// `noLipFile` ships with no lip blob, which is legal and common.
    public let lipData: Data?
    /// `XWM Data`: the rest of the file, a complete RIFF/XWMA stream.
    public let audioData: Data

    public init(data: Data) throws {
        var reader = BinaryReader(data)
        let magic: FourCC
        do {
            magic = try reader.readFourCC()
        } catch {
            throw FUZError.malformed("file is shorter than the 12-byte FUZE header")
        }
        guard magic == Layout.magic else {
            throw FUZError.malformed("magic is \(magic), expected \(Layout.magic)")
        }
        let version: UInt32
        let declaredLipSize: UInt32
        do {
            version = try reader.readUInt32()
            declaredLipSize = try reader.readUInt32()
        } catch {
            throw FUZError.malformed("file is shorter than the 12-byte FUZE header")
        }
        guard version == Layout.supportedVersion else {
            throw FUZError.unsupported("container version \(version)")
        }
        // `LIP Size` is a UInt32 read from an external file: widen before
        // comparing so a 4 GB claim cannot overflow the offset arithmetic.
        let lipSize = Int(declaredLipSize)
        let available = data.count - Layout.headerSize
        guard lipSize <= available else {
            throw FUZError.malformed(
                "LIP Size \(lipSize) overruns the file (\(available) bytes after the header)"
            )
        }
        let lip = try reader.read(count: lipSize)
        let audio = try reader.read(count: available - lipSize)
        guard !audio.isEmpty else {
            throw FUZError.malformed("no audio payload after \(lipSize) lip bytes")
        }
        self.version = version
        lipData = lip.isEmpty ? nil : lip
        audioData = audio
    }
}

nonisolated extension FUZFile {
    public var lipByteCount: Int {
        lipData?.count ?? 0
    }

    public var audioByteCount: Int {
        audioData.count
    }

    /// Frames the audio payload as xWMA. Separate from `init` so a framing
    /// sweep can report container failures apart from audio failures, and so
    /// the lip blob is reachable without paying for the RIFF walk.
    public func audio() throws -> XWMFile {
        try XWMFile(data: audioData)
    }
}
