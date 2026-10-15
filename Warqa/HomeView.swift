import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    newCard
                    ForEach($store.projects) { $project in
                        NavigationLink {
                            EditorView(project: $project)
                        } label: {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(project.id)
                            } label: {
                                Label("حذف المشروع", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("ورقتي")
        }
    }

    private var newCard: some View {
        Menu {
            Button { store.create(style: .ruled4) } label: {
                Label("صفحة ٤ أسطر", systemImage: PageStyle.ruled4.icon)
            }
            Button { store.create(style: .plain) } label: {
                Label("صفحة سادة", systemImage: PageStyle.plain.icon)
            }
            Button { store.create(style: .ruled) } label: {
                Label("صفحة مسطّرة", systemImage: PageStyle.ruled.icon)
            }
            Button { store.create(style: .grid) } label: {
                Label("صفحة مربعات", systemImage: PageStyle.grid.icon)
            }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    Image(systemName: "plus")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .frame(width: PageSize.w * 0.26, height: PageSize.h * 0.26)
                Text("مشروع جديد")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
                Text(" ").font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(spacing: 8) {
            PageThumb(page: project.pages.first ?? Page(), scale: 0.26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            Text(project.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(project.pages.count) صفحات")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
