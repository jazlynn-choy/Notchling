import Foundation

/// Which widgets appear in each slot, in display order.
///
/// Invariants, enforced by every mutation and by `sanitized()`: each widget fits its slot,
/// appears at most once per slot, and no slot exceeds its capacity.
public struct WidgetLayout: Equatable, Sendable {
    public private(set) var leftWing: [WidgetKind]
    public private(set) var rightWing: [WidgetKind]
    /// Panel cards in reading order: column by column, top to bottom.
    public private(set) var panel: [WidgetKind]
    /// Panel cards that sit *under* the card before them instead of starting a new column.
    /// Storing stacking as a flag keeps `panel` a plain ordered list, so older saved layouts
    /// (which have no flags) load as one card per column.
    public private(set) var stacked: Set<WidgetKind> = []

    public static let maxColumns = 4
    public static let maxStack = 3

    public static let `default` = WidgetLayout(leftWing: [.nowPlayingOrDate],
                                               rightWing: [.reminderCount, .time, .battery],
                                               panel: [.musicCard, .remindersCard])

    public init(leftWing: [WidgetKind], rightWing: [WidgetKind], panel: [WidgetKind],
                stacked: Set<WidgetKind> = []) {
        self.leftWing = Self.clean(leftWing, for: .leftWing)
        self.rightWing = Self.clean(rightWing, for: .rightWing)
        self.panel = Self.clean(panel, for: .panel)
        self.stacked = stacked
        normalizeStacks()
    }

    /// Init from columns, e.g. `[[.musicCard, .weatherCard], [.remindersCard]]`.
    public init(leftWing: [WidgetKind], rightWing: [WidgetKind], columns: [[WidgetKind]]) {
        self.init(leftWing: leftWing, rightWing: rightWing, panel: [])
        panelColumns = columns
    }

    // MARK: Panel columns

    /// The panel as columns of stacked cards. Setting it enforces every limit: no empty
    /// columns, at most `maxStack` per column and `maxColumns` columns, no duplicates.
    public var panelColumns: [[WidgetKind]] {
        get {
            var columns: [[WidgetKind]] = []
            for kind in panel {
                if stacked.contains(kind), !columns.isEmpty {
                    columns[columns.count - 1].append(kind)
                } else {
                    columns.append([kind])
                }
            }
            return columns
        }
        set {
            var seen = Set<WidgetKind>()
            let columns = newValue
                .map { $0.filter { $0.fits(.panel) && seen.insert($0).inserted }.prefix(Self.maxStack).map { $0 } }
                .filter { !$0.isEmpty }
                .prefix(Self.maxColumns)
            panel = columns.flatMap { $0 }
            stacked = Set(columns.flatMap { $0.dropFirst() })
        }
    }

    /// Where a dragged card can be dropped in the panel.
    public enum PanelDrop: Equatable, Sendable {
        /// Its own new column, inserted before column `at` (or at the end).
        case newColumn(at: Int)
        case above(WidgetKind)
        case below(WidgetKind)
        /// Trade places with that card (each keeps its own width and height).
        case swap(WidgetKind)
    }

    /// Moves a panel card to `target`. Returns false (and changes nothing) if that would
    /// break a limit, e.g. a full column or too many columns.
    @discardableResult
    public mutating func drop(_ kind: WidgetKind, at target: PanelDrop) -> Bool {
        if case .swap(let other) = target { return swap(kind, other) }
        var columns = panelColumns
        guard let from = columns.firstIndex(where: { $0.contains(kind) }) else { return false }
        let wasAlone = columns[from].count == 1
        columns[from].removeAll { $0 == kind }
        if wasAlone { columns.remove(at: from) }

        switch target {
        case .newColumn(var index):
            if wasAlone && from < index { index -= 1 }
            guard columns.count < Self.maxColumns else { return false }
            columns.insert([kind], at: min(max(index, 0), columns.count))
        case .swap:
            return false   // handled above
        case .above(let other), .below(let other):
            guard other != kind, let column = columns.firstIndex(where: { $0.contains(other) }),
                  columns[column].count < Self.maxStack,
                  let row = columns[column].firstIndex(of: other) else { return false }
            columns[column].insert(kind, at: target == .above(other) ? row : row + 1)
        }
        panelColumns = columns
        return true
    }

    /// Two cards trade places. Column shapes don't change, so no limit can be broken.
    @discardableResult
    public mutating func swap(_ first: WidgetKind, _ second: WidgetKind) -> Bool {
        guard first != second, panel.contains(first), panel.contains(second) else { return false }
        panelColumns = panelColumns.map { $0.map { $0 == first ? second : $0 == second ? first : $0 } }
        return true
    }

    /// Moves the whole column holding `kind` one place left (-1) or right (+1).
    @discardableResult
    public mutating func moveColumn(containing kind: WidgetKind, by offset: Int) -> Bool {
        var columns = panelColumns
        guard let from = columns.firstIndex(where: { $0.contains(kind) }) else { return false }
        let to = from + offset
        guard columns.indices.contains(to) else { return false }
        columns.swapAt(from, to)
        panelColumns = columns
        return true
    }

