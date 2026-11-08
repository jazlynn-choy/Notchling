import CoreGraphics
import Foundation

/// Splits the panel's width between cards by weight, and works out what a drag means.
/// Pure math, so the editing behaviour is unit tested without SwiftUI.
public enum PanelLayout {
    /// The narrowest/widest a card can be made, as a weight.
    public static let weightRange: ClosedRange<Double> = 0.5...4
    public static let minimumWidth: Double = 90

    /// Widths for cards with `weights`, filling `totalWidth` with `spacing` between them. Every
    /// card gets at least `minimum` (if there's room), so a small card can't be squeezed to nothing.
    public static func widths(for weights: [Double], totalWidth: Double, spacing: Double,
                              minimum: Double = minimumWidth) -> [Double] {
        guard !weights.isEmpty else { return [] }
        let (floor, extra) = split(count: weights.count, totalWidth: totalWidth, spacing: spacing, minimum: minimum)
        let totalWeight = weights.reduce(0, +)
        return weights.map { floor + extra * $0 / totalWeight }
    }

    /// The weight card `index` needs so that it ends up `targetWidth` wide, with the other
    /// cards keeping their weights. This is what makes a resize handle track the pointer.
    public static func weight(toMake index: Int, width targetWidth: Double, weights: [Double],
                              totalWidth: Double, spacing: Double, minimum: Double = minimumWidth) -> Double {
        guard weights.indices.contains(index), weights.count > 1 else { return weights.first ?? 1 }
        let (floor, extra) = split(count: weights.count, totalWidth: totalWidth, spacing: spacing, minimum: minimum)
        guard extra > 0 else { return weights[index] }
        let others = weights.enumerated().filter { $0.offset != index }.reduce(0) { $0 + $1.element }
        // width = floor + extra * w / (w + others)  →  w = others * q / (1 - q)
        let share = min(max((targetWidth - floor) / extra, 0.001), 0.95)
        return (others * share / (1 - share)).clamped(to: weightRange)
    }

    /// Where a card dragged sideways by `translation` should land: it moves past a neighbour
    /// once its centre crosses the neighbour's centre.
    public static func targetIndex(moving index: Int, by translation: Double, widths: [Double],
                                   spacing: Double) -> Int {
        guard widths.indices.contains(index) else { return index }
        let centres = widths.indices.map { i in
            widths[..<i].reduce(0, +) + spacing * Double(i) + widths[i] / 2
        }
        let draggedCentre = centres[index] + translation
        var target = index
        while target < widths.count - 1, draggedCentre > centres[target + 1] { target += 1 }
        while target > 0, draggedCentre < centres[target - 1] { target -= 1 }
        return target
    }

    public static let minimumCardHeight: Double = 44
    /// Gap between stacked cards.
    public static let stackSpacing: Double = 8

    /// Every card's rectangle (in panel coordinates, origin top-left), column by column.
    public static func frames(columnWeights: [Double], heightWeights: [[Double]], size: CGSize,
                              spacing: Double) -> [[CGRect]] {
        let widths = widths(for: columnWeights, totalWidth: size.width, spacing: spacing)
        var x = 0.0
        return zip(widths, heightWeights).map { width, weights in
            defer { x += width + spacing }
            let heights = Self.widths(for: weights, totalWidth: size.height, spacing: stackSpacing,
                                      minimum: minimumCardHeight)
            var y = 0.0
            return heights.map { height in
                defer { y += height + stackSpacing }
                return CGRect(x: x, y: y, width: width, height: height)
            }
        }
    }

    /// What dropping `dragging` at `point` would do:
    /// - the outer fifth of a column, or the gap between columns: a new column there;
    /// - the top or bottom quarter of a card: stack above or below it;
    /// - the middle of a card: swap with it, the most common intent, so it gets the biggest zone.
    /// Nil means "put it back where it was".
    public static func dropTarget(at point: CGPoint, frames: [[CGRect]], columns: [[WidgetKind]],
                                  dragging: WidgetKind) -> WidgetLayout.PanelDrop? {
        guard !frames.isEmpty else { return .newColumn(at: 0) }
        for (c, column) in frames.enumerated() {
            guard let first = column.first else { continue }
            let edge = first.width * 0.2
            if point.x < first.minX { return .newColumn(at: c) }               // gap before column c
            guard point.x <= first.maxX else { continue }
            if point.x < first.minX + edge { return .newColumn(at: c) }
            if point.x > first.maxX - edge { return .newColumn(at: c + 1) }
            let row = column.lastIndex { point.y >= $0.minY } ?? 0
            let card = columns[c][row]
            if card == dragging { return nil }
            let frame = column[row]
            let band = frame.height * 0.25
            if point.y < frame.minY + band { return .above(card) }
            if point.y > frame.maxY - band { return .below(card) }
            return .swap(card)
        }
        return .newColumn(at: frames.count)
    }

    /// Dragging the divider between two stacked cards by `delta` points. Returns their new
    /// height weights, keeping their total (so other cards in the column don't move) and
    /// keeping both at least `minimum` tall.
    public static func resizePair(weights: (Double, Double), heights: (Double, Double), delta: Double,
                                  minimum: Double = minimumCardHeight) -> (Double, Double) {
        let total = heights.0 + heights.1
        guard total > 0 else { return weights }
        let upper = min(max(heights.0 + delta, min(minimum, total / 2)), total - min(minimum, total / 2))
        let sum = weights.0 + weights.1
        let first = sum * upper / total
        return (first, sum - first)
    }

    private static func split(count: Int, totalWidth: Double, spacing: Double,
                              minimum: Double) -> (floor: Double, extra: Double) {
        let available = max(0, totalWidth - spacing * Double(count - 1))
        let floor = min(minimum, available / Double(count))
        return (floor, available - floor * Double(count))
    }
}
