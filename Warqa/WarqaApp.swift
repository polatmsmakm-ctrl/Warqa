import SwiftUI

@main
struct WarqaApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .onChange(of: scenePhase) { phase in
                    if phase != .active { store.saveNow() }
                }
        }
    }
}
