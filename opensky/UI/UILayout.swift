// Simple deterministic vertical stack layout (M8.1.1). Pure float math; no
// Metal, no text — stacks pre-measured item sizes down a container rect.

/// Cross-axis alignment for a vertical stack.
enum UIStackAlignment {
    case leading, center, trailing
}

/// Lays out a column of items top-to-bottom within a container rect.
struct UIVerticalStack {
    var spacing: Float
    var alignment: UIStackAlignment

    init(spacing: Float = 0, alignment: UIStackAlignment = .leading) {
        self.spacing = spacing
        self.alignment = alignment
    }

    /// Total column height for the given item sizes, including inter-item gaps.
    func totalHeight(sizes: [UISize]) -> Float {
        guard !sizes.isEmpty else { return 0 }
        let content = sizes.reduce(0) { $0 + $1.height }
        return content + spacing * Float(sizes.count - 1)
    }

    /// Frames for each item, stacked from `container`'s top edge, cross-aligned.
    func layout(sizes: [UISize], in container: UIRect) -> [UIRect] {
        var cursorY = container.y
        return sizes.map { size in
            let originX: Float = switch alignment {
            case .leading: container.x
            case .center: container.x + (container.width - size.width) / 2
            case .trailing: container.x + (container.width - size.width)
            }
            let frame = UIRect(x: originX, y: cursorY, width: size.width, height: size.height)
            cursorY += size.height + spacing
            return frame
        }
    }
}
