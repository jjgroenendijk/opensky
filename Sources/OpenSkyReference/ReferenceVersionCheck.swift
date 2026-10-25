// Whether the reference copy and the install OpenSky reads hold the same data: the
// Steam build id from each `appmanifest_489830.acf`, and a SHA-256 of every master file.

import CryptoKit
import Foundation

nonisolated public struct ReferenceInstallFingerprint: Equatable, Sendable {
    public var buildID: String?
    /// Lower-case master file name to its SHA-256 in hex.
    public var masters: [String: String]

    public init(buildID: String?, masters: [String: String]) {
        self.buildID = buildID
        self.masters = masters
    }

    /// The value of `"buildid"` in a Steam `.acf` manifest.
    public static func buildID(inManifest text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\"", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if fields.count == 2, fields[0].lowercased() == "buildid" {
                return fields[1]
            }
        }
        return nil
    }

    /// Reads the manifest and hashes each `.esm` in `Data/`. Runs off the main actor.
    @concurrent
    public static func read(gameDirectory: URL, manifest: URL) async throws -> Self {
        let text = try? String(contentsOf: manifest, encoding: .utf8)
        let data = gameDirectory.appending(path: "Data", directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(
            atPath: data.path(percentEncoded: false)
        ).filter { $0.lowercased().hasSuffix(".esm") }
        var masters: [String: String] = [:]
        for name in names {
            masters[name.lowercased()] = try sha256(of: data.appending(path: name))
        }
        return Self(buildID: text.flatMap(buildID(inManifest:)), masters: masters)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated public enum ReferenceMismatch: Equatable, Sendable {
    case buildID(opensky: String?, reference: String?)
    case onlyInOpenSky(String)
    case onlyInReference(String)
    case differs(String)

    public var line: String {
        switch self {
        case let .buildID(opensky, reference):
            "Steam build id: OpenSky install \(opensky ?? "unknown"), "
                + "reference copy \(reference ?? "unknown")"
        case let .onlyInOpenSky(name): "\(name): only in the OpenSky install"
        case let .onlyInReference(name): "\(name): only in the reference copy"
        case let .differs(name): "\(name): the files differ"
        }
    }
}

nonisolated public enum ReferenceVersionCheck {
    /// Every difference, build id first, then masters by name. Empty means a match.
    public static func compare(
        opensky: ReferenceInstallFingerprint, reference: ReferenceInstallFingerprint
    ) -> [ReferenceMismatch] {
        var result: [ReferenceMismatch] = []
        if opensky.buildID != reference.buildID || opensky.buildID == nil {
            result.append(.buildID(opensky: opensky.buildID, reference: reference.buildID))
        }
        let names = Set(opensky.masters.keys).union(reference.masters.keys).sorted()
        for name in names {
            switch (opensky.masters[name], reference.masters[name]) {
            case (nil, _): result.append(.onlyInReference(name))
            case (_, nil): result.append(.onlyInOpenSky(name))
            case let (lhs?, rhs?) where lhs != rhs: result.append(.differs(name))
            default: break
            }
        }
        return result
    }
}