    /// Moves a card one place up (-1) or down (+1) within its stack.
    @discardableResult
    public mutating func moveInStack(_ kind: WidgetKind, by offset: Int) -> Bool {
        var columns = panelColumns
        guard let c = columns.firstIndex(where: { $0.contains(kind) }),
              let r = columns[c].firstIndex(of: kind), columns[c].indices.contains(r + offset) else { return false }
        columns[c].swapAt(r, r + offset)
        panelColumns = columns
        return true
    }

    /// Stacks a card under the one before it, or gives a stacked card its own column again.
    @discardableResult
    public mutating func setStacked(_ kind: WidgetKind, _ shouldStack: Bool) -> Bool {
        guard let index = panel.firstIndex(of: kind), stacked.contains(kind) != shouldStack else { return false }
        if shouldStack {
            guard index > 0 else { return false }
            return drop(kind, at: .below(panel[index - 1]))
        }
        let column = panelColumns.firstIndex { $0.contains(kind) } ?? 0
        return drop(kind, at: .newColumn(at: column + 1))
    }

    /// Keeps `stacked` consistent with `panel` after any flat-list change.
    private mutating func normalizeStacks() {
        stacked = stacked.intersection(panel)
        let columns = panelColumns
        panelColumns = columns   // re-applies the column limits
    }

    public subscript(slot: WidgetSlot) -> [WidgetKind] {
        get {
            switch slot {
            case .leftWing: return leftWing
            case .rightWing: return rightWing
            case .panel: return panel
            }
        }
        set {
            let cleaned = Self.clean(newValue, for: slot)
            switch slot {
            case .leftWing: leftWing = cleaned
            case .rightWing: rightWing = cleaned
            case .panel:
                panel = cleaned
                normalizeStacks()
            }
        }
    }

    public var allWidgets: Set<WidgetKind> { Set(leftWing + rightWing + panel) }

    /// Widgets that could still be added to `slot`, or nothing if it's full.
    public func addable(to slot: WidgetSlot) -> [WidgetKind] {
        guard self[slot].count < slot.capacity else { return [] }
        if slot == .panel, panelColumns.count >= Self.maxColumns,
           !panelColumns.contains(where: { $0.count < Self.maxStack }) { return [] }
        return WidgetKind.allCases.filter { $0.fits(slot) && !self[slot].contains($0) }
    }

    /// Adds to the end. In the panel that's a new column, or, once there are
    /// `maxColumns`, the first column with room.
    public mutating func add(_ kind: WidgetKind, to slot: WidgetSlot) {
        guard addable(to: slot).contains(kind) else { return }
        guard slot == .panel else { self[slot].append(kind); return }
        var columns = panelColumns
        if columns.count < Self.maxColumns {
            columns.append([kind])
        } else if let column = columns.firstIndex(where: { $0.count < Self.maxStack }) {
            columns[column].append(kind)
        }
        panelColumns = columns
    }

    public mutating func remove(_ kind: WidgetKind, from slot: WidgetSlot) {
        guard slot == .panel else { self[slot].removeAll { $0 == kind }; return }
        // Through columns, so the card under a removed top card becomes the new top
        // rather than sliding into the column to its left.
        panelColumns = panelColumns.map { $0.filter { $0 != kind } }
    }

    /// Moves a widget one step earlier (negative offset) or later (positive) in its slot.
    /// Moves a widget to the other wing (or between any two slots it fits). Returns whether
    /// it moved: it won't if it doesn't fit there, is already there, or the slot is full.
    @discardableResult
    public mutating func transfer(_ kind: WidgetKind, from source: WidgetSlot, to destination: WidgetSlot) -> Bool {
        guard source != destination, self[source].contains(kind), addable(to: destination).contains(kind) else {
            return false
        }
        remove(kind, from: source)
        add(kind, to: destination)
        return true
    }

    /// For SwiftUI's `onMove` (drag to reorder in Settings).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, in slot: WidgetSlot) {
        if slot == .panel { prepareFlatMove(of: source.compactMap { panel.indices.contains($0) ? panel[$0] : nil }) }
        var items = self[slot]
        let moving = source.sorted().filter(items.indices.contains).map { items[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where items.indices.contains(index) { items.remove(at: index) }
        items.insert(contentsOf: moving, at: min(max(insertAt, 0), items.count))
        self[slot] = items
    }

    public mutating func move(_ kind: WidgetKind, in slot: WidgetSlot, by offset: Int) {
        if slot == .panel { prepareFlatMove(of: [kind]) }
        var items = self[slot]
        guard let from = items.firstIndex(of: kind) else { return }
        let to = min(max(from + offset, 0), items.count - 1)
        guard to != from else { return }
        items.remove(at: from)
        items.insert(kind, at: to)
        self[slot] = items
    }

    /// A card moved in the flat list (Settings) becomes its own column, and a card that was
    /// stacked under it becomes the top of the old column.
    private mutating func prepareFlatMove(of kinds: [WidgetKind]) {
        for kind in kinds {
            if let index = panel.firstIndex(of: kind), !stacked.contains(kind),
               panel.indices.contains(index + 1) {
                stacked.remove(panel[index + 1])
            }
            stacked.remove(kind)
        }
    }

    private static func clean(_ kinds: [WidgetKind], for slot: WidgetSlot) -> [WidgetKind] {
        var seen = Set<WidgetKind>()
        let valid = kinds.filter { $0.fits(slot) && seen.insert($0).inserted }
        return Array(valid.prefix(slot.capacity))
    }
}
