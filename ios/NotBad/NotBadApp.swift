import SwiftData
import SwiftUI

@main
struct NotBadApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Paper.self, Mistake.self, ReviewLog.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            MistakeListView()
                .tabItem { Label("错题本", systemImage: "book.closed") }
            ReviewView()
                .tabItem { Label("复习", systemImage: "arrow.triangle.2.circlepath") }
        }
    }
}
