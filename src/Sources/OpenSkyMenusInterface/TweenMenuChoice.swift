// The four entries of the Tween menu, numbered as `tweenmenu.swf` numbers them in its
// `HighlightMenu` and `OpenHighlightedMenu` calls. See docs/engine/tween-menu.md.

/// A Tween menu entry, with the movie's number as its raw value.
nonisolated public enum TweenMenuChoice: Int, CaseIterable, Sendable {
    case skills = 1
    case magic = 2
    case items = 3
    case map = 4
}
