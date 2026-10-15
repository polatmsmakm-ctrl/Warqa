import SwiftUI
import PhotosUI
import UIKit

// MARK: - Editor

struct EditorView: View {
    @Binding var project: Project

    @State private var activePageID: UUID? = nil
    @State private var selection: UUID? = nil
    @State private var zoom: Double = 1
    @State private var pinchBase: Double = 1
    @State private var pinching = false
    @State private var showTextEditor = false
    @State private var showRename = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var shareURLs: [URL] = []
    @State private var showShare = false
    @State private var scrollTarget: UUID? = nil

    // undo / redo
    @State private var undoStack: [[Page]] = []
    @State private var redoStack: [[Page]] = []
    @State private var baseline: [Page] = []
    @State private var restoring = false
    @State private var commitTask: Task<Void, Never>? = nil

    // MARK: lookups

    private var activeIndex: Int {
        if let id = activePageID, let i = project.pages.firstIndex(where: { $0.id == id }) {
            return i
        }
        return 0
    }

    private var activePageBinding: Binding<Page> {
        Binding(
            get: { project.pages[activeIndex] },
            set: { project.pages[activeIndex] = $0 }
        )
    }

    private func locate(_ id: UUID) -> (Int, Int)? {
        for (pi, page) in project.pages.enumerated() {
            if let ei = page.elements.firstIndex(where: { $0.id == id }) {
                return (pi, ei)
            }
        }
        return nil
    }

    private func elementBinding(_ id: UUID) -> Binding<Element>? {
        guard let loc = locate(id) else { return nil }
        let current = project.pages[loc.0].elements[loc.1]
        return Binding(
            get: {
                if let l = locate(id) { return project.pages[l.0].elements[l.1] }
                return current
            },
            set: { newValue in
                if let l = locate(id) { project.pages[l.0].elements[l.1] = newValue }
            }
        )
    }

