// `.fuz` container framing for Skyrim SE voice lines: the `FUZE` header, the
// optional `.lip` lip-sync blob, and the xWMA audio payload that follows it.
// This type frames and validates only — it never decodes audio and never looks
// inside the lip blob. The audio payload is a complete RIFF/XWMA stream, so
// callers hand `audioData` straight to `XWMFile`; `lipData` is handed on
// untouched for the lip-sync work in item 17.7.
//
// References:
//   xEdit dev-4.1.6 Core/wbDataFormatMisc.pas, `dfFUZ` (read as documentation,
//   not transcribed):
//     https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDataFormatMisc.pas
//     dfStruct('FUZ', [ dfChars('Magic', 4, 'FUZE'), dfInteger('Version', dtU32,
//     '1'), dfInteger('LIP Size', dtU32), dfBytes('LIP Data', <LIP Size>),
//     dfBytes('XWM Data', 0) ])
//   CreationKit wiki, "How to generate voice files by batch" — `.fuz` is the
//   container the shipped tools build by stitching one `.xwm` and one `.lip`
//   together:
//     https://ck.uesp.net/wiki/How_to_generate_voice_files_by_batch
// Confirmed against the install's own bytes; layout and the sweep evidence are
// documented in docs/formats/fuz.md.

import Foundation

nonisolated enum FUZError: Error, Equatable {
    /// Input violates the documented layout.
    case malformed(String)
    /// Structurally valid `.fuz` in a variant OpenSky declines.
    case unsupported(String)
}

/// A framed `.fuz` file: the container version, the lip-sync blob and the
/// encoded audio payload. Parsing is bounds-checked throughout; malformed
/// input throws `FUZError` rather than trapping.
nonisolated struct FUZFile {
    private enum Layout {
        static let magic: FourCC = "FUZE"
        /// Magic + `Version` + `LIP Size`.
        static let headerSize = 12
        /// The only container version vanilla Skyrim SE writes, and the value
        /// xEdit's definition carries as the field default.
        static let supportedVersion: UInt32 = 1
    }

    /// `Version`. Always `1` in the vanilla corpus.
    let version: UInt32
    /// `LIP Data`, or nil when `LIP Size` is zero. A voice line whose INFO sets
    /// `noLipFile` ships with no lip blob, which is legal and common.
    let lipData: Data?
    /// `XWM Data`: the rest of the file, a complete RIFF/XWMA stream.
    let audioData: Data

    init(data: Data) throws {
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
    var lipByteCount: Int {
        lipData?.count ?? 0
    }

    var audioByteCount: Int {
        audioData.count
    }

    /// Frames the audio payload as xWMA. Separate from `init` so a framing
    /// sweep can report container failures apart from audio failures, and so
    /// the lip blob is reachable without paying for the RIFF walk.
    func audio() throws -> XWMFile {
        try XWMFile(data: audioData)
    }
}
