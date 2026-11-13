import OpenSkyCells
import Testing

struct LoadDoorNameTests {
    @Test func anInteriorShowsItsOwnName() {
        #expect(LoadDoorName.resolve(
            cellName: "Breezehome", isInterior: true, worldspaceName: nil
        ) == "Breezehome")
        #expect(LoadDoorName.resolve(cellName: "", isInterior: true, worldspaceName: nil) == nil)
    }

    @Test func anExteriorShowsItsWorldspace() {
        #expect(LoadDoorName.resolve(
            cellName: "Riverwood", isInterior: false, worldspaceName: "Skyrim"
        ) == "Skyrim")
        #expect(LoadDoorName.resolve(
            cellName: nil, isInterior: false, worldspaceName: "Whiterun"
        ) == "Whiterun")
    }
}
