import SwiftUI

enum PageSize {
    static let w: CGFloat = 595
    static let h: CGFloat = 842
}

struct CanvasScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var canvasScale: CGFloat {
        get { self[CanvasScaleKey.self] }
        set { self[CanvasScaleKey.self] = newValue }
    }
}

func solidStroke(_ width: Double) -> StrokeStyle {
    StrokeStyle(lineWidth: CGFloat(width), lineCap: .round, lineJoin: .round)
}

func dottedStroke(_ width: Double) -> StrokeStyle {
    StrokeStyle(lineWidth: CGFloat(width), lineCap: .round, lineJoin: .round,
                dash: [0.01, CGFloat(width) * 2.2])
}

// MARK: - Page background (plain / 4 lines / ruled / grid)

struct PageBackground: View {
    let page: Page

    var body: some View {
        let lineColor = page.lineColor.color
        let style = page.style
        ZStack {
            page.background.color
            Canvas { context, size in
                switch style {
                case .plain:
                    break
                case .ruled4:
                    let gap: CGFloat = 22
                    let groupHeight = gap * 3
                    let spacing: CGFloat = 44
                    let margin: CGFloat = 36
                    var y: CGFloat = 70
                    while y + groupHeight < size.height - 40 {
                        for i in 0..<4 {
                            let ly = y + CGFloat(i) * gap
                            var p = Path()
                            p.move(to: CGPoint(x: margin, y: ly))
                            p.addLine(to: CGPoint(x: size.width - margin, y: ly))
                            let isMiddle = (i == 1)
                            let isBase = (i == 2)
                            let stroke = StrokeStyle(lineWidth: isBase ? 1.8 : 1.0,
                                                     dash: isMiddle ? [6, 5] : [])
                            context.stroke(p, with: .color(lineColor), style: stroke)
                        }
                        y += groupHeight + spacing
                    }
                case .ruled:
                    var y: CGFloat = 80
                    while y < size.height - 30 {
                        var p = Path()
                        p.move(to: CGPoint(x: 30, y: y))
                        p.addLine(to: CGPoint(x: size.width - 30, y: y))
                        context.stroke(p, with: .color(lineColor), lineWidth: 1)
                        y += 30
                    }
                case .grid:
                    let step: CGFloat = 24
                    var x: CGFloat = 0
                    while x <= size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(lineColor.opacity(0.7)), lineWidth: 0.7)
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(lineColor.opacity(0.7)), lineWidth: 0.7)
                        y += step
                    }
                }
            }
        }
    }
}

// MARK: - Element drawing (shared by editor, thumbnails, export)

struct ElementContent: View {
    let el: Element

    var body: some View {
        let size = el.size
        content
            .frame(width: size.width, height: size.height)
            .opacity(el.opacity)
    }

    @ViewBuilder
    private var content: some View {
        switch el.kind {
        case .text:
            if el.dotted {
                TextShape(text: el.text, design: el.design)
                    .stroke(el.color.color, style: dottedStroke(max(2.5, el.fontSize * 0.035)))
            } else {
                TextShape(text: el.text, design: el.design)
                    .fill(el.color.color)
            }
        case .image:
            if let name = el.imageFile, let ui = ImageStore.load(name) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: CGFloat(el.w), height: CGFloat(el.h))
                    .clipped()
            } else {
                Rectangle().fill(Color.gray.opacity(0.25))
            }
        case .rect:
            if el.filled {
                RoundedRectangle(cornerRadius: 8).fill(el.color.color)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(el.color.color, style: el.dotted ? dottedStroke(el.lineWidth) : solidStroke(el.lineWidth))
            }
        case .circle:
            if el.filled {
                Ellipse().fill(el.color.color)
            } else {
                Ellipse()
                    .stroke(el.color.color, style: el.dotted ? dottedStroke(el.lineWidth) : solidStroke(el.lineWidth))
            }
        case .arrow:
            ArrowShape()
                .stroke(el.color.color, style: el.dotted ? dottedStroke(el.lineWidth) : solidStroke(el.lineWidth))
        case .line:
            LineShape()
                .stroke(el.color.color, style: el.dotted ? dottedStroke(el.lineWidth) : solidStroke(el.lineWidth))
        }
    }
}

/// صفحة للعرض فقط (مصغّرات + تصدير)
struct PageStatic: View, Equatable {
    let page: Page

    var body: some View {
        ZStack(alignment: .topLeading) {
            PageBackground(page: page)
            ForEach(page.elements) { el in
                ElementContent(el: el)
                    .rotationEffect(.degrees(el.rotation))
                    .position(x: CGFloat(el.x), y: CGFloat(el.y))
            }
        }
        .frame(width: PageSize.w, height: PageSize.h)
        .clipped()
    }
}

