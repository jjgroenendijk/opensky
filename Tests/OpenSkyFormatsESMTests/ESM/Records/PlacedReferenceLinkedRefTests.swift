// XLKR (linked reference) decode on REFR, over synthetic bytes. Layout: UESP
// "Skyrim Mod:Mod File Format/REFR" and xEdit dev-4.1.6 wbDefinitionsTES5.pas;
// see docs/formats/placed-references.md.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
import Testing

struct PlacedReferenceLinkedRefTests {
    private static let keyword = FormID(0x0006_5EBB)
    private static let target = FormID(0x0001_2345)

    private func xlkr(keyword: UInt32?, ref: UInt32) -> Data {
        var payload = Data()
        if let keyword {
            payload.appendUInt32(keyword)
        }
        payload.appendUInt32(ref)
        return ESMFixture.field("XLKR", payload)
    }

    @Test func decodesKeywordedLinkedReference() throws {
        let refr = try PlacedReferenceFixture.reference(
            xlkr(keyword: Self.keyword.rawValue, ref: Self.target.rawValue)
        )
        #expect(refr.linkedReferences.count == 1)
        #expect(refr.linkedReferences.first?.keyword == Self.keyword)
        #expect(refr.linkedReferences.first?.ref == Self.target)
        #expect(refr.linkedReference(keyword: Self.keyword) == Self.target)
        // The keyword-less lookup must not fall back to a tagged link.
        #expect(refr.linkedReference() == nil)
    }

    @Test func decodesShortFormLinkedReference() throws {
        let refr = try PlacedReferenceFixture.reference(xlkr(
            keyword: nil,
            ref: Self.target.rawValue
        ))
        #expect(refr.linkedReferences == [
            PlacedReference.LinkedReference(keyword: nil, ref: Self.target)
        ])
        #expect(refr.linkedReference() == Self.target)
    }

    /// An 8-byte entry whose keyword slot holds the null FormID is the same
    /// untagged link as the 4-byte form, so both decode to `keyword == nil`.
    @Test func nullKeywordSlotDecodesAsUntagged() throws {
        let refr = try PlacedReferenceFixture.reference(xlkr(keyword: 0, ref: Self.target.rawValue))
        #expect(refr.linkedReferences.first?.keyword == nil)
        #expect(refr.linkedReference() == Self.target)
    }

    @Test func collectsRepeatedLinkedReferencesInFileOrder() throws {
        let fields = xlkr(keyword: Self.keyword.rawValue, ref: 0x0000_00AA)
            + xlkr(keyword: nil, ref: 0x0000_00BB)
            + xlkr(keyword: 0x0000_0077, ref: 0x0000_00CC)
        let refr = try PlacedReferenceFixture.reference(fields)
        #expect(refr.linkedReferences.map(\.ref) == [
            FormID(0x0000_00AA), FormID(0x0000_00BB), FormID(0x0000_00CC)
        ])
        #expect(refr.linkedReferences.map(\.keyword) == [
            Self.keyword, nil, FormID(0x0000_0077)
        ])
        #expect(refr.linkedReference() == FormID(0x0000_00BB))
        #expect(refr.linkedReference(keyword: FormID(0x0000_0077)) == FormID(0x0000_00CC))
        #expect(refr.linkedReference(keyword: FormID(0x0000_DEAD)) == nil)
    }

    /// A payload too short for even one FormID is dropped, not thrown: XLKR is
    /// an optional repeating link, so a mod quirk costs one link and never the
    /// whole reference.
    @Test func skipsTruncatedLinkedReference() throws {
        let refr = try PlacedReferenceFixture.reference(ESMFixture.field("XLKR", Data(count: 3)))
        #expect(refr.linkedReferences.isEmpty)
        #expect(refr.linkedReference() == nil)
        #expect(refr.base == FormID(0x0002_D4E2))
    }

    /// Five to seven bytes cannot hold the 8-byte struct, so the leading
    /// FormID is taken as the short form and the trailing bytes are ignored.
    @Test func decodesShortFormWhenTrailingBytesCannotCompleteTheStruct() throws {
        var payload = Data()
        payload.appendUInt32(Self.target.rawValue)
        payload.append(Data(count: 2))
        let refr = try PlacedReferenceFixture.reference(ESMFixture.field("XLKR", payload))
        #expect(refr.linkedReference() == Self.target)
    }

    @Test func absentLinkedReferenceLeavesTheListEmpty() throws {
        let refr = try PlacedReferenceFixture.reference(Data())
        #expect(refr.linkedReferences.isEmpty)
        #expect(refr.linkedReference() == nil)
    }

    /// XLKR must be matched before the VMAD catch-all, and adding the case
    /// must not steal script attachments from it.
    @Test func linkedReferenceCoexistsWithScriptAttachments() throws {
        let script = VMADFixture.Script("OpenSkyProbe", properties: [])
        let vmad = ESMFixture.field("VMAD", VMADFixture.payload(scripts: [script]))
        let refr = try PlacedReferenceFixture.reference(
            vmad + xlkr(keyword: Self.keyword.rawValue, ref: Self.target.rawValue)
        )
        #expect(refr.linkedReference(keyword: Self.keyword) == Self.target)
        #expect(refr.scriptData.scripts.map(\.name) == ["OpenSkyProbe"])
    }
}
