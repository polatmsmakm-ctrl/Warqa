import SwiftUI
import PhotosUI
import UIKit

// MARK: - Editor

struct EditorView: View {
    @Binding var project: Project

    @State private var pageIndex = 0
    @State private var selection: UUID? = nil
    @State private var showTextEditor = false
    @State private var showRename = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var shareURLs: [URL] = []
    @State private var showShare = false

    private var safeIndex: Int {
        min(max(pageIndex, 0), max(project.pages.count - 1, 0))
    }

    private var pageBinding: Binding<Page> {
        Binding(
            get: { project.pages[safeIndex] },
            set: { project.pages[safeIndex] = $0 }
        )
    }

    private func elementBinding(_ id: UUID) -> Binding<Element>? {
        guard let current = project.pages[safeIndex].elements.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { project.pages[safeIndex].elements.first(where: { $0.id == id }) ?? current },
            set: { newValue in
                if let i = project.pages[safeIndex].elements.firstIndex(where: { $0.id == id }) {
                    project.pages[safeIndex].elements[i] = newValue
                }
            }
        )
    }

    private var inkColor: RGBA {
        project.pages[safeIndex].background.luminance > 0.5 ? RGBA.ink : RGBA.white
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let s = max(0.1, min((geo.size.width - 24) / PageSize.w, (geo.size.height - 24) / PageSize.h))
                ZStack {
                    Color(.systemGray5)
                    EditorCanvas(
                        page: pageBinding,
                        selection: $selection,
                        onEditText: { showTextEditor = true },
                        onDelete: { id in deleteElement(id) }
                    )
                    .environment(\.canvasScale, s)
                    .environment(\.layoutDirection, .leftToRight)
                    .shadow(color: .black.opacity(0.25), radius: 6)
                    .scaleEffect(s, anchor: .center)
                    .frame(width: PageSize.w * s, height: PageSize.h * s)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

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
                    PageInspector(page: pageBinding)
                }
                addBar
                pagesBar
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showRename = true } label: {
                    Text(project.name).font(.headline)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { sharePDF() } label: {
                        Label("مشاركة كل الصفحات PDF", systemImage: "doc.richtext")
                    }
                    Button { sharePNG() } label: {
                        Label("مشاركة هذه الصفحة صورة", systemImage: "photo")
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
        .onChange(of: project.pages) { _ in
            project.updated = Date()
        }
    }

    // MARK: bars

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

    private var pagesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(project.pages.enumerated()), id: \.element.id) { index, p in
                    Button {
                        pageIndex = index
                        selection = nil
                    } label: {
                        PageThumb(page: p, scale: 0.1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(index == safeIndex ? Color.accentColor : Color.gray.opacity(0.4),
                                            lineWidth: index == safeIndex ? 3 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { duplicatePage(at: index) } label: {
                            Label("تكرار الصفحة", systemImage: "plus.square.on.square")
                        }
                        if project.pages.count > 1 {
                            Button(role: .destructive) { deletePage(at: index) } label: {
                                Label("حذف الصفحة", systemImage: "trash")
                            }
                        }
                    }
                }
                Button { addPage() } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        Image(systemName: "plus").foregroundColor(.accentColor)
                    }
                    .frame(width: PageSize.w * 0.1, height: PageSize.h * 0.1)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: element actions

    private func nextCenter() -> (Double, Double) {
        let n = project.pages[safeIndex].elements.count % 5
        return (Double(PageSize.w) / 2 + Double(n) * 18,
                Double(PageSize.h) / 2 - 80 + Double(n) * 18)
    }

    private func append(_ element: Element) {
        project.pages[safeIndex].elements.append(element)
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
        project.pages[safeIndex].elements.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    private func duplicateSelected() {
        guard let id = selection,
              let i = project.pages[safeIndex].elements.firstIndex(where: { $0.id == id }) else { return }
        var copy = project.pages[safeIndex].elements[i]
        copy.id = UUID()
        copy.x += 24
        copy.y += 24
        append(copy)
    }

    private func moveSelected(toFront: Bool) {
        guard let id = selection,
              let i = project.pages[safeIndex].elements.firstIndex(where: { $0.id == id }) else { return }
        let element = project.pages[safeIndex].elements.remove(at: i)
        if toFront {
            project.pages[safeIndex].elements.append(element)
        } else {
            project.pages[safeIndex].elements.insert(element, at: 0)
        }
    }

    // MARK: page actions

    private func addPage() {
        let current = project.pages[safeIndex]
        let page = Page(style: current.style, background: current.background, lineColor: current.lineColor)
        project.pages.insert(page, at: safeIndex + 1)
        pageIndex = safeIndex + 1
        selection = nil
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
        pageIndex = index + 1
        selection = nil
    }

    private func deletePage(at index: Int) {
        guard project.pages.count > 1, project.pages.indices.contains(index) else { return }
        project.pages.remove(at: index)
        pageIndex = max(0, min(index, project.pages.count - 1))
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
        if let url = Exporter.png(page: project.pages[safeIndex], name: project.name) {
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
