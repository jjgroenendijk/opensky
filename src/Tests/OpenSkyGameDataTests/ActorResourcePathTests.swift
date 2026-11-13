import OpenSkyGameData
import Testing

struct ActorResourcePathTests {
    @Test func theSettingBecomesAnArchiveMeshPath() {
        let fallback = ActorResourcePath.firstPersonSkeleton.fallback
        #expect(ActorResourcePath
            .meshPath(fallback) == "meshes\\actors\\character\\_1stperson\\skeleton.nif")
        #expect(ActorResourcePath.meshPath("Meshes/A/B.nif") == "meshes\\a\\b.nif")
    }
}