    private var inkColor: RGBA {
        project.pages[activeIndex].background.luminance > 0.5 ? RGBA.ink : RGBA.white
    }

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {
            canvasArea
            bottomPanel
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showRename = true } label: {
                    Text(project.name).font(.headline)
                }
                .buttonStyle(.plain)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(undoStack.isEmpty && baseline == project.pages)
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(redoStack.isEmpty)
                Menu {
                    Button { sharePDF() } label: {
                        Label("مشاركة كل الصفحات PDF", systemImage: "doc.richtext")
                    }
                    Button { sharePNG() } label: {
                        Label("مشاركة الصفحة الحالية صورة", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .alert("اسم المشروع", isPresented: $showRename) {
            TextField("الاسم", text: $project.name)
            Button("تم", role: .cancel) {}
        }
        .sheet(isPresented: $showTextEditor) {
            if let id = selection, let binding = elementBinding(id) {
                TextEditSheet(text: Binding(
                    get: { binding.wrappedValue.text },
                    set: { binding.wrappedValue.text = $0 }
                ))
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareURLs)
        }
        .onAppear {
            baseline = project.pages
            if activePageID == nil { activePageID = project.pages.first?.id }
        }
        .onChange(of: photoItem) { item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { addImage(image) }
                }
                await MainActor.run { photoItem = nil }
            }
        }
        .onChange(of: project.pages) { newPages in
            project.updated = Date()
            if restoring {
                restoring = false
                baseline = newPages
                return
            }
            commitTask?.cancel()
            commitTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                await MainActor.run { commitHistory() }
            }
        }
    }

    // MARK: canvas (pages stacked vertically, like Canva)

    private var canvasArea: some View {
        GeometryReader { geo in
            let fit = max(0.1, (geo.size.width - 32) / PageSize.w)
            let s = fit * CGFloat(zoom)
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal], showsIndicators: false) {
                    VStack(spacing: 22) {
                        ForEach($project.pages) { $page in
                            pageBlock($page, scale: s)
                                .id(page.id)
                        }
                        addPageButton(width: PageSize.w * s)
                    }
                    .padding(.vertical, 16)
                    .frame(minWidth: geo.size.width)
                }
                .background(Color(.systemGray5))
                .onChange(of: scrollTarget) { id in
                    if let id = id {
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    }
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if !pinching {
                                pinching = true
                                pinchBase = zoom
                            }
                            zoom = min(3, max(0.4, pinchBase * Double(value)))
                        }
                        .onEnded { _ in pinching = false }
                )
            }
        }
    }

    private func pageBlock(_ page: Binding<Page>, scale s: CGFloat) -> some View {
        let pageID = page.wrappedValue.id
        let index = project.pages.firstIndex(where: { $0.id == pageID }) ?? 0
        return VStack(spacing: 8) {
            pageHeader(index: index, id: pageID)
                .frame(width: PageSize.w * s)
            EditorCanvas(
                page: page,
                selection: $selection,
                onActivate: { activePageID = pageID },
                onEditText: { showTextEditor = true },
                onDelete: { id in deleteElement(id) },
                onDuplicate: { duplicateSelected() }
            )
            .environment(\.canvasScale, s)
            .environment(\.layoutDirection, .leftToRight)
            .shadow(color: .black.opacity(0.25), radius: 5)
            .scaleEffect(s, anchor: .center)
            .frame(width: PageSize.w * s, height: PageSize.h * s)
        }
    }

    private func pageHeader(index: Int, id: UUID) -> some View {
        let isActive = (id == project.pages[activeIndex].id)
        return HStack(spacing: 16) {
            Text("صفحة \(index + 1)")
                .font(.footnote.weight(.semibold))
                .foregroundColor(isActive ? .accentColor : .secondary)
            Spacer()
            Button { movePage(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { movePage(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index >= project.pages.count - 1)
            Button { duplicatePage(at: index) } label: { Image(systemName: "plus.square.on.square") }
            Button(role: .destructive) { deletePage(at: index) } label: { Image(systemName: "trash") }
                .disabled(project.pages.count <= 1)
        }
        .font(.system(size: 15))
        .buttonStyle(.plain)
        .foregroundColor(.primary.opacity(0.7))
    }

    private func addPageButton(width: CGFloat) -> some View {
        Button { addPage() } label: {
            Label("إضافة صفحة", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
        }
        .buttonStyle(.plain)
        .frame(width: width)
    }

    // MARK: bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if let id = selection, let binding = elementBinding(id) {
                InspectorView(
                    el: binding,
                    onEditText: { showTextEditor = true },
                    onDuplicate: { duplicateSelected() },
                    onFront: { moveSelected(toFront: true) },
                    onBack: { moveSelected(toFront: false) },
                    onDelete: { deleteElement(id) }
                )
            } else {
                PageInspector(page: activePageBinding)
            }
            addBar
            zoomBar
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var zoomBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass").foregroundColor(.secondary)
            Slider(value: $zoom, in: 0.4...3)
            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 44)
            Text("\(activeIndex + 1)/\(project.pages.count)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private func barButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { barLabel(title, icon) }
    }

    private func barLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 20))
            Text(title).font(.caption2)
        }
        .frame(minWidth: 54)
        .foregroundColor(.accentColor)
    }

    private var addBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                barButton("نص", "textformat") { addText(dotted: false) }
                barButton("نص منقّط", "textformat.abc") { addText(dotted: true) }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    barLabel("صورة", "photo")
                }
                barButton("مربع", "square") { addShape(.rect) }
                barButton("دائرة", "circle") { addShape(.circle) }
                barButton("سهم", "arrow.right") { addShape(.arrow) }
                barButton("خط", "minus") { addShape(.line) }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: element actions

    private func nextCenter() -> (Double, Double) {
        let n = project.pages[activeIndex].elements.count % 5
        return (Double(PageSize.w) / 2 + Double(n) * 18,
                Double(PageSize.h) / 2 - 80 + Double(n) * 18)
    }

    private func append(_ element: Element) {
        project.pages[activeIndex].elements.append(element)
        selection = element.id
    }

    private func addText(dotted: Bool) {
        let c = nextCenter()
        append(Element(kind: .text, x: c.0, y: c.1, color: inkColor, dotted: dotted, text: "اكتب هنا", fontSize: 80))
        showTextEditor = true
    }

    private func addShape(_ kind: ElementKind) {
        let c = nextCenter()
        let blue = RGBA.palette[7]
        switch kind {
        case .rect:
            append(Element(kind: .rect, x: c.0, y: c.1, w: 170, h: 170, color: blue))
        case .circle:
            append(Element(kind: .circle, x: c.0, y: c.1, w: 170, h: 170, color: blue))
        case .arrow:
            append(Element(kind: .arrow, x: c.0, y: c.1, w: 240, h: 70, color: blue))
        default:
            append(Element(kind: .line, x: c.0, y: c.1, w: 260, h: 24, color: blue))
        }
    }

    private func addImage(_ image: UIImage) {
        guard let name = ImageStore.save(image) else { return }
        let c = nextCenter()
        var w: Double = 320
        var h: Double = w * Double(image.size.height / max(image.size.width, 1))
        if h > 520 {
            w = w * 520 / h
            h = 520
        }
        append(Element(kind: .image, x: c.0, y: c.1, w: w, h: h, imageFile: name))
    }

    private func deleteElement(_ id: UUID) {
        if let loc = locate(id) {
            project.pages[loc.0].elements.remove(at: loc.1)
        }
        if selection == id { selection = nil }
    }

    private func duplicateSelected() {
        guard let id = selection, let loc = locate(id) else { return }
        var copy = project.pages[loc.0].elements[loc.1]
        copy.id = UUID()
        copy.x += 24
        copy.y += 24
        copy.locked = false
        project.pages[loc.0].elements.append(copy)
        selection = copy.id
    }

    private func moveSelected(toFront: Bool) {
        guard let id = selection, let loc = locate(id) else { return }
        let element = project.pages[loc.0].elements.remove(at: loc.1)
        if toFront {
            project.pages[loc.0].elements.append(element)
        } else {
            project.pages[loc.0].elements.insert(element, at: 0)
        }
    }

    // MARK: page actions

    private func addPage() {
        let i = activeIndex
        let current = project.pages[i]
        let page = Page(style: current.style, background: current.background, lineColor: current.lineColor)
        project.pages.insert(page, at: i + 1)
        activePageID = page.id
        selection = nil
        scrollTarget = page.id
    }

    private func duplicatePage(at index: Int) {
        guard project.pages.indices.contains(index) else { return }
        var copy = project.pages[index]
        copy.id = UUID()
        copy.elements = copy.elements.map { element in
            var e = element
            e.id = UUID()
            return e
        }
        project.pages.insert(copy, at: index + 1)
        activePageID = copy.id
        selection = nil
        scrollTarget = copy.id
    }

    private func deletePage(at index: Int) {
        guard project.pages.count > 1, project.pages.indices.contains(index) else { return }
        project.pages.remove(at: index)
        activePageID = project.pages[max(0, min(index, project.pages.count - 1))].id
        selection = nil
    }

    private func movePage(_ index: Int, by offset: Int) {
        let target = index + offset
        guard project.pages.indices.contains(index), project.pages.indices.contains(target) else { return }
        project.pages.swapAt(index, target)
        scrollTarget = project.pages[target].id
    }

    // MARK: undo / redo

    private func commitHistory() {
        guard baseline != project.pages else { return }
        undoStack.append(baseline)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
        baseline = project.pages
    }

    private func undo() {
        commitTask?.cancel()
        commitHistory()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project.pages)
        restoring = (previous != project.pages)
        project.pages = previous
        selection = nil
    }

    private func redo() {
        commitTask?.cancel()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project.pages)
        restoring = (next != project.pages)
        project.pages = next
        selection = nil
    }

    // MARK: export

    @MainActor
    private func sharePDF() {
        selection = nil
        if let url = Exporter.pdf(project: project) {
            shareURLs = [url]
            showShare = true
        }
    }

    @MainActor
    private func sharePNG() {
        selection = nil
        if let url = Exporter.png(page: project.pages[activeIndex], name: project.name) {
            shareURLs = [url]
            showShare = true
        }
    }
}

