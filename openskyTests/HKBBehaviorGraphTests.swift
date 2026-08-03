// Behavior graph-level decode + census tests (todo 14.1) over a synthetic
// in-code packfile — never an extracted game file (AGENTS.md "Legal & IP
// boundary"). Every name below is invented; the byte layout follows
// docs/formats/hkx-behavior.md. Class-name signatures are invented hashes, as
// in HKXFixture.

import Foundation
@testable import opensky
import Testing

/// Hand-builds one behavior packfile: root container -> named variant ->
/// hkbBehaviorGraph -> graph data -> string data plus variable value set, with
/// a stub root generator object so the graph's `m_rootGenerator` resolves to a
/// registered class. Object offsets are laid out on 0x20 boundaries so an
/// assertion can name the byte it reads.
struct HKBBehaviorFixture {
    // Object bases inside the __data__ payload.
    static let rootContainer = 0x000
    static let namedVariant = 0x020
    static let behaviorGraph = 0x100
    static let graphData = 0x240
    static let variableValueSet = 0x400
    static let stringData = 0x500
    static let rootGenerator = 0x600
    static let payloadSize = 0x640

    // Data blobs the fixups target.
    private static let variantNameString = 0x040
    private static let variantClassNameString = 0x060
    private static let graphNameString = 0x080
    private static let variableInfoData = 0x300
    private static let eventInfoData = 0x320
    private static let wordValueData = 0x340
    private static let quadValueData = 0x360
    private static let eventNamePointers = 0x380
    private static let variableNamePointers = 0x390
    private static let eventNameStrings = [0x560, 0x570]
    private static let variableNameStrings = [0x580, 0x590, 0x5A0]

    var graphName = "TestBehaviorGraph"
    var variantName = "TestVariant"
    var userData: UInt64 = 0xABCD
    var variableMode = 1
    var eventNames = ["TestEventAlpha", "TestEventBeta"]
    var variableNames = ["bTestFlag", "iTestState", "fTestSpeed"]
    /// Declared types, parallel to `variableNames`: bool, int32, real.
    var variableTypes: [Int8] = [0, 3, 4]
    var eventFlags: [UInt32] = [1, 2]
    var wordValues: [Int32] = [1, 42, Int32(bitPattern: Float(0.5).bitPattern)]
    var quadValue = SIMD4<Float>(1, 2, 3, 4)
    /// Drops the string-data pointer so a graph with unresolvable naming still
    /// decodes and reports the miss.
    var omitStringDataPointer = false

    /// Class-name table: index 2 is the container root, the rest register the
    /// objects laid out below.
    private static let classNames: [(signature: UInt32, name: String)] = [
        (0x0BD4_C87B, "hkClass"),
        (0x0B5F_0E29, "hkClassMember"),
        (0x6DAB_825E, "hkRootLevelContainer"),
        (0x11A2_3C40, "hkbBehaviorGraph"),
        (0x11A2_3C41, "hkbBehaviorGraphData"),
        (0x11A2_3C42, "hkbVariableValueSet"),
        (0x11A2_3C43, "hkbBehaviorGraphStringData"),
        (0x11A2_3C44, "hkbStateMachine")
    ]

    func build() throws -> HKXFile {
        var fixture = HKXFixture()
        fixture.classNames = Self.classNames
        fixture.rootClassIndex = 2
        fixture.payloadOverride = payload()
        fixture.localFixups = localFixups()
        fixture.globalFixups = []
        fixture.virtualFixups = virtualFixups(fixture: fixture)
        return try HKXFile(data: fixture.build())
    }

    func graph() throws -> HKXObjectGraph {
        try HKXObjectGraph(file: build())
    }

    // MARK: - Payload

    private func payload() -> Data {
        var payload = Data(count: Self.payloadSize)
        // hkRootLevelContainer: one named variant.
        payload.writeUInt32(1, at: Self.rootContainer + 0x08)

        // hkbBehaviorGraph inherited members.
        payload.writeUInt64(userData, at: Self.behaviorGraph + 0x30)
        payload.writeUInt8(UInt8(bitPattern: Int8(variableMode)), at: Self.behaviorGraph + 0x48)

        // hkbBehaviorGraphData array sizes.
        payload.writeUInt32(UInt32(variableTypes.count), at: Self.graphData + 0x28)
        payload.writeUInt32(UInt32(eventFlags.count), at: Self.graphData + 0x48)

        // hkbVariableValueSet array sizes.
        payload.writeUInt32(UInt32(wordValues.count), at: Self.variableValueSet + 0x18)
        payload.writeUInt32(1, at: Self.variableValueSet + 0x28)

        // hkbBehaviorGraphStringData array sizes.
        payload.writeUInt32(UInt32(eventNames.count), at: Self.stringData + 0x18)
        payload.writeUInt32(UInt32(variableNames.count), at: Self.stringData + 0x38)

        writeElements(into: &payload)
        writeStrings(into: &payload)
        return payload
    }

