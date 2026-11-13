// Model paths the game reads from string settings rather than from a record.
// See docs/formats/gmst.md.

import Foundation

nonisolated public enum ActorResourcePath: String, GameSettingTextKey {
    /// The NIF rig the first-person arm meshes skin against.
    case firstPersonSkeleton = "sFirstPersonSkeleton"

    public var fallback: String {
        switch self {
        case .firstPersonSkeleton: "Actors\\Character\\_1stPerson\\Skeleton.NIF"
        }
    }

    /// `value` as an archive path: lowercase, under `meshes\`, as a record's model path is.
    public static func meshPath(_ value: String) -> String {
        let path = value.lowercased().replacingOccurrences(of: "/", with: "\\")
        return path.hasPrefix("meshes\\") ? path : "meshes\\" + path
    }
}
