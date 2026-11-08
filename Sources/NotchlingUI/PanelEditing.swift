import NotchlingCore
import SwiftUI

/// Edit-mode state for the panel. A plain ObservableObject because the toolchain this
/// builds with can't expand SwiftUI's `@State` macro.
@MainActor
public final class PanelEditor: ObservableObject {
    @Published public var isEditing = false {
        didSet { if !isEditing { endDrag() } }
    }
    /// The card being dragged to a new position, and how far.
    @Published var dragging: WidgetKind?
    @Published var dragOffset: CGFloat = 0
    /// Width of the card being resized when the drag began.
    var resizeStartWidth: CGFloat?

    public init() {}

    func endDrag() {
        dragging = nil
        dragOffset = 0
        resizeStartWidth = nil
    }
}

/// The panel's cards. In edit mode each card gets a drag handle, a resize edge and a remove button.
struct PanelCards: View {
    @ObservedObject var model: NotchModel
    let totalWidth: CGFloat
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var editor: PanelEditor

    static let spacing: CGFloat = 10

    var body: some View {
        let cards = settings.widgets.panel
        let weights = cards.map(settings.cardWeight(for:))
        let widths = PanelLayout.widths(for: weights, totalWidth: totalWidth, spacing: Self.spacing)
        HStack(alignment: .top, spacing: Self.spacing) {
            if cards.isEmpty {
                Text(editor.isEditing ? "Add a card with + above." : "No panel widgets. Add some in Settings.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(Array(cards.enumerated()), id: \.element) { index, kind in
                let width = widths.indices.contains(index) ? widths[index] : 0
                PanelWidgetView(kind: kind, model: model)
                    .frame(width: width)
                    .allowsHitTesting(!editor.isEditing)
                    .overlay {
                        if editor.isEditing {
                            editOverlay(kind: kind, index: index, widths: widths, weights: weights)
                        }
                    }
                    .offset(x: editor.dragging == kind ? editor.dragOffset : 0)
                    .zIndex(editor.dragging == kind ? 1 : 0)
                    .scaleEffect(editor.dragging == kind ? 1.03 : 1)
            }
        }
        .animation(editor.dragging == nil && editor.resizeStartWidth == nil ? .spring(response: 0.3) : nil,
                   value: cards)
    }

    private func editOverlay(kind: WidgetKind, index: Int, widths: [Double], weights: [Double]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.35)))

            // Centre: drag to reorder.
            VStack(spacing: 4) {
                Image(systemName: "arrow.left.and.right").font(.system(size: 14, weight: .semibold))
                Text(kind.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        editor.dragging = kind
                        editor.dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let target = PanelLayout.targetIndex(moving: index, by: value.translation.width,
                                                             widths: widths, spacing: Self.spacing)
                        settings.widgets.move(kind, in: .panel, by: target - index)
                        editor.endDrag()
                    }
            )
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

            // Right edge: drag to resize. Hidden with a single card, which always fills the panel.
            if widths.count > 1 {
                HStack {
                    Spacer()
                    Capsule().fill(Color.white)
                        .frame(width: 4, height: 30)
                        .padding(.horizontal, 4)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    let start = editor.resizeStartWidth ?? widths[index]
                                    editor.resizeStartWidth = start
                                    let weight = PanelLayout.weight(toMake: index, width: start + value.translation.width,
                                                                    weights: weights, totalWidth: totalWidth,
                                                                    spacing: Self.spacing)
                                    settings.setCardWeight(weight, for: kind)
                                }
                                .onEnded { _ in editor.endDrag() }
                        )
                        .accessibilityLabel("Drag to resize \(kind.title)")
                }
            }
        }
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
