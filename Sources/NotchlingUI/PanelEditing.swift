import NotchlingCore
import SwiftUI

/// Edit-mode state for the panel. A plain ObservableObject because the toolchain this
/// builds with can't expand SwiftUI's `@State` macro.
@MainActor
public final class PanelEditor: ObservableObject {
    @Published public var isEditing = false {
        didSet { if !isEditing { endDrag() } }
    }
    /// The card being dragged, how far, and where it would land.
    @Published var dragging: WidgetKind?
    @Published var dragTranslation: CGSize = .zero
    @Published var dropTarget: WidgetLayout.PanelDrop?
    /// Captured when a resize starts, so the whole drag is measured from one stable baseline.
    var resizeStartWidth: CGFloat?
    var pairStart: (weights: (Double, Double), heights: (Double, Double))?

    public init() {}

    func endDrag() {
        dragging = nil
        dragTranslation = .zero
        dropTarget = nil
        resizeStartWidth = nil
        pairStart = nil
    }
}

/// The panel's cards, laid out as columns of stacked cards. In edit mode: drag a card
/// anywhere (onto another card's lower half to stack under it, onto a column's edge for a
/// column of its own), drag a right edge to change a column's width, drag the bar between
/// stacked cards to change their heights, × to remove.
struct PanelCards: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var editor: PanelEditor

    static let spacing: CGFloat = 10
    static let space = "panelCards"

    var body: some View {
        GeometryReader { proxy in
            let columns = settings.widgets.panelColumns
            let columnWeights = settings.columnWeights(columns)
            let frames = PanelLayout.frames(columnWeights: columnWeights,
                                            heightWeights: columns.map { $0.map(settings.cardHeight(for:)) },
                                            size: proxy.size, spacing: Self.spacing)
            ZStack(alignment: .topLeading) {
                if columns.isEmpty {
                    Text(editor.isEditing ? "Add a card with + above." : "No panel widgets. Add some in Settings.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                ForEach(Array(columns.enumerated()), id: \.offset) { c, column in
                    ForEach(Array(column.enumerated()), id: \.element) { r, kind in
                        let frame = frames[c][r]
                        let isDragged = editor.dragging == kind
                        PanelWidgetView(kind: kind, model: model)
                            .frame(width: frame.width, height: frame.height)
                            .allowsHitTesting(!editor.isEditing)
                            .overlay {
                                if editor.isEditing {
                                    EditOverlay(kind: kind, column: c, row: r, columns: columns, frames: frames,
                                                columnWeights: columnWeights, panelSize: proxy.size)
                                }
                            }
                            .scaleEffect(isDragged ? 0.92 : 1)
                            .opacity(isDragged ? 0.85 : 1)
                            .offset(x: frame.minX + (isDragged ? editor.dragTranslation.width : 0),
                                    y: frame.minY + (isDragged ? editor.dragTranslation.height : 0))
                            .zIndex(isDragged ? 1 : 0)
                    }
                }
                if let target = editor.dropTarget {
                    DropIndicator(target: target, columns: columns, frames: frames, height: proxy.size.height)
                }
            }
            .coordinateSpace(name: Self.space)
            .animation(editor.dragging == nil && editor.resizeStartWidth == nil && editor.pairStart == nil
                       ? .spring(response: 0.3) : nil, value: settings.widgets)
        }
    }
}

/// Where the dragged card will go: a vertical bar for a new column, a horizontal bar for a stack.
struct DropIndicator: View {
    let target: WidgetLayout.PanelDrop
    let columns: [[WidgetKind]]
    let frames: [[CGRect]]
    let height: CGFloat

    var body: some View {
        let rect = indicatorRect
        Capsule().fill(Color.accentColor)
            .shadow(color: .accentColor.opacity(0.8), radius: 4)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }

    private var indicatorRect: CGRect {
        switch target {
        case .newColumn(let index):
            let x: CGFloat
            if frames.isEmpty { x = 0 }
            else if index >= frames.count { x = (frames.last?.first?.maxX ?? 0) + PanelCards.spacing / 2 }
            else { x = (frames[index].first?.minX ?? 0) - PanelCards.spacing / 2 }
            return CGRect(x: x - 2, y: 0, width: 4, height: height)
        case .above(let kind), .below(let kind):
            guard let c = columns.firstIndex(where: { $0.contains(kind) }),
                  let r = columns[c].firstIndex(of: kind) else { return .zero }
            let card = frames[c][r]
            let gap = PanelLayout.stackSpacing / 2
            let y = target == .above(kind) ? card.minY - gap : card.maxY + gap
            return CGRect(x: card.minX, y: y - 2, width: card.width, height: 4)
        }
    }
}

