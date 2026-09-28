// NAVM record: the walkable surface an actor paths across. One navmesh per
// interior cell and per exterior cell square; the whole set is indexed by the
// single NAVI record (`NavmeshInfoMap`).
//
// The record carries one payload that matters, NVNM, decoded by
// `NavmeshGeometry` in the neighbouring file. NVNM routinely exceeds the
// 16-bit field size in `Skyrim.esm`, so it arrives through the `XXXX`
// size-extension path `ESMField.parseAll` already folds away — an oversized
// navmesh is what that code was written for.
//
// NVNM, variable size. Every count below is a uint32 immediately preceding its
// array, and every array is tightly packed:
//   00 uint32  version (12 in every vanilla record)
//   04 uint32  CRC hash of the literal "PathingCell"; a constant marker
//   08 FormID  parent worldspace, null for an interior
//   0C union   parent world null -> FormID of the parent CELL
//              parent world set  -> int16 grid Y then int16 grid X (reversed,
//                                   the same order GRUP exterior-block labels
//                                   use)
//   then       uint32 count + count * (float32 x, y, z)      vertices
//   then       uint32 count + count * 16-byte triangle:
//                00 uint16 vertex 0    06 int16 edge 1-2 neighbour
//                02 uint16 vertex 1    08 int16 edge 2-0 neighbour
//                04 uint16 vertex 2    0A uint16 flags
//                06 int16 edge 0-1     0C uint16 cover flags
//              (a neighbour of -1 means the edge borders nothing)
//   then       uint32 count + count * 10-byte edge link:
//                00 uint32 type   04 FormID navmesh   08 int16 triangle
//              (the triangle indexes the navmesh named at 04, not this one —
//               see the census finding on `NavmeshGeometry.EdgeLink`)
//   then       uint32 count + count * 10-byte door link:
//                00 int16 triangle   02 uint32 CRC hash of "PathingDoor"
//                06 FormID door REFR
//   then       uint32 count + count * int16            cover triangles
//   then       the navmesh grid:
//                00 uint32  divisor
//                04 float32 grid size X, 08 float32 grid size Y
//                0C float32[3] bounds minimum
//                18 float32[3] bounds maximum
//                24 divisor*divisor lists, each uint32 count + count * int16
//
// Skipped, decoded far enough to validate and then discarded: the two CRC-hash
// markers (constants), the per-triangle cover flags' internal nibble layout
// (kept as a raw uint16), the cover-triangle list, and the navmesh grid's
// per-square triangle lists — the grid is an acceleration structure for a
// query OpenSky does not run yet, so only its divisor, extent and bounds are
// retained. Skipped outright: ONAM base objects, PNAM preferred connectors and
// NNAM non-connectors, none of which pathing (16.2) reads.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/NAVM"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NAVM
//   UESP "Skyrim Mod:Mod File Format/NVNM Field"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVNM_Field
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas — `wbNVNM` at line 5557 and
//     `wbRecord(NAVM, ...)` at line 5655; the parent union's rule is
//     `wbNVNMParentDecider` in Core/wbDefinitionsCommon.pas line 5372, which
//     switches on the parent worldspace being null. UESP instead claims the
//     switch is on the worldspace equalling 0x0000003C (Tamriel), which cannot
//     be right for the other worldspaces; the census probe confirms xEdit.
// Layout documented in docs/formats/navmesh.md.

import Foundation

/// Where a navmesh sits in the world. Interiors name their CELL directly;
/// exteriors name a worldspace and the cell square inside it, because an
/// exterior navmesh is authored per grid square rather than per CELL record.
nonisolated enum NavmeshLocation: Hashable, Sendable {
    case interior(cell: FormID)
    case exterior(world: FormID, x: Int32, y: Int32)
}

nonisolated struct Navmesh: Sendable {
    let formID: FormID
    let editorID: String?
    /// NVNM. Required: a NAVM without geometry is structurally unusable, so
    /// its absence is a decode error rather than an empty mesh.
    let geometry: NavmeshGeometry

    init(record: ESMRecord) throws {
        guard record.type == "NAVM" else {
            throw ESMError.malformed("expected NAVM record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var geometry: NavmeshGeometry?
        for field in try record.fields() {
            switch field.type {
            case "EDID":
                var reader = BinaryReader(field.data)
                editorID = try reader.readZString()
            case "NVNM":
                geometry = try NavmeshGeometry(data: field.data)
            // Skipped: ONAM, PNAM, NNAM (see the header note).
            default:
                break
            }
        }
        guard let geometry else {
            throw ESMError.malformed("NAVM \(FormID(record.formID)) has no NVNM field")
        }
        self.editorID = editorID
        self.geometry = geometry
    }
}
