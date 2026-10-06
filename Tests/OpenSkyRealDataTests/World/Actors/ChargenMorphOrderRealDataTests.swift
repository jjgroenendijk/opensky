// Builds the chargen face of several vanilla NPCs from NAM9 and NAMA and compares
// it with the baked FaceGen face. Each slider must fit worse with its sign flipped. Confirms the
// order and sign in docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import simd
import Testing

struct ChargenMorphOrderRealDataTests {
    static let npcs = [
        "Hulda", "Ysolda", "Belethor", "AdrianneAvenicci", "HousecarlWhiterun", "Nazeem",
        "Heimskr", "CarlottaValentia", "Brenuin", "FarengarSecretFire", "Olava",
        "Saadia", "CamillaValerius", "LucanValerius", "Gerdur", "Hod", "Alvor", "Sigrid",
        "Ralof", "Hadvar", "Delphine", "Uthgerd", "AelaTheHuntress",
        "Mjoll", "Balgruuf", "Irileth", "ProventusAvenicci",
        "BrelynaMaryon", "Faendal", "Sven", "Lucia", "Danica", "Amren", "Fralia"
    ]

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func fittedWeightsMatchTheSliders() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let fileSystem = VirtualFileSystem(root: root)
        let records =
            try FaceRecords(file: ESMFile(url: root.dataURL.appending(path: "Skyrim.esm")))
        var lines: [String] = []
        var evidence: [Int: SliderEvidence] = [:]
        var partTargets: Set<String> = []
        for name in Self.npcs {
            guard let actor = records.actors[name] else {
                lines.append("\(name): no NPC_ record")
                continue
            }
            do {
                let fit = try FaceFit(actor: actor, records: records, fileSystem: fileSystem)
                lines.append(fit.report(name: name))
                partTargets.formUnion(fit.partTargets)
                for (index, item) in fit.evidence {
                    evidence[index, default: SliderEvidence()].flipped += item.flipped
                    evidence[index, default: SliderEvidence()].dropped += item.dropped
                    evidence[index, default: SliderEvidence()].samples += 1
                }
            } catch {
                lines.append("\(name): \(error)")
            }
        }
        lines
            .append("part targets ending in 0 or 1: " + partTargets.sorted()
                .joined(separator: ", "))
        for (index, item) in evidence.sorted(by: { $0.key < $1.key }) {
            let pair = ChargenMorphs.sliders[index]
            lines.append(String(
                format: "NAM9[%d] %@/%@ (%d NPCs): flipped +%.4f, dropped +%.4f %@",
                index, pair.negative, pair.positive, item.samples, item.flipped, item.dropped,
                item.agrees ? "ok" : "MISMATCH"
            ))
        }
        let checked = evidence.count
        let agreeing = evidence.values.filter(\.agrees).count
        lines.append("sliders agreeing: \(agreeing) of \(checked)")
        let dir = try RepositoryLogs.createdDirectory("chargen-morph-order")
        try lines.joined(separator: "\n").write(
            to: dir.appending(path: "fit.txt"), atomically: true, encoding: .utf8
        )
        #expect(checked == ChargenMorphs.sliders.count)
        #expect(agreeing == checked, "see \(dir.path)/fit.txt")
    }
}

private struct FaceRecords {
    var actors: [String: ActorBase] = [:]
    var races: [UInt32: Race] = [:]
    var headParts: [UInt32: HeadPart] = [:]

    init(file: ESMFile) throws {
        let wanted = Set(ChargenMorphOrderRealDataTests.npcs)
        ESMWalk.forEachRecord(in: file) { record in
            switch record.type {
            case "NPC_":
                if
                    let actor = try? ActorBase(record: record, localized: true),
                    let id = actor.editorID, wanted.contains(id)
                {
                    actors[id] = actor
                }
            case "RACE":
                if let race = try? Race(record: record, localized: true) {
                    races[race.formID.rawValue] = race
                }
            case "HDPT":
                if let part = try? HeadPart(record: record, localized: true) {
                    headParts[part.formID.rawValue] = part
                }
            default:
                break
            }
            return true
        }
    }
}

/// Summed error changes for one slider index: positive means our mapping fits better.
/// The sign is what the test checks; `dropped` only reports whether the weight helps.
private struct SliderEvidence {
    var flipped = 0.0
    var dropped = 0.0
    var samples = 0

    var agrees: Bool {
        flipped > 0
    }
}

