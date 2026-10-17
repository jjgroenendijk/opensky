// MenuRouteTable: one route per menu, and the fallback for the rest.

@testable import OpenSkyMenus
import Testing

@MainActor
struct MenuRouteTableTests {
    @Test func theTopMenuGetsItsOwnRouteAndOthersFallBack() {
        var routed: [String] = []
        let table = MenuRouteTable { _ in routed.append("fallback") }
        table.register("InventoryMenu") { _ in routed.append("inventory") }
        table.register("ContainerMenu", "BarterMenu") { _ in routed.append("container") }
        table.route(.button(.accept), top: "BarterMenu")
        table.route(.button(.accept), top: "InventoryMenu")
        table.route(.button(.accept), top: "Journal")
        table.route(.button(.accept), top: nil)
        #expect(routed == ["container", "inventory", "fallback", "fallback"])
        #expect(table.identifiers == ["InventoryMenu", "ContainerMenu", "BarterMenu"])
    }
}
