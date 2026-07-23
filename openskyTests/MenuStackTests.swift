// Menu-stack semantics (todo 8.1.2): push/pop ordering, the empty-stack
// gameplay-vs-menu boundary, and the decided edge cases (pop on empty is a
// no-op, a duplicate push is rejected). Pure value type, no AppKit or GPU.
//
// Mutating calls are made before `#expect` because the macro captures its
// argument as an immutable value, which forbids a mutating member inside it.

@testable import opensky
import Testing

struct MenuStackTests {
    @Test
    func emptyStackIsGameplayMode() {
        let stack = MenuStack()
        #expect(stack.isEmpty)
        #expect(!stack.isMenuMode)
        #expect(stack.top == nil)
    }

    @Test
    func pushEntersMenuModeAndSetsTop() {
        var stack = MenuStack()
        let pushed = stack.push("InventoryMenu")
        #expect(pushed)
        #expect(stack.isMenuMode)
        #expect(stack.top == "InventoryMenu")
        #expect(stack.count == 1)
    }

    @Test
    func topFollowsPushOrder() {
        var stack = MenuStack()
        stack.push("InventoryMenu")
        stack.push("Console")
        stack.push("Dialogue Menu")
        #expect(stack.top == "Dialogue Menu")
        #expect(stack.count == 3)
        #expect(stack.contains("InventoryMenu"))
    }

    @Test
    func popReturnsTopAndRestoresPrevious() {
        var stack = MenuStack()
        stack.push("InventoryMenu")
        stack.push("Console")
        let popped = stack.pop()
        #expect(popped == "Console")
        #expect(stack.top == "InventoryMenu")
        #expect(stack.isMenuMode)
    }

    @Test
    func poppingLastMenuReturnsToGameplay() {
        var stack = MenuStack()
        stack.push("InventoryMenu")
        let popped = stack.pop()
        #expect(popped == "InventoryMenu")
        #expect(!stack.isMenuMode)
        #expect(stack.top == nil)
    }

    @Test
    func popOnEmptyIsNoOp() {
        var stack = MenuStack()
        let popped = stack.pop()
        #expect(popped == nil)
        #expect(stack.isEmpty)
    }

    @Test
    func duplicatePushIsRejected() {
        var stack = MenuStack()
        let first = stack.push("InventoryMenu")
        let second = stack.push("InventoryMenu")
        #expect(first)
        #expect(!second)
        #expect(stack.count == 1)
        // The original entry keeps its position; no second copy is stacked.
        #expect(stack.top == "InventoryMenu")
    }

    @Test
    func removeTakesOutAnyPosition() {
        var stack = MenuStack()
        stack.push("A")
        stack.push("B")
        stack.push("C")
        let removed = stack.remove("B")
        #expect(removed)
        #expect(!stack.contains("B"))
        #expect(stack.count == 2)
        #expect(stack.top == "C")
    }

    @Test
    func removeAbsentReturnsFalse() {
        var stack = MenuStack()
        stack.push("A")
        let removed = stack.remove("B")
        #expect(!removed)
        #expect(stack.count == 1)
    }

    @Test
    func removeAllReturnsToGameplay() {
        var stack = MenuStack()
        stack.push("A")
        stack.push("B")
        stack.removeAll()
        #expect(!stack.isMenuMode)
        #expect(stack.isEmpty)
    }

    @Test
    func identifierStringLiteralEquality() {
        let literal: MenuIdentifier = "Console"
        #expect(literal == MenuIdentifier("Console"))
        #expect(literal != MenuIdentifier("InventoryMenu"))
    }
}
