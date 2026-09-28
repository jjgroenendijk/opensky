// Standard SWF tag-code -> name table, per the Adobe spec's tag list. Used to
// report a known/unknown tally when sweeping the game's Interface .swf files.
//
// Reference: Adobe SWF File Format Specification, version 19, "Appendix:
// Reserved and undocumented tags" and the per-chapter tag definitions.
//
// Scaleform GFx (the runtime Skyrim's UI actually targets) adds its own
// extension tags in the ~1000+ code range. Those are deliberately absent from
// the Adobe specification and therefore stay "unknown" here — decoding them is
// out of scope for the container milestone.

import Foundation

nonisolated enum SWFTagName {
    /// Human-readable name for a standard Adobe tag code, or `nil` when the
    /// code is not in the Adobe specification (reserved, or a GFx extension).
    static func name(forCode code: UInt16) -> String? {
        names[code]
    }

    /// Whether `code` is a standard Adobe tag.
    static func isKnown(_ code: UInt16) -> Bool {
        names[code] != nil
    }

    private static let names: [UInt16: String] = [
        0: "End",
        1: "ShowFrame",
        2: "DefineShape",
        4: "PlaceObject",
        5: "RemoveObject",
        6: "DefineBits",
        7: "DefineButton",
        8: "JPEGTables",
        9: "SetBackgroundColor",
        10: "DefineFont",
        11: "DefineText",
        12: "DoAction",
        13: "DefineFontInfo",
        14: "DefineSound",
        15: "StartSound",
        17: "DefineButtonSound",
        18: "SoundStreamHead",
        19: "SoundStreamBlock",
        20: "DefineBitsLossless",
        21: "DefineBitsJPEG2",
        22: "DefineShape2",
        23: "DefineButtonCxform",
        24: "Protect",
        26: "PlaceObject2",
        28: "RemoveObject2",
        32: "DefineShape3",
        33: "DefineText2",
        34: "DefineButton2",
        35: "DefineBitsJPEG3",
        36: "DefineBitsLossless2",
        37: "DefineEditText",
        39: "DefineSprite",
        43: "FrameLabel",
        45: "SoundStreamHead2",
        46: "DefineMorphShape",
        48: "DefineFont2",
        56: "ExportAssets",
        57: "ImportAssets",
        58: "EnableDebugger",
        59: "DoInitAction",
        60: "DefineVideoStream",
        61: "VideoFrame",
        62: "DefineFontInfo2",
        64: "EnableDebugger2",
        65: "ScriptLimits",
        66: "SetTabIndex",
        69: "FileAttributes",
        70: "PlaceObject3",
        71: "ImportAssets2",
        73: "DefineFontAlignZones",
        74: "CSMTextSettings",
        75: "DefineFont3",
        76: "SymbolClass",
        77: "Metadata",
        78: "DefineScalingGrid",
        82: "DoABC",
        83: "DefineShape4",
        84: "DefineMorphShape2",
        86: "DefineSceneAndFrameLabelData",
        87: "DefineBinaryData",
        88: "DefineFontName",
        89: "StartSound2",
        90: "DefineBitsJPEG4",
        91: "DefineFont4",
        93: "EnableTelemetry"
    ]
}
