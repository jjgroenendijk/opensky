// The root motion of an idle's clip, read from the project's animation data text
// files. See docs/formats/animation-data.md.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

/// One project's clip list and motion table.
nonisolated struct IdleMotionProject {
    let clips: AnimationDataProject
    let motions: AnimationMotionTable
}

nonisolated extension IdlePlaybackResolver {
    static let animationDataFolder = "meshes\\animationdata\\"

    /// The first project in the folder that knows the generator. The character folder
    /// holds two projects, `defaultfemale` and `defaultmale`.
    func rootMotion(generator: String, project folder: String) -> AnimationRootMotion? {
        for project in motionProjects(in: folder) {
            if let clip = project.clips.clip(named: generator) {
                return project.motions.motions[clip.motionIndex]
            }
        }
        return nil
    }

    private func motionProjects(in folder: String) -> [IdleMotionProject] {
        if let known = motionProjects[folder] {
            return known
        }
        let directory = folder.hasSuffix("\\") ? String(folder.dropLast()) : folder
        let projects = files.fileNames(inDirectory: directory)
            .compactMap { path -> IdleMotionProject? in
                let name = path.split(separator: "\\").last.map { $0.lowercased() } ?? ""
                guard name.hasSuffix(".hkx") else { return nil }
                let stem = String(name.dropLast(".hkx".count))
                let clipPath = Self.animationDataFolder + stem + ".txt"
                let motionPath = Self.animationDataFolder + "boundanims\\anims_" + stem + ".txt"
                guard
                    let clips = text(clipPath).flatMap({ try? AnimationDataProject(text: $0) }),
                    let motions = text(motionPath).flatMap({ try? AnimationMotionTable(text: $0) })
                else { return nil }
                return IdleMotionProject(clips: clips, motions: motions)
            }
        motionProjects[folder] = projects
        return projects
    }

    private func text(_ path: String) -> String? {
        (try? files.contents(forPath: path)).flatMap { String(bytes: $0, encoding: .utf8) }
    }
}
