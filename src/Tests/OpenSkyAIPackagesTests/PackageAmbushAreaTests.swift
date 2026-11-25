// Whom a running Ambush package waits for: its first location input as a place, a
// target input not matched yet, or everyone (docs/engine/detection.md#ambush-packages).

@testable import OpenSkyAIPackages
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorldConditions
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct PackageAmbushAreaTests {
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x500)

    private static func area(
        of inputs: [Package.DataValue], kind: Package.Kind = .unknown(9)
    ) throws -> PackageAmbushArea? {
        let package = try PackageRuntimeFixture.package(
            id: 0x101, editorID: "Ambush",
            dataInputs: inputs.enumerated().map { index, value in
                Package.DataInput(index: Int8(index), type: "PLDT", value: value)
            },
            kind: kind
        )
        let base = try PackageRuntimeFixture.actorBase(id: 0x600, packages: [0x101])
        let world = FakePackageWorld()
        world.residents = try [PackageRuntimeFixture.residentActor(0x500, base: 0x600)]
        let coordinator = PackageCoordinator(
            world: world,
            data: PackageSessionData(store: PackageStore(
                packages: [package],
                actorTemplates: ActorTemplateResolver(actors: [0x600: base], leveledActors: [:])
            ), conditionFunctions: .standard)
        )
        coordinator.advance()
        return coordinator.ambushArea(of: Self.actor)
    }

    private static func location(_ id: UInt32) -> Package.DataValue {
        .location(Package.Location(rawKind: 0, value: id, radius: 300))
    }

    @Test func theFirstLocationGivesThePlaceAndItsRadius() throws {
        #expect(try Self.area(of: [.boolean(true), Self.location(0x700)])
            == .within(center: FakePackageWorld.place, radius: 0))
        #expect(try Self.area(of: [Self.location(0x999)]) == .unmatched)
    }

    @Test func aTargetIsNotMatchedAndNoInputMeansEveryone() throws {
        let target = Package.DataValue.target(
            Package.Target(rawKind: 0, value: 0x701, countOrDistance: 0)
        )
        #expect(try Self.area(of: [target]) == .unmatched)
        #expect(try Self.area(of: []) == .everyone)
    }

    @Test func anotherPackageTypeHasNoAmbushArea() throws {
        #expect(try Self.area(of: [], kind: .package) == nil)
        #expect(PackageCoordinator(world: nil, data: nil).ambushArea(of: Self.actor) == nil)
    }
}
