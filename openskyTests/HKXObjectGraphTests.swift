// Shared HKX object-graph resolution tests (todo 14.1) over synthetic in-code
// packfiles — never extracted game files (AGENTS.md "Legal & IP boundary").
// Covers the three operations every class decoder shares: pointer resolution
// through local and global fixups, hkArray element location, and in-place
// cstring reads, plus the rule that an unresolvable field yields nil and a
// recorded reason rather than a trap. Byte map: docs/formats/hkx-behavior.md.

import Foundation
@testable import opensky
import Testing

/// One synthetic object exercising every cursor accessor at a known offset.
/// The payload is laid out by hand so each assertion names the byte it reads.
private enum HKXCursorFixture {
    /// Member offsets inside the object at data offset 0.
    static let localPointer = HKXField(0x00, "m_localPointer")
    static let globalPointer = HKXField(0x08, "m_globalPointer")
    static let nullPointer = HKXField(0x10, "m_nullPointer")
    static let indexArray = HKXField(0x20, "m_indexArray")
    static let negativeArray = HKXField(0x30, "m_negativeArray")
    static let pointerArray = HKXField(0x40, "m_pointerArray")
    static let scalar = HKXField(0x50, "m_scalar")
    static let realValue = HKXField(0x54, "m_realValue")
    static let pastEnd = HKXField(0x400, "m_pastEnd")

    /// Section-local offsets of the data the fixups target.
    static let stringOffset = 0x80
    static let indexDataOffset = 0xA0
    static let pointerDataOffset = 0xC0
    static let payloadSize = 0x100