    private func writeElements(into payload: inout Data) {
        for (index, type) in variableTypes.enumerated() {
            // hkbVariableInfo is 6 bytes; m_type is the i8 at element + 4.
            payload.writeUInt8(UInt8(bitPattern: type), at: Self.variableInfoData + index * 6 + 4)
        }
        for (index, flags) in eventFlags.enumerated() {
            payload.writeUInt32(flags, at: Self.eventInfoData + index * 4)
        }
        for (index, value) in wordValues.enumerated() {
            payload.writeUInt32(UInt32(bitPattern: value), at: Self.wordValueData + index * 4)
        }
        for lane in 0 ..< 4 {
            payload.writeUInt32(quadValue[lane].bitPattern, at: Self.quadValueData + lane * 4)
        }
    }

    private func writeStrings(into payload: inout Data) {
        payload.writeCString(variantName, at: Self.variantNameString)
        payload.writeCString("hkbBehaviorGraph", at: Self.variantClassNameString)
        payload.writeCString(graphName, at: Self.graphNameString)
        for (index, name) in eventNames.enumerated() where index < Self.eventNameStrings.count {
            payload.writeCString(name, at: Self.eventNameStrings[index])
        }
        for (index, name) in variableNames.enumerated()
            where index < Self.variableNameStrings.count
        {
            payload.writeCString(name, at: Self.variableNameStrings[index])
        }
    }

    // MARK: - Fixups

    private func localFixups() -> [HKXFixture.LocalFixup] {
        var pairs: [(Int, Int)] = [
            (Self.rootContainer + 0x00, Self.namedVariant),
            (Self.namedVariant + 0x00, Self.variantNameString),
            (Self.namedVariant + 0x08, Self.variantClassNameString),
            (Self.namedVariant + 0x10, Self.behaviorGraph),
            (Self.behaviorGraph + 0x38, Self.graphNameString),
            (Self.behaviorGraph + 0x80, Self.rootGenerator),
            (Self.behaviorGraph + 0x88, Self.graphData),
            (Self.graphData + 0x20, Self.variableInfoData),
            (Self.graphData + 0x40, Self.eventInfoData),
            (Self.graphData + 0x70, Self.variableValueSet),
            (Self.variableValueSet + 0x10, Self.wordValueData),
            (Self.variableValueSet + 0x20, Self.quadValueData),
            (Self.stringData + 0x10, Self.eventNamePointers),
            (Self.stringData + 0x30, Self.variableNamePointers)
        ]
        if !omitStringDataPointer {
            pairs.append((Self.graphData + 0x78, Self.stringData))
        }
        for (index, target) in Self.eventNameStrings.enumerated() {
            pairs.append((Self.eventNamePointers + index * 8, target))
        }
        for (index, target) in Self.variableNameStrings.enumerated() {
            pairs.append((Self.variableNamePointers + index * 8, target))
        }
        return pairs.map {
            HKXFixture.LocalFixup(from: UInt32($0.0), toOffset: UInt32($0.1))
        }
    }

    /// Registers every object beyond the auto-registered root container.
    private func virtualFixups(fixture: HKXFixture) -> [HKXFixture.VirtualFixup] {
        [
            (Self.behaviorGraph, 3),
            (Self.graphData, 4),
            (Self.variableValueSet, 5),
            (Self.stringData, 6),
            (Self.rootGenerator, 7)
        ].map { offset, classIndex in
            HKXFixture.VirtualFixup(
                dataOffset: UInt32(offset),
                classNameSection: fixture.contentsClassNameSectionIndex,
                classNameOffset: UInt32(fixture.nameOffset(ofClass: classIndex))
            )
        }
    }
}

extension Data {
    fileprivate mutating func writeUInt8(_ value: UInt8, at offset: Int) {
        self[offset] = value
    }

    fileprivate mutating func writeUInt32(_ value: UInt32, at offset: Int) {
        replaceSubrange(
            offset ..< offset + 4,
            with: Swift.withUnsafeBytes(of: value.littleEndian) { Data($0) }
        )
    }

    fileprivate mutating func writeUInt64(_ value: UInt64, at offset: Int) {
        replaceSubrange(
            offset ..< offset + 8,
            with: Swift.withUnsafeBytes(of: value.littleEndian) { Data($0) }
        )
    }

    fileprivate mutating func writeCString(_ value: String, at offset: Int) {
        let bytes = Data(value.utf8) + Data([0])
        replaceSubrange(offset ..< offset + bytes.count, with: bytes)
    }
}