struct PageThumb: View {
    let page: Page
    let scale: CGFloat

    var body: some View {
        PageStatic(page: page)
            .equatable()
            .scaleEffect(scale, anchor: .center)
            .frame(width: PageSize.w * scale, height: PageSize.h * scale)
            .allowsHitTesting(false)
    }
}

// MARK: - Interactive editor canvas

struct EditorCanvas: View {
    @Binding var page: Page
    @Binding var selection: UUID?
    var onEditText: () -> Void
    var onDelete: (UUID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            PageBackground(page: page)
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }
            ForEach($page.elements) { $el in
                ElementView(
                    el: $el,
                    selected: selection == el.id,
                    onSelect: { selection = el.id },
                    onEditText: {
                        selection = el.id
                        onEditText()
                    },
                    onDelete: { onDelete(el.id) }
                )
            }
        }
        .frame(width: PageSize.w, height: PageSize.h)
        .coordinateSpace(name: "page")
    }
}

struct ElementView: View {
    @Binding var el: Element
    let selected: Bool
    var onSelect: () -> Void
    var onEditText: () -> Void
    var onDelete: () -> Void

    @Environment(\.canvasScale) private var canvasScale
    @State private var dragStart: CGPoint? = nil
    @State private var startSize: CGSize? = nil
    @State private var startFont: Double = 0

    var body: some View {
        let size = el.size
        ZStack {
            ElementContent(el: el)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if el.kind == .text { onEditText() }
                }
                .onTapGesture { onSelect() }
                .gesture(moveGesture)
            if selected {
                selectionOverlay(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(el.rotation))
        .position(x: CGFloat(el.x), y: CGFloat(el.y))
    }

    // MARK: gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("page"))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = CGPoint(x: el.x, y: el.y)
                    onSelect()
                }
                if let start = dragStart {
                    el.x = Double(start.x + value.translation.width)
                    el.y = Double(start.y + value.translation.height)
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
            .onChanged { value in
                let dx = Double(value.location.x) - el.x
                let dy = Double(value.location.y) - el.y
                var degrees = atan2(dy, dx) * 180 / Double.pi + 90
                let snapped = (degrees / 15).rounded() * 15
                if abs(degrees - snapped) < 3 { degrees = snapped }
                el.rotation = degrees
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
            .onChanged { value in
                if startSize == nil {
                    startSize = el.size
                    startFont = el.fontSize
                }
                guard let s0 = startSize else { return }
                let theta = el.rotation * Double.pi / 180
                let tx = Double(value.translation.width)
                let ty = Double(value.translation.height)
                let dx = tx * cos(theta) + ty * sin(theta)
                let dy = -tx * sin(theta) + ty * cos(theta)
                let w0 = Double(s0.width)
                let h0 = Double(s0.height)
                switch el.kind {
                case .text:
                    let factor = max(0.15, (w0 + 2 * dx) / max(w0, 1))
                    el.fontSize = min(400, max(14, startFont * factor))
                case .line:
                    el.w = max(40, w0 + 2 * dx)
                case .image:
                    let newW = max(50, w0 + 2 * dx)
                    el.w = newW
                    el.h = newW * h0 / max(w0, 1)
                default:
                    el.w = max(40, w0 + 2 * dx)
                    el.h = max(40, h0 + 2 * dy)
                }
            }
            .onEnded { _ in startSize = nil }
    }

    // MARK: selection UI

    private func handle(_ icon: String, tint: Color) -> some View {
        let d = 34 / canvasScale
        return Image(systemName: icon)
            .font(.system(size: d * 0.5, weight: .bold))
            .foregroundColor(.white)
            .frame(width: d, height: d)
            .background(Circle().fill(tint))
            .contentShape(Circle())
    }

    private func selectionOverlay(size: CGSize) -> some View {
        let d = 34 / canvasScale
        let m = 6 / canvasScale
        return ZStack {
            Rectangle()
                .strokeBorder(Color.accentColor,
                              style: StrokeStyle(lineWidth: 1.5 / canvasScale, dash: [5 / canvasScale, 4 / canvasScale]))
                .frame(width: size.width + m * 2, height: size.height + m * 2)
                .allowsHitTesting(false)
            handle("xmark", tint: .red)
                .offset(x: -(size.width / 2 + m), y: -(size.height / 2 + m))
                .onTapGesture { onDelete() }
            handle("arrow.triangle.2.circlepath", tint: .accentColor)
                .offset(x: 0, y: -(size.height / 2 + d))
                .gesture(rotateGesture)
            handle("arrow.up.left.and.arrow.down.right", tint: .accentColor)
                .offset(x: size.width / 2 + m, y: size.height / 2 + m)
                .gesture(resizeGesture)
        }
    }
}