// MARK: - Inspector for a selected element

struct InspectorView: View {
    @Binding var el: Element
    var onEditText: () -> Void
    var onDuplicate: () -> Void
    var onFront: () -> Void
    var onBack: () -> Void
    var onDelete: () -> Void

    private var supportsDotted: Bool { el.kind != .image }
    private var supportsFill: Bool { el.kind == .rect || el.kind == .circle }

    var body: some View {
        VStack(spacing: 8) {
            if el.kind != .image {
                ColorRow(colors: RGBA.palette, selected: $el.color)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if el.kind == .text {
                        chip("تعديل النص", "pencil") { onEditText() }
                        Picker("الخط", selection: $el.design) {
                            ForEach(TextDesign.allCases) { design in
                                Text(design.title).tag(design)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if supportsDotted {
                        toggleChip("منقّط", "circle.dotted", $el.dotted)
                    }
                    if supportsFill {
                        toggleChip("تعبئة", "square.fill", $el.filled)
                    }
                    chip("قلب", "arrow.left.and.right") { el.flipped.toggle() }
                    chip("نسخ", "plus.square.on.square") { onDuplicate() }
                    chip("للأمام", "arrow.up.to.line") { onFront() }
                    chip("للخلف", "arrow.down.to.line") { onBack() }
                    chip("حذف", "trash", tint: .red) { onDelete() }
                }
                .padding(.horizontal, 12)
            }
            sliderRow
        }
    }

    @ViewBuilder
    private var sliderRow: some View {
        switch el.kind {
        case .text:
            HStack(spacing: 8) {
                Image(systemName: "textformat.size").foregroundColor(.secondary)
                Slider(value: $el.fontSize, in: 20...300)
            }
            .padding(.horizontal, 16)
        case .image:
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled").foregroundColor(.secondary)
                Slider(value: $el.opacity, in: 0.1...1)
            }
            .padding(.horizontal, 16)
        default:
            if !el.filled {
                HStack(spacing: 8) {
                    Image(systemName: "scribble").foregroundColor(.secondary)
                    Slider(value: $el.lineWidth, in: 1...24)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func chip(_ title: String, _ icon: String, tint: Color = .accentColor,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(tint.opacity(0.12))
                .foregroundColor(tint)
                .clipShape(Capsule())
        }
    }

    private func toggleChip(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Button { binding.wrappedValue.toggle() } label: {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(binding.wrappedValue ? Color.accentColor : Color.accentColor.opacity(0.12))
                .foregroundColor(binding.wrappedValue ? .white : .accentColor)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Inspector for the page itself

struct PageInspector: View {
    @Binding var page: Page

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PageStyle.allCases) { style in
                        Button { page.style = style } label: {
                            Label(style.title, systemImage: style.icon)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(page.style == style ? Color.accentColor : Color.accentColor.opacity(0.12))
                                .foregroundColor(page.style == style ? .white : .accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            HStack(spacing: 6) {
                Text("الخلفية")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                ColorRow(colors: RGBA.pageColors, selected: $page.background)
            }
            if page.style != .plain {
                HStack(spacing: 6) {
                    Text("الخطوط")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                    ColorRow(colors: RGBA.lineColors, selected: $page.lineColor)
                }
            }
        }
    }
}

struct ColorRow: View {
    let colors: [RGBA]
    @Binding var selected: RGBA

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ColorPicker("", selection: Binding(
                    get: { selected.color },
                    set: { selected = RGBA($0) }
                ), supportsOpacity: false)
                .labelsHidden()
                ForEach(colors, id: \.self) { c in
                    Circle()
                        .fill(c.color)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 3)
                                .padding(-3)
                                .opacity(c == selected ? 1 : 0)
                        )
                        .onTapGesture { selected = c }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Text editor sheet

struct TextEditSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.title2)
                .padding()
                .focused($focused)
                .navigationTitle("النص")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("تم") { dismiss() }
                    }
                }
                .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Share + export

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

@MainActor
enum Exporter {
    private static func safeName(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "ورقتي" : cleaned
    }

    static func pdf(project: Project) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName(project.name) + ".pdf")
        try? FileManager.default.removeItem(at: url)
        var box = CGRect(x: 0, y: 0, width: PageSize.w, height: PageSize.h)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for page in project.pages {
            let renderer = ImageRenderer(content: PageStatic(page: page))
            renderer.proposedSize = ProposedViewSize(width: PageSize.w, height: PageSize.h)
            context.beginPDFPage(nil)
            renderer.render { _, draw in
                draw(context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    static func png(page: Page, name: String) -> URL? {
        let renderer = ImageRenderer(content: PageStatic(page: page))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName(name) + ".png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