/// Builds the face from NAM9 and NAMA with `ChargenMorphs`, then measures how
/// much worse it fits the baked face when one slider flips sign or is left out.
private struct FaceFit {
    let baseError: Double
    let builtError: Double
    let vampireError: Double?
    let vampireValue: Float?
    let actor: ActorBase
    let partTargets: [String]
    let evidence: [Int: SliderEvidence]

    init(actor: ActorBase, records: FaceRecords, fileSystem: VirtualFileSystem) throws {
        self.actor = actor
        let race = try #require(actor.race.flatMap { records.races[$0.rawValue] })
        let defaults = actor.isFemale ? race.femaleHeadParts : race.maleHeadParts
        let face = try #require((actor.headParts + defaults).compactMap {
            records.headParts[$0.rawValue]
        }.first { $0.partType == .face })
        let triPath = try #require(face.morphPaths.first { $0.kind == .chargen }?.path)
        let tri = try TRIFile(data: fileSystem.contents(forPath: "meshes\\" + triPath))
        let baked = try Self.bakedPositions(
            actor: actor,
            shape: face.editorID ?? "",
            fileSystem: fileSystem
        )
        try #require(
            baked.count == tri.baseVertices.count,
            "baked \(baked.count) vs TRI \(tri.baseVertices.count)"
        )
        partTargets = tri.morphTargets.map(\.name)
            .filter { $0.hasSuffix("Type0") || $0.hasSuffix("Type1") }
        let morphs = actor.details.faceMorphs
        let parts = actor.details.faceParts
        let weights = ChargenMorphs.weights(morphs: morphs, parts: parts)
        func error(_ weights: [String: Float]) -> Double {
            Self
                .rms(zip(baked, ChargenMorphs.positions(tri: tri, weights: weights))
                    .map { SIMD3<Double>($0 - $1) })
        }
        baseError = error([:])
        let built = error(weights)
        builtError = built
        var toggled = weights
        toggled[ChargenMorphs.vampireTarget] = weights[ChargenMorphs.vampireTarget] == nil ? 1 : nil
        vampireError = morphs.count > ChargenMorphs.sliders.count ? error(toggled) : nil
        vampireValue = morphs.count > ChargenMorphs.sliders
            .count ? morphs[ChargenMorphs.sliders.count] : nil
        var evidence: [Int: SliderEvidence] = [:]
        for (index, pair) in ChargenMorphs.sliders.enumerated()
            where index < morphs.count && abs(morphs[index]) >= 0.2
        {
            let value = morphs[index]
            let (used, other) = value < 0 ? (pair.negative, pair.positive) : (
                pair.positive,
                pair.negative
            )
            var dropped = weights
            dropped[used] = nil
            var flipped = dropped
            flipped[other] = min(abs(value), 1)
            evidence[index] = SliderEvidence(
                flipped: error(flipped) - built, dropped: error(dropped) - built, samples: 1
            )
        }
        self.evidence = evidence
    }

    func report(name: String) -> String {
        var line = String(
            format: "%@: base rms %.4f, built rms %.4f, NAMA %@", name, baseError, builtError,
            actor.details.faceParts.map(String.init).joined(separator: " ")
        )
        if let vampireError {
            line += String(
                format: ", NAM9[18] %g, VampireMorph toggled %.4f",
                vampireValue ?? 0,
                vampireError
            )
        }
        return line
    }

    private static func bakedPositions(
        actor: ActorBase, shape: String, fileSystem: VirtualFileSystem
    ) throws -> [SIMD3<Float>] {
        let path = FaceGenPaths.mesh(for: ResolvedFormID(
            plugin: "Skyrim.esm",
            objectID: actor.formID.rawValue
        ))
        let file = try NIFFile(data: fileSystem.contents(forPath: path))
        for block in file.blocks where block.typeName == "BSDynamicTriShape" {
            let dynamic = try NIFDynamicTriShape(data: block.data, header: file.header)
            if dynamic.shape.object.name?.caseInsensitiveCompare(shape) == .orderedSame {
                return dynamic.shape.positions
            }
        }
        throw FaceFitError.noShape(shape)
    }

    private static func rms(_ values: [SIMD3<Double>]) -> Double {
        guard !values.isEmpty else { return 0 }
        return (values.reduce(0) { $0 + simd_length_squared($1) } / Double(values.count))
            .squareRoot()
    }
}

private enum FaceFitError: Error {
    case noShape(String)
}