@Suite("HKX behavior graph")
struct HKBBehaviorGraphTests {
    @Test("Root container names its variant and its payload class")
    func rootContainerNamesVariant() throws {
        let graph = try HKBBehaviorFixture().graph()
        let root = try #require(HKBRootLevelContainer.root(in: graph))
        #expect(root.variants.count == 1)
        #expect(root.variants[0].name == "TestVariant")
        #expect(root.variants[0].className == "hkbBehaviorGraph")
        #expect(root.variant(ofClass: "hkbBehaviorGraph") == HKXPointerTarget(
            sectionIndex: 2, dataOffset: HKBBehaviorFixture.behaviorGraph
        ))
        #expect(root.unresolved.isEmpty)
    }

    @Test("Behavior graph decodes its name, mode, and root generator class")
    func behaviorGraphTopLevelFields() throws {
        let graph = try HKBBehaviorFixture().graph()
        let behavior = try #require(HKBBehaviorGraph.graphs(in: graph).first)
        #expect(behavior.name == "TestBehaviorGraph")
        #expect(behavior.userData == 0xABCD)
        #expect(behavior.variableMode == 1)
        #expect(behavior.rootGeneratorClassName == "hkbStateMachine")
        #expect(behavior.unresolved.isEmpty)
    }

    @Test("String data round-trips variable and event names in order")
    func stringDataRoundTrips() throws {
        let graph = try HKBBehaviorFixture().graph()
        let behavior = try #require(HKBBehaviorGraph.graphs(in: graph).first)
        let strings = try #require(behavior.data?.stringData)
        #expect(strings.variableNames == ["bTestFlag", "iTestState", "fTestSpeed"])
        #expect(strings.eventNames == ["TestEventAlpha", "TestEventBeta"])
        #expect(strings.attributeNames.isEmpty)
    }

    @Test("Graph data decodes variable types and event flags")
    func graphDataDecodesDeclarations() throws {
        let graph = try HKBBehaviorFixture().graph()
        let data = try #require(HKBBehaviorGraph.graphs(in: graph).first?.data)
        #expect(data.variableInfos.map(\.type) == [.bool, .int32, .real])
        #expect(data.eventFlags == [1, 2])
    }

    @Test("Variable value set round-trips word and quad initial values")
    func variableValueSetRoundTrips() throws {
        let graph = try HKBBehaviorFixture().graph()
        let values = try #require(
            HKBBehaviorGraph.graphs(in: graph).first?.data?.variableInitialValues
        )
        #expect(values.wordValues.prefix(2) == [1, 42])
        #expect(values.realValue(at: 2) == 0.5)
        #expect(values.quadValues == [SIMD4<Float>(1, 2, 3, 4)])
        #expect(values.variantCount == 0)
    }

    @Test("A missing string-data pointer costs the names, not the decode")
    func missingStringDataIsRecordedNotFatal() throws {
        var fixture = HKBBehaviorFixture()
        fixture.omitStringDataPointer = true
        let graph = try fixture.graph()
        let behavior = try #require(HKBBehaviorGraph.graphs(in: graph).first)
        #expect(behavior.data?.stringData == nil)
        #expect(behavior.data?.variableInfos.count == 3)
        #expect(behavior.unresolved.contains(HKXUnresolvedReference(
            sectionIndex: 2,
            objectOffset: HKBBehaviorFixture.graphData,
            field: "m_stringData",
            miss: .noFixup
        )))
    }

    @Test("Census reports a behavior file's role and inventories")
    func censusReportsBehaviorFile() throws {
        let census = try HKBBehaviorCensus.census(of: HKBBehaviorFixture().build())
        #expect(census.role == .behavior)
        #expect(census.rootVariantClassNames == ["hkbBehaviorGraph"])
        #expect(census.graphName == "TestBehaviorGraph")
        #expect(census.rootGeneratorClassName == "hkbStateMachine")
        #expect(census.variableNames == ["bTestFlag", "iTestState", "fTestSpeed"])
        #expect(census.variables.map(\.type) == [.bool, .int32, .real])
        #expect(census.eventNames == ["TestEventAlpha", "TestEventBeta"])
        #expect(census.classCounts["hkbBehaviorGraph"] == 1)
        #expect(census.unresolved.isEmpty)
    }

    @Test("A file with no root container censuses as unknown, not a throw")
    func censusOfContainerlessFileIsUnknown() throws {
        var fixture = HKXFixture()
        fixture.rootObjectDataOffset = nil
        fixture.virtualFixups = []
        let census = try HKBBehaviorCensus.census(of: HKXFile(data: fixture.build()))
        #expect(census.role == .unknown)
        #expect(census.objectCount == 0)
    }
}
