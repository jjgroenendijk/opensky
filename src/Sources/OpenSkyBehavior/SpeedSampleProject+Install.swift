// Reads one project's speed tables from the install's speed file.

public import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyGameData

nonisolated extension SpeedSampleProject {
    public static let installPath = "meshes\\speeddatasinglefile.txt"

    /// Nil when the file is missing or malformed; the samplers then pass the goal on.
    /// `projectPath` is the project or character file, such as `defaultmale.hkx`.
    public static func load(
        forProject projectPath: String,
        from files: any GameFileSource
    ) -> Self? {
        guard let data = attempt({ try files.contents(forPath: installPath) }) else { return nil }
        return attempt { try SpeedSampleTable(data: data) }?.project(forBehaviorPath: projectPath)
    }
}