struct EditOverlay: View {
    let kind: WidgetKind
    let column: Int
    let row: Int
    let columns: [[WidgetKind]]
    let frames: [[CGRect]]
    let columnWeights: [Double]
    let panelSize: CGSize
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var editor: PanelEditor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.4)))

            // Middle: drag the card anywhere.
            VStack(spacing: 3) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                Text(kind.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(moveGesture)
            .accessibilityLabel("Drag to move \(kind.title)")

            // Top-right: remove.
            VStack {
                HStack {
                    Spacer()
                    Button { settings.widgets.remove(kind, from: .panel) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(kind.title)")
                }
                Spacer()
            }
            .padding(5)

            // Right edge: the column's width (hidden with a single column, which fills the panel).
            if columns.count > 1 {
                HStack {
                    Spacer()
                    handle(width: 4, height: 28, cursor: .resizeLeftRight)
                        .padding(.horizontal, 3)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(widthGesture)
                        .accessibilityLabel("Drag to resize the column")
                }
            }

            // Bottom edge: the split with the card below in the same stack.
            if row < columns[column].count - 1 {
                VStack {
                    Spacer()
                    handle(width: 28, height: 4, cursor: .resizeUpDown)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(heightGesture)
                        .accessibilityLabel("Drag to change the heights")
                }
            }
        }
    }

    private func handle(width: CGFloat, height: CGFloat, cursor: NSCursor) -> some View {
        Capsule().fill(Color.white)
            .frame(width: width, height: height)
            .onHover { inside in
                if inside { cursor.push() } else { NSCursor.pop() }
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(PanelCards.space))
            .onChanged { value in
                editor.dragging = kind
                editor.dragTranslation = value.translation
                editor.dropTarget = PanelLayout.dropTarget(at: value.location, frames: frames,
                                                           columns: columns, dragging: kind)
            }
            .onEnded { value in
                if let target = PanelLayout.dropTarget(at: value.location, frames: frames,
                                                       columns: columns, dragging: kind) {
                    settings.widgets.drop(kind, at: target)
                }
                editor.endDrag()
            }
    }

    private var widthGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(PanelCards.space))
            .onChanged { value in
                let start = editor.resizeStartWidth ?? frames[column][row].width
                editor.resizeStartWidth = start
                let weight = PanelLayout.weight(toMake: column, width: start + value.translation.width,
                                                weights: columnWeights, totalWidth: panelSize.width,
                                                spacing: PanelCards.spacing)
                settings.setCardWeight(weight, for: columns[column][0])
            }
            .onEnded { _ in editor.endDrag() }
    }

    private var heightGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(PanelCards.space))
            .onChanged { value in
                let below = columns[column][row + 1]
                let start = editor.pairStart ?? (
                    weights: (settings.cardHeight(for: kind), settings.cardHeight(for: below)),
                    heights: (frames[column][row].height, frames[column][row + 1].height))
                editor.pairStart = start
                let (top, bottom) = PanelLayout.resizePair(weights: start.weights, heights: start.heights,
                                                           delta: value.translation.height)
                settings.setCardHeights((kind, top), (below, bottom))
            }
            .onEnded { _ in editor.endDrag() }
    }
}

/// Header controls: the pencil, and while editing, an add menu and Done.
struct PanelEditControls: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var editor: PanelEditor

    var body: some View {
        if editor.isEditing {
            HStack(spacing: 6) {
                let addable = settings.widgets.addable(to: .panel)
                Menu {
                    ForEach(addable) { kind in
                        Button { settings.widgets.add(kind, to: .panel) } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(addable.isEmpty)
                .help(addable.isEmpty ? "The panel is full" : "Add a card")
                .accessibilityLabel("Add a card")

                Button("Done") { editor.isEditing = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white))
                    .foregroundStyle(.black)
            }
        } else {
            IconButton(symbol: "pencil", label: "Arrange and resize cards") { editor.isEditing = true }
        }
    }
}
