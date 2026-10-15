import SwiftUI
import UIKit
import Combine

// MARK: - Colors

struct RGBA: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    static let ink = RGBA(r: 0.10, g: 0.10, b: 0.12)
    static let white = RGBA(r: 1, g: 1, b: 1)
    static let paper = RGBA(r: 0.99, g: 0.97, b: 0.92)

    /// ألوان العناصر (نصوص، أشكال)
    static let palette: [RGBA] = [
        RGBA(r: 0.10, g: 0.10, b: 0.12),
        RGBA(r: 1.00, g: 1.00, b: 1.00),
        RGBA(r: 0.90, g: 0.22, b: 0.27),
        RGBA(r: 0.98, g: 0.55, b: 0.13),
        RGBA(r: 1.00, g: 0.80, b: 0.10),
        RGBA(r: 0.20, g: 0.72, b: 0.40),
        RGBA(r: 0.10, g: 0.65, b: 0.85),
        RGBA(r: 0.15, g: 0.40, b: 0.95),
        RGBA(r: 0.55, g: 0.30, b: 0.90),
        RGBA(r: 0.95, g: 0.40, b: 0.70),
        RGBA(r: 0.55, g: 0.40, b: 0.28),
        RGBA(r: 0.55, g: 0.57, b: 0.62)
    ]

    /// ألوان خلفية الصفحة
    static let pageColors: [RGBA] = [
        RGBA(r: 0.99, g: 0.97, b: 0.92),
        RGBA(r: 1.00, g: 1.00, b: 1.00),
        RGBA(r: 1.00, g: 0.97, b: 0.78),
        RGBA(r: 0.86, g: 0.93, b: 1.00),
        RGBA(r: 1.00, g: 0.88, b: 0.92),
        RGBA(r: 0.87, g: 0.97, b: 0.88),
        RGBA(r: 0.92, g: 0.92, b: 0.93),
        RGBA(r: 0.11, g: 0.12, b: 0.15)
    ]

    /// ألوان خطوط الصفحة
    static let lineColors: [RGBA] = [
        RGBA(r: 0.35, g: 0.55, b: 0.85),
        RGBA(r: 0.60, g: 0.60, b: 0.62),
        RGBA(r: 0.15, g: 0.15, b: 0.17),
        RGBA(r: 0.90, g: 0.35, b: 0.35),
        RGBA(r: 0.25, g: 0.65, b: 0.40),
        RGBA(r: 1.00, g: 1.00, b: 1.00)
    ]
}

extension RGBA {
    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}

// MARK: - Enums

enum PageStyle: String, Codable, CaseIterable, Identifiable {
    case plain, ruled4, ruled, grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return "سادة"
        case .ruled4: return "٤ أسطر"
        case .ruled: return "مسطّرة"
        case .grid: return "مربعات"
        }
    }

    var icon: String {
        switch self {
        case .plain: return "doc"
        case .ruled4: return "line.3.horizontal"
        case .ruled: return "text.alignleft"
        case .grid: return "square.grid.3x3"
        }
    }
}

enum ElementKind: String, Codable {
    case text, image, rect, circle, arrow, line
}

enum TextDesign: String, Codable, CaseIterable, Identifiable {
    case rounded, standard, serif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: return "مدوّر"
        case .standard: return "عادي"
        case .serif: return "كلاسيكي"
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .rounded: design = .rounded
        case .standard: design = .default
        case .serif: design = .serif
        }
        if let descriptor = base.fontDescriptor.withDesign(design) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}

// MARK: - Model

struct Element: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ElementKind
    var x: Double
    var y: Double
    var w: Double = 160
    var h: Double = 160
    var rotation: Double = 0
    var color: RGBA = .ink
    var filled: Bool = false
    var dotted: Bool = false
    var lineWidth: Double = 6
    var text: String = ""
    var fontSize: Double = 80
    var design: TextDesign = .rounded
    var imageFile: String? = nil
    var opacity: Double = 1

    var size: CGSize {
        if kind == .text {
            return TextGeometry.size(text: text, design: design, fontSize: fontSize)
        }
        return CGSize(width: w, height: h)
    }
}

struct Page: Identifiable, Codable, Equatable {
    var id = UUID()
    var style: PageStyle = .ruled4
    var background: RGBA = .paper
    var lineColor: RGBA = RGBA(r: 0.35, g: 0.55, b: 0.85)
    var elements: [Element] = []
}

struct Project: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var pages: [Page]
    var updated: Date = Date()
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var projects: [Project] = []
    private var bag = Set<AnyCancellable>()
    private let url: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("projects.json")
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Project].self, from: data) {
            projects = list
        }
        $projects
            .dropFirst()
            .debounce(for: .seconds(0.8), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveNow() }
            .store(in: &bag)
    }

    func saveNow() {
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func create(style: PageStyle) {
        let number = projects.count + 1
        let page = Page(style: style)
        projects.insert(Project(name: "مشروع \(number)", pages: [page]), at: 0)
    }

    func delete(_ id: UUID) {
        projects.removeAll { $0.id == id }
    }
}

// MARK: - Images on disk

enum ImageStore {
    private static let cache = NSCache<NSString, UIImage>()

    private static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func hasAlpha(_ image: UIImage) -> Bool {
        guard let info = image.cgImage?.alphaInfo else { return false }
        switch info {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }

    static func save(_ image: UIImage) -> String? {
        let alpha = hasAlpha(image)
        let resized = image.resized(maxSide: 1800)
        let name = UUID().uuidString + (alpha ? ".png" : ".jpg")
        let data = alpha ? resized.pngData() : resized.jpegData(compressionQuality: 0.88)
        guard let data = data else { return nil }
        do {
            try data.write(to: directory.appendingPathComponent(name))
            cache.setObject(resized, forKey: name as NSString)
            return name
        } catch {
            return nil
        }
    }

    static func load(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let path = directory.appendingPathComponent(name).path
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let factor = maxSide / longest
        let newSize = CGSize(width: size.width * factor, height: size.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
