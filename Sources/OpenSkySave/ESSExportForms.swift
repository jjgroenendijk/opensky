// Turns OpenSky's form ids into the save's ref ids: full and light plugin lists, the
// runtime form id each plugin form gets in them, and the form id array the ref ids index.
// See docs/formats/ess.md#ref-ids.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyWorldState

nonisolated public enum ESSExportError: Error, Equatable, Sendable {
    /// More full plugins than the save's one-byte plugin index can name.
    case tooManyPlugins(Int)
    /// More light plugins than the 12-bit light index can name.
    case tooManyLightPlugins(Int)
    /// The save could not be encoded.
    case format(ESSError)
}

nonisolated struct ESSExportForms {
    let plugins: [String]
    let lightPlugins: [String]
    /// The load order OpenSky's form ids count in.
    let loadOrder: FormIDResolver
    private var fullIndex: [String: Int] = [:]
    private var lightIndex: [String: Int] = [:]
    private(set) var formIDArray: [UInt32] = []
    private var arrayPositions: [UInt32: Int] = [:]

    static let playerReference = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x14)

    init(_ installed: [ESSExportPlugin]) throws(ESSExportError) {
        plugins = installed.filter { !$0.isLight }.map(\.name)
        lightPlugins = installed.filter(\.isLight).map(\.name)
        guard plugins.count <= 0xFE else { throw .tooManyPlugins(plugins.count) }
        guard lightPlugins.count <= 0x1000 else {
            throw .tooManyLightPlugins(lightPlugins.count)
        }
        loadOrder = FormIDResolver.loadOrder(installed.map(\.name))
        for (index, name) in plugins.enumerated() {
            fullIndex[name.lowercased()] = index
        }
        for (index, name) in lightPlugins.enumerated() {
            lightIndex[name.lowercased()] = index
        }
    }

    /// The form id in the save's own load order, or nil for a plugin not loaded or an
    /// object id a light plugin cannot hold.
    func runtimeFormID(_ form: ResolvedFormID) -> UInt32? {
        let name = form.plugin.lowercased()
        if let index = fullIndex[name] {
            return UInt32(index) << 24 | form.objectID & 0x00FF_FFFF
        }
        guard let index = lightIndex[name], form.objectID <= 0xFFF else { return nil }
        return 0xFE00_0000 | UInt32(index) << 12 | form.objectID
    }

    /// `Skyrim.esm` forms use the short kind; every other form goes through the array.
    mutating func ref(_ form: ResolvedFormID) -> ESSRefID? {
        guard let id = runtimeFormID(form) else { return nil }
        if id >> 24 == 0, id <= ESSWriter.maximumVSVal {
            return ESSRefID(kind: .default, value: id)
        }
        if let position = arrayPositions[id] {
            return ESSRefID(kind: .formIDArray, value: UInt32(position + 1))
        }
        guard formIDArray.count < Int(ESSWriter.maximumVSVal) else { return nil }
        formIDArray.append(id)
        arrayPositions[id] = formIDArray.count - 1
        return ESSRefID(kind: .formIDArray, value: UInt32(formIDArray.count))
    }

    /// A form id in OpenSky's load-order space, as record stores hold them.
    mutating func ref(loadOrder id: FormID) -> ESSRefID? {
        loadOrder.resolve(id).flatMap { ref($0) }
    }

    /// A session key: the player's reference, a plugin form, or a created form.
    mutating func ref(_ key: ReferenceKey) -> ESSRefID? {
        if let form = resolved(key) {
            return ref(form)
        }
        guard case let .generated(sequence) = key, sequence <= UInt64(ESSWriter.maximumVSVal)
        else { return nil }
        return ESSRefID(kind: .created, value: UInt32(sequence))
    }

    /// The plugin form a key names; the player key names the player's reference.
    func resolved(_ key: ReferenceKey) -> ResolvedFormID? {
        switch key {
        case .player: Self.playerReference
        case let .plugin(name, objectID): ResolvedFormID(plugin: name, objectID: objectID)
        case .generated: nil
        }
    }
}
