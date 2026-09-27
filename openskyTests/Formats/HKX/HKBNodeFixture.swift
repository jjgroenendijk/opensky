// Synthetic behavior-node packfile builder (todo 14.2). Lays out Havok objects
// at chosen offsets inside one `__data__` payload, registers each one's class
// through a virtual fixup, and patches pointers through the local and global
// fixup tables the way a real packfile does — pointers are null on disk and the
// fixup tables *are* the pointer values.
//
// Everything here is invented. No extracted game file is ever committed
// (AGENTS.md "Legal & IP boundary"); class-name signatures are synthetic
// hashes, as in HKXFixture, and the only real thing borrowed from Havok is the
// class *names* and the member offsets the decoders under test declare.

import Foundation
@testable import opensky

/// Builds one packfile holding arbitrary hkb objects. Offsets are the caller's
/// choice so an assertion can name the byte it reads.
struct HKBNodeFixture {
    /// Zero-filled object data; writes patch it in place.
    private var payload: Data
    /// Extra class-name entries beyond HKXFixture's three defaults, in the
    /// order they are added; the signature is a synthetic counter.
    private var extraClassNames: [(signature: UInt32, name: String)] = []
    private var localFixups: [HKXFixture.LocalFixup] = []
    private var globalFixups: [HKXFixture.GlobalFixup] = []
    /// (object offset, index into the full class-name table).
    private var registered: [(offset: Int, classIndex: Int)] = []

    /// HKXFixture's own defaults occupy class-name indices 0 through 2.
    private static let defaultClassCount = 3
    private static let firstSyntheticSignature: UInt32 = 0x5100_0000
    /// The `__data__` section index in every HKXFixture build.
    static let dataSection = 2

    init(payloadSize: Int) {
        payload = Data(count: payloadSize)
    }

    // MARK: - Objects

    /// Registers `className` at `offset` as a packfile object, adding the class
    /// to the name table on first use. Returns the pointer target callers use
    /// to decode it.
    @discardableResult
    mutating func addObject(_ className: String, at offset: Int) -> HKXPointerTarget {
        registered.append((offset: offset, classIndex: classIndex(for: className)))
        return HKXPointerTarget(sectionIndex: Self.dataSection, dataOffset: offset)
    }

    private mutating func classIndex(for className: String) -> Int {
        if let existing = extraClassNames.firstIndex(where: { $0.name == className }) {
            return Self.defaultClassCount + existing
        }
        let signature = Self.firstSyntheticSignature + UInt32(extraClassNames.count)
        extraClassNames.append((signature: signature, name: className))
        return Self.defaultClassCount + extraClassNames.count - 1
    }

    // MARK: - Scalar writes

    mutating func setUInt8(_ value: UInt8, at offset: Int) {
        write(Data([value]), at: offset)
    }

    mutating func setBool(_ value: Bool, at offset: Int) {
        setUInt8(value ? 1 : 0, at: offset)
    }

    mutating func setInt16(_ value: Int16, at offset: Int) {
        write(Data(withUnsafeBytes(of: value.littleEndian) { Data($0) }), at: offset)
    }

    mutating func setInt32(_ value: Int32, at offset: Int) {
        write(Data(withUnsafeBytes(of: value.littleEndian) { Data($0) }), at: offset)
    }

    mutating func setUInt32(_ value: UInt32, at offset: Int) {
        write(Data(withUnsafeBytes(of: value.littleEndian) { Data($0) }), at: offset)
    }

    mutating func setUInt64(_ value: UInt64, at offset: Int) {
        write(Data(withUnsafeBytes(of: value.littleEndian) { Data($0) }), at: offset)
    }

    mutating func setFloat(_ value: Float, at offset: Int) {
        setUInt32(value.bitPattern, at: offset)
    }

    mutating func setVector4(_ value: SIMD4<Float>, at offset: Int) {
        for lane in 0 ..< 4 {
            setFloat(value[lane], at: offset + lane * 4)
        }
    }

    private mutating func write(_ bytes: Data, at offset: Int) {
        precondition(
            offset >= 0 && offset + bytes.count <= payload.count,
            "fixture write at \(offset) runs past the \(payload.count)-byte payload"
        )
        payload.replaceSubrange(offset ..< (offset + bytes.count), with: bytes)
    }

    // MARK: - Pointers, strings, arrays

    /// Patches the 8-byte pointer at `offset` to `target` through the local
    /// fixup table, the way an intra-section pointer resolves.
    mutating func setPointer(at offset: Int, to target: Int) {
        localFixups.append(HKXFixture.LocalFixup(
            from: UInt32(offset), toOffset: UInt32(target)
        ))
    }

    /// Patches the pointer at `offset` through the *global* table to a section
    /// the file does not define, which is the `sectionMissing` miss case.
    mutating func setDanglingPointer(at offset: Int, toSection section: UInt32 = 9) {
        globalFixups.append(HKXFixture.GlobalFixup(
            from: UInt32(offset), toSection: section, toOffset: 0
        ))
    }

    /// Stores `value` as a NUL-terminated ASCII string at `storage` and points
    /// the hkStringPtr at `offset` to it.
    mutating func setString(_ value: String, at offset: Int, storage: Int) {
        var bytes = Data(value.utf8)
        bytes.append(0)
        write(bytes, at: storage)
        setPointer(at: offset, to: storage)
    }

    /// Fills an hkArray descriptor: pointer to `dataOffset`, `count` elements,
    /// and a capacity word. An empty array is left null with no fixup, which is
    /// how a packfile writes one, so `count == 0` writes nothing.
    mutating func setArray(at offset: Int, count: Int, dataOffset: Int) {
        setInt32(Int32(count), at: offset + 8)
        // Bit 31 of capacityAndFlags is a Havok owned-memory flag; the decoder
        // must read the size word rather than this one.
        setUInt32(UInt32(count) | 0x8000_0000, at: offset + 12)
        guard count > 0 else { return }
        setPointer(at: offset, to: dataOffset)
    }

    /// Fills an `hkArray<T*>` descriptor plus one local fixup per element, so
    /// the elements resolve as pointers to the given targets.
    mutating func setPointerArray(at offset: Int, dataOffset: Int, targets: [Int]) {
        setArray(at: offset, count: targets.count, dataOffset: dataOffset)
        for (index, target) in targets.enumerated() {
            setPointer(at: dataOffset + index * 8, to: target)
        }
    }

    // MARK: - Build

    /// Truncates the object payload to `count` bytes, so an object runs past
    /// the end of its section — the truncated-object case every class test
    /// exercises.
    mutating func truncatePayload(to count: Int) {
        payload = payload.prefix(count)
    }

    func buildFile() throws -> HKXFile {
        var fixture = HKXFixture()
        fixture.classNames += extraClassNames
        fixture.rootClassIndex = 2
        fixture.payloadOverride = payload
        fixture.localFixups = localFixups
        fixture.globalFixups = globalFixups
        // No auto-registered root object: every object in these fixtures is
        // registered explicitly so the class inventory is exactly the list
        // under test.
        fixture.rootObjectDataOffset = nil
        fixture.virtualFixups = registered.map { object in
            HKXFixture.VirtualFixup(
                dataOffset: UInt32(object.offset),
                classNameSection: 0,
                classNameOffset: UInt32(fixture.nameOffset(ofClass: object.classIndex))
            )
        }
        return try HKXFile(data: fixture.build())
    }

    func buildGraph() throws -> HKXObjectGraph {
        try HKXObjectGraph(file: buildFile())
    }
}
