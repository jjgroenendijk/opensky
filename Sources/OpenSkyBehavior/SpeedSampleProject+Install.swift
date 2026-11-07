// Reads one project's speed tables from the install's speed file.

import OpenSkyFormatsAnimation
import OpenSkyGameData

nonisolated extension SpeedSampleProject {
    public static let installPath = "meshes\\speeddatasinglefile.txt"

    /// Nil when the file is missing or malformed; the samplers then pass the goal on.
    /// `projectPath` is the project or character file, such as `defaultmale.hkx`.
    public static func load(
        forProject projectPath: String,
        from files: any GameFileSource
    ) -> Self? {
        guard let data = try? files.contents(forPath: installPath) else { return nil }
        return (try? SpeedSampleTable(data: data))?.project(forBehaviorPath: projectPath)
    }
}