    static func payload() -> Data {
        var payload = Data(count: payloadSize)
        // hkArray sizes: element count sits at the descriptor's offset + 8.
        payload.replaceSubrange(0x28 ..< 0x2C, with: littleEndian(UInt32(3)))
        payload.replaceSubrange(0x38 ..< 0x3C, with: littleEndian(UInt32(bitPattern: -1)))
        payload.replaceSubrange(0x48 ..< 0x4C, with: littleEndian(UInt32(2)))
        payload.replaceSubrange(0x50 ..< 0x54, with: littleEndian(UInt32(0x1234_5678)))
        payload.replaceSubrange(
            0x54 ..< 0x58, with: littleEndian(Float(2.5).bitPattern)
        )
        let name = Data("LocalName".utf8) + Data([0])
        payload.replaceSubrange(stringOffset ..< stringOffset + name.count, with: name)
        for (index, value) in [Int16(7), Int16(-2), Int16(9)].enumerated() {
            let start = indexDataOffset + index * 2
            payload.replaceSubrange(
                start ..< start + 2, with: littleEndian(UInt16(bitPattern: value))
            )
        }
        return payload
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func littleEndian(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// Builds the packfile. The global fixups point into `__classnames__`
    /// (section 0), whose payload is the class-name blob, so a cross-section
    /// string read lands on a real NUL-terminated name.
    static func file() throws -> (file: HKXFile, classNameOffset: Int) {
        var fixture = HKXFixture()
        fixture.payloadOverride = payload()
        let classNameOffset = fixture.nameOffset(ofClass: 0)
        fixture.localFixups = [
            HKXFixture.LocalFixup(from: 0x00, toOffset: UInt32(stringOffset)),
            HKXFixture.LocalFixup(from: 0x20, toOffset: UInt32(indexDataOffset)),
            HKXFixture.LocalFixup(from: 0x40, toOffset: UInt32(pointerDataOffset)),
            HKXFixture.LocalFixup(
                from: UInt32(pointerDataOffset), toOffset: UInt32(stringOffset)
            )
        ]
        fixture.globalFixups = [
            HKXFixture.GlobalFixup(from: 0x08, toSection: 0, toOffset: UInt32(classNameOffset)),
            HKXFixture.GlobalFixup(
                from: UInt32(pointerDataOffset + 8), toSection: 0,
                toOffset: UInt32(classNameOffset)
            )
        ]
        return try (HKXFile(data: fixture.build()), classNameOffset)
    }
}

@Suite("HKX object graph")
struct HKXObjectGraphTests {
    private func cursor() throws -> (HKXObjectCursor, Int) {
        let (file, classNameOffset) = try HKXCursorFixture.file()
        let graph = try HKXObjectGraph(file: file)
        let object = try #require(graph.objects(ofClass: "hkRootLevelContainer").first)
        return try (#require(graph.cursor(at: object)), classNameOffset)
    }

    @Test("Local fixup resolves a pointer inside the same section")
    func localPointerResolves() throws {
        var (cursor, _) = try cursor()
        #expect(cursor.pointer(at: HKXCursorFixture.localPointer)
            == HKXPointerTarget(sectionIndex: 2, dataOffset: 0x80))
        #expect(cursor.unresolved.isEmpty)
    }

    @Test("Global fixup resolves a pointer into another section")
    func globalPointerResolvesAcrossSections() throws {
        var (cursor, classNameOffset) = try cursor()
        #expect(cursor.pointer(at: HKXCursorFixture.globalPointer)
            == HKXPointerTarget(sectionIndex: 0, dataOffset: classNameOffset))
    }

    @Test("Cross-section string reads the target section's payload")
    func stringReadsAcrossSections() throws {
        var (cursor, _) = try cursor()
        #expect(cursor.string(at: HKXCursorFixture.localPointer) == "LocalName")
        #expect(cursor.string(at: HKXCursorFixture.globalPointer) == "hkClass")
    }

    @Test("Unresolvable pointer yields nil and records the reason")
    func nullPointerRecordsMiss() throws {
        var (cursor, _) = try cursor()
        #expect(cursor.pointer(at: HKXCursorFixture.nullPointer) == nil)
        #expect(cursor.unresolved == [HKXUnresolvedReference(
            sectionIndex: 2, objectOffset: 0, field: "m_nullPointer", miss: .noFixup
        )])
    }

    @Test("Read past the section payload yields nil and records the reason")
    func outOfBoundsRecordsMiss() throws {
        var (cursor, _) = try cursor()
        #expect(cursor.int32(at: HKXCursorFixture.pastEnd) == nil)
        #expect(cursor.unresolved.map(\.miss) == [.outOfBounds])
    }

    @Test("Negative hkArray size yields nil and records the reason")
    func negativeArrayCountRecordsMiss() throws {
        var (cursor, _) = try cursor()
        #expect(cursor.arrayCount(at: HKXCursorFixture.negativeArray) == nil)
        #expect(cursor.unresolved.map(\.miss) == [.negativeCount])
    }

    @Test("hkArray descriptor locates its elements")
    func arrayDescriptorLocatesElements() throws {
        var (cursor, _) = try cursor()
        #expect(cursor.arrayCount(at: HKXCursorFixture.indexArray) == 3)
        #expect(cursor.array(at: HKXCursorFixture.indexArray) == HKXArrayView(
            sectionIndex: 2, dataOffset: HKXCursorFixture.indexDataOffset, count: 3
        ))
        #expect(cursor.int16Array(at: HKXCursorFixture.indexArray) == [7, -2, 9])
    }

    @Test("Pointer array resolves each element, local and global alike")
    func pointerArrayResolvesEachElement() throws {
        var (cursor, classNameOffset) = try cursor()
        #expect(cursor.pointerArray(at: HKXCursorFixture.pointerArray) == [
            HKXPointerTarget(sectionIndex: 2, dataOffset: 0x80),
            HKXPointerTarget(sectionIndex: 0, dataOffset: classNameOffset)
        ])
    }

    @Test("Scalar members read at their declared offsets")
    func scalarsReadAtOffsets() throws {
        var (cursor, _) = try cursor()
        #expect(cursor.uint32(at: HKXCursorFixture.scalar) == 0x1234_5678)
        #expect(cursor.float32(at: HKXCursorFixture.realValue) == 2.5)
    }

    @Test("Object class names resolve by location")
    func classNamesResolveByLocation() throws {
        let (file, _) = try HKXCursorFixture.file()
        let graph = try HKXObjectGraph(file: file)
        let target = HKXPointerTarget(sectionIndex: 2, dataOffset: 0)
        #expect(graph.className(at: target) == "hkRootLevelContainer")
        #expect(graph.className(at: HKXPointerTarget(sectionIndex: 2, dataOffset: 0x80)) == nil)
    }
}
