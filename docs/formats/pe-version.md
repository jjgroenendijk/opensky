---
type: File Format
title: Executable version resource
description: Where a Windows executable stores its file version, and how OpenSky reads the
  game build from SkyrimSE.exe without running it.
tags: [format, pe, launcher]
---

# Executable version resource

The game folder check shows which game build the install is. The build number is stamped in
`SkyrimSE.exe` as a version resource. OpenSky reads only the file headers and that one
resource. It never runs or loads the executable.

References: Microsoft, "PE Format" (the DOS stub, the COFF header, the section table, and
the `.rsrc` section), and the Win32 reference pages for `VS_VERSIONINFO` and
`VS_FIXEDFILEINFO`. All integers are little-endian.

## Headers and the resource section

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 2 | `MZ` |
| 0x3C | 4 | File offset of the PE signature |
| PE + 0 | 4 | `PE\0\0` |
| PE + 6 | 2 | Number of sections |
| PE + 20 | 2 | Size of the optional header |
| PE + 24 + optional size | 40 each | The section table |

A section table entry holds the name (8 bytes), the virtual size, the virtual address, the
raw size, and the raw file offset, then 16 bytes OpenSky does not read. The section named
`.rsrc` holds the resources.

## The resource tree

The resources form a tree of three levels: type, name, and language. Each directory is 16
bytes; the counts of named and numbered entries are the two `UInt16` values at offset 12.
Eight-byte entries follow: an id, then an offset into the section. When the top bit of the
offset is set, the offset points at the next directory. Otherwise it points at a data entry:
an RVA, a size, a code page, and a reserved word. The file offset of the data is the RVA
minus the section's virtual address, plus its raw offset.

The version resource has type 16. OpenSky takes the first name and the first language.

## The version block

`VS_VERSIONINFO` starts with three `UInt16` values (length, value length, type), then the
UTF-16 key `VS_VERSION_INFO` with its terminator, then padding to a 4-byte boundary. The
`VS_FIXEDFILEINFO` follows:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | Signature `0xFEEF04BD` |
| 4 | 4 | Structure version |
| 8 | 4 | File version, high: major << 16, minor |
| 12 | 4 | File version, low: build << 16, revision |

## Confirmed on the real install

A probe over the Steam install's `SkyrimSE.exe` found eight sections, `.rsrc` among them,
one version resource at type 16, name 1, language 1033, and the signature at the padded
offset. The file version read `1.6.1170.0`.
