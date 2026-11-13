// The name a load door shows under the crosshair. See docs/engine/interaction.md#load-doors.

nonisolated public enum LoadDoorName {
    /// An interior's own name, or else the worldspace's; nil keeps the door's own name.
    public static func resolve(
        cellName: String?, isInterior: Bool, worldspaceName: String?
    ) -> String? {
        let candidates = isInterior ? [cellName, worldspaceName] : [worldspaceName]
        return candidates.lazy.compactMap(\.self).first { !$0.isEmpty }
    }
}
