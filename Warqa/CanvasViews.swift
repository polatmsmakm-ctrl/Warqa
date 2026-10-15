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
            .scaleEffect(x: el.flipped ? -1 : 1, y: 1)
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
    var onActivate: () -> Void
    var onEditText: () -> Void
    var onDelete: (UUID) -> Void
    var onDuplicate: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            PageBackground(page: page)
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = nil
                    onActivate()
                }
            ForEach($page.elements) { $el in
                ElementView(
                    el: $el,
                    selected: selection == el.id,
                    onSelect: {
                        selection = el.id
                        onActivate()
                    },
                    onEditText: {
                        selection = el.id
                        onActivate()
                        onEditText()
                    },
                    onDelete: { onDelete(el.id) },
                    onDuplicate: { onDuplicate() }
                )
            }
        }
        .frame(width: PageSize.w, height: PageSize.h)
        .coordinateSpace(name: "page")
    }
}

let selectionPurple = Color(red: 0.49, green: 0.30, blue: 0.97)

struct ElementView: View {
    @Binding var el: Element
    let selected: Bool
    var onSelect: () -> Void
    var onEditText: () -> Void
    var onDelete: () -> Void
    var onDuplicate: () -> Void

    @Environment(\.canvasScale) private var cs
    @State private var dragStart: CGPoint? = nil
    @State private var startEl: Element? = nil

    var body: some View {
        let size = el.size
        ZStack {
            ElementContent(el: el)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if el.kind == .text && !el.locked { onEditText() }
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
                if el.locked { return }
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
                var degrees = atan2(dy, dx) * 180 / Double.pi - 90
                let snapped = (degrees / 15).rounded() * 15
                if abs(degrees - snapped) < 3 { degrees = snapped }
                el.rotation = degrees
            }
    }

    /// ax, ay in {-1, 0, 1}: which side/corner is being dragged. The opposite side stays fixed.
    private func resizeGesture(ax: Double, ay: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
            .onChanged { value in
                if startEl == nil { startEl = el }
                guard let s0 = startEl else { return }
                let size0 = s0.size
                let w0 = Double(size0.width)
                let h0 = Double(size0.height)
                let theta = s0.rotation * Double.pi / 180
                let tx = Double(value.translation.width)
                let ty = Double(value.translation.height)
                let dx = tx * cos(theta) + ty * sin(theta)
                let dy = -tx * sin(theta) + ty * cos(theta)

                var w1 = w0
                var h1 = h0
                let uniform = (ax != 0 && ay != 0) || s0.kind == .text || s0.kind == .image
                if uniform {
                    let fx = ax != 0 ? (w0 + ax * dx) / max(w0, 1) : 1
                    let fy = ay != 0 ? (h0 + ay * dy) / max(h0, 1) : 1
                    var f: Double
                    if ax != 0 && ay != 0 {
                        f = (fx + fy) / 2
                    } else if ax != 0 {
                        f = fx
                    } else {
                        f = fy
                    }
                    f = max(0.1, f)
                    w1 = w0 * f
                    h1 = h0 * f
                } else {
                    if ax != 0 { w1 = max(30, w0 + ax * dx) }
                    if ay != 0 { h1 = max(30, h0 + ay * dy) }
                }

                if s0.kind == .text {
                    let f = w1 / max(w0, 1)
                    el.fontSize = min(500, max(12, s0.fontSize * f))
                    let actual = el.size
                    w1 = Double(actual.width)
                    h1 = Double(actual.height)
                } else {
                    el.w = w1
                    el.h = h1
                }

                let ox = ax * (w1 - w0) / 2
                let oy = ay * (h1 - h0) / 2
                el.x = s0.x + ox * cos(theta) - oy * sin(theta)
                el.y = s0.y + ox * sin(theta) + oy * cos(theta)
            }
            .onEnded { _ in startEl = nil }
    }

    // MARK: selection UI (Canva style)

    private func dotHandle(_ ax: Double, _ ay: Double, _ w: CGFloat, _ h: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1 / cs))
            .shadow(color: .black.opacity(0.25), radius: 1.5 / cs)
            .frame(width: 14 / cs, height: 14 / cs)
            .frame(width: 40 / cs, height: 40 / cs)
            .contentShape(Rectangle())
            .offset(x: CGFloat(ax) * w / 2, y: CGFloat(ay) * h / 2)
            .gesture(resizeGesture(ax: ax, ay: ay))
    }

    private func edgeHandle(_ ax: Double, _ ay: Double, _ w: CGFloat, _ h: CGFloat) -> some View {
        let long = 22 / cs
        let short = 7 / cs
        return Capsule()
            .fill(Color.white)
            .overlay(Capsule().stroke(Color.gray.opacity(0.5), lineWidth: 1 / cs))
            .shadow(color: .black.opacity(0.25), radius: 1.5 / cs)
            .frame(width: ax != 0 ? short : long, height: ax != 0 ? long : short)
            .frame(width: 40 / cs, height: 40 / cs)
            .contentShape(Rectangle())
            .offset(x: CGFloat(ax) * w / 2, y: CGFloat(ay) * h / 2)
            .gesture(resizeGesture(ax: ax, ay: ay))
    }

    private var showsEdgeHandles: Bool {
        el.kind == .rect || el.kind == .circle || el.kind == .arrow || el.kind == .line
    }

    private func selectionOverlay(size: CGSize) -> some View {
        let w = size.width
        let h = size.height
        return ZStack {
            Rectangle()
                .stroke(selectionPurple, lineWidth: 2 / cs)
                .frame(width: w, height: h)
                .allowsHitTesting(false)

            if el.locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Circle().fill(selectionPurple))
                    .scaleEffect(1 / cs)
                    .rotationEffect(.degrees(-el.rotation))
                    .offset(x: w / 2, y: -h / 2)
                    .onTapGesture { el.locked = false }
            } else {
                if showsEdgeHandles {
                    if el.kind != .line {
                        edgeHandle(0, -1, w, h)
                        edgeHandle(0, 1, w, h)
                    }
                    edgeHandle(-1, 0, w, h)
                    edgeHandle(1, 0, w, h)
                }
                if el.kind != .line {
                    dotHandle(-1, -1, w, h)
                    dotHandle(1, -1, w, h)
                    dotHandle(-1, 1, w, h)
                    dotHandle(1, 1, w, h)
                } else {
                    dotHandle(-1, 0, w, h)
                    dotHandle(1, 0, w, h)
                }

                // rotate handle (below the element)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.75))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .scaleEffect(1 / cs)
                    .frame(width: 44 / cs, height: 44 / cs)
                    .contentShape(Rectangle())
                    .offset(x: 0, y: h / 2 + 34 / cs)
                    .gesture(rotateGesture)

                // floating mini toolbar (lock / duplicate / delete)
                HStack(spacing: 18) {
                    Image(systemName: "lock.open")
                        .onTapGesture { el.locked = true }
                    Image(systemName: "plus.square.on.square")
                        .onTapGesture { onDuplicate() }
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .onTapGesture { onDelete() }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                )
                .scaleEffect(1 / cs)
                .rotationEffect(.degrees(-el.rotation))
                .offset(x: 0, y: -(h / 2 + 40 / cs))
            }
        }
    }
}
