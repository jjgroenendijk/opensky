// The place natives over a synthetic lever: enable and delete reads, angles,
// distance, heading, location, cell, worldspace, game time, and `GetFormFromFile`.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeWorldPlaceTests {
    private typealias Fixture = PapyrusNativeReferenceFixture
    private static let holdID: UInt32 = 0x0000_0E10
    private static let townID: UInt32 = 0x0000_0E20
    private static let cellID: UInt32 = 0x0000_0E30
    private static let worldspaceID: UInt32 = 0x0000_0E40

    @Test func noWaitFormsChangeTheEnableStateAndDeleteIsRead() throws {
        let fixture = try Fixture.make()
        #expect(fixture.call("DisableNoWait") == .returned(.none))
        #expect(fixture.call("IsEnabled", returnType: .boolean) == .returned(.boolean(false)))
        #expect(fixture.call("EnableNoWait") == .returned(.none))
        #expect(fixture.call("IsEnabled", returnType: .boolean) == .returned(.boolean(true)))

        #expect(fixture.call("IsDeleted", returnType: .boolean) == .returned(.boolean(false)))
        #expect(fixture.call("Delete") == .returned(.none))
        #expect(fixture.call("IsDeleted", returnType: .boolean) == .returned(.boolean(true)))
    }

    @Test func angleYAndScaleReadTheTransform() throws {
        let fixture = try Fixture.make()
        fixture.session.bridge.write(ReferenceTransformOverride(
            position: SIMD3(1, 2, 3), rotation: SIMD3(0, .pi / 2, 0), scale: 1.5
        ).erased, for: fixture.key)

        guard case let .returned(.float(angle)) = fixture.call("GetAngleY", returnType: .float)
        else {
            Issue.record("GetAngleY should answer a float")
            return
        }
        #expect(abs(angle - 90) < 0.001)
        #expect(fixture.call("GetScale", returnType: .float) == .returned(.float(1.5)))
    }

    /// The lever stands at (1, 2, 3) facing north; the other actor stands 3 east and
    /// 4 north of it, so it is 5 units away and clockwise of the lever's heading.
    @Test func distanceAndHeadingUseTheLivePosition() throws {
        let fixture = try Fixture.make()
        let other = Fixture.key(Fixture.doorID)
        fixture.session.bridge.perceptionNatives
            .livePosition = { $0 == other ? SIMD3(4, 6, 3) : nil }
        let argument: [PapyrusValue] = [.object(fixture.handle(Fixture.doorID))]

        #expect(fixture.call("GetDistance", arguments: argument, returnType: .float)
            == .returned(.float(5)))
        let heading = fixture.call("GetHeadingAngle", arguments: argument, returnType: .float)
        guard case let .returned(.float(degrees)) = heading else {
            Issue.record("GetHeadingAngle should answer a float: \(heading)")
            return
        }
        #expect(abs(degrees - atan2(3, 4) * 180 / .pi) < 0.001)
    }

    @Test func distanceAcrossTwoInteriorsIsOutOfAnyRange() throws {
        let fixture = try Fixture.make()
        let other = Fixture.key(Fixture.doorID)
        fixture.session.bridge.perceptionNatives
            .livePosition = { $0 == other ? SIMD3(1, 2, 3) : nil }
        fixture.session.bridge.sessionNatives.conditionData = {
            ConditionDataResolution(cells: [
                fixture.key: ReferenceCell(cell: FormID(Self.cellID), worldspace: nil),
                other: ReferenceCell(cell: FormID(Self.cellID + 1), worldspace: nil)
            ])
        }
        let result = fixture.call(
            "GetDistance", arguments: [.object(fixture.handle(Fixture.doorID))],
            returnType: .float
        )
        #expect(result == .returned(.float(PapyrusNativeFunctions.separateSpaceDistance)))
    }

    @Test func locationCellAndWorldspaceComeFromThePlaceSnapshot() throws {
        let fixture = try Fixture.make()
        fixture.session.bridge.formIDResolver = PapyrusWorldFixture.resolver
        fixture.session.bridge.sessionNatives.conditionData = {
            ConditionDataResolution(
                currentLocations: [fixture.key: ResolvedFormID(
                    plugin: "Skyrim.esm", objectID: Self.townID
                )],
                cells: [fixture.key: ReferenceCell(
                    cell: FormID(Self.cellID), worldspace: FormID(Self.worldspaceID)
                )]
            )
        }
        let expected: [(String, UInt32)] = [
            ("GetCurrentLocation", Self.townID),
            ("GetParentCell", Self.cellID),
            ("GetWorldSpace", Self.worldspaceID)
        ]
        for (name, objectID) in expected {
            #expect(fixture.call(name, returnType: .object("Form"))
                == .returned(.object(fixture.handle(objectID))))
        }
    }

    @Test func placeReadsAreNoneForAnUnplacedReference() throws {
        let fixture = try Fixture.make()
        fixture.session.bridge.sessionNatives.conditionData = { .empty }
        for name in ["GetCurrentLocation", "GetParentCell", "GetWorldSpace"] {
            #expect(fixture.call(name, returnType: .object("Form")) == .returned(.none))
        }
    }

    @Test func isChildFollowsTheParentChain() throws {
        let fixture = try Fixture.make()
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "LCTN",
            contents: LocationFixture.recordBytes(Self.holdID, "Hold")
                + LocationFixture.recordBytes(Self.townID, "Town", parent: Self.holdID)
        ))
        let store = LocationStore(plugins: [("Skyrim.esm", file)])
        fixture.session.bridge.sessionNatives
            .conditionData = { ConditionDataResolution(locations: store) }
        let hold = fixture.handle(Self.holdID)
        let town = fixture.handle(Self.townID)

        #expect(isChild(fixture, of: hold, town) == .returned(.boolean(true)))
        #expect(isChild(fixture, of: town, hold) == .returned(.boolean(false)))
        #expect(isChild(fixture, of: hold, hold) == .returned(.boolean(false)))
    }

    @Test func gameTimeReadsTheDaysPassed() throws {
        let fixture = try Fixture.make()
        let clock = GameClock()
        fixture.session.bridge.sessionNatives.clockSource = { clock }
        let result = fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Utility", "GetCurrentGameTime", receiver: nil, returnType: .float
        ))
        #expect(result == .returned(.float(clock.daysPassed)))
    }

    @Test func formFromFileNamesALoadedPluginOnly() throws {
        let fixture = try Fixture.make()
        fixture.session.bridge.formIDResolver = PapyrusWorldFixture.resolver
        let loaded = getFormFromFile(fixture, Int32(Fixture.leverID), "SKYRIM.ESM")
        #expect(loaded == .returned(.object(fixture.receiver)))
        let missing = getFormFromFile(fixture, Int32(Fixture.leverID), "Dawnguard.esm")
        #expect(missing == .returned(.none))
    }

    private func isChild(
        _ fixture: Fixture, of parent: PapyrusObjectHandle, _ child: PapyrusObjectHandle
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Location", "IsChild", receiver: parent,
            arguments: [.object(child)], returnType: .boolean
        ))
    }

    private func getFormFromFile(
        _ fixture: Fixture, _ formID: Int32, _ file: String
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Game", "GetFormFromFile", receiver: nil,
            arguments: [.integer(formID), .string(file)], returnType: .object("Form")
        ))
    }
}
