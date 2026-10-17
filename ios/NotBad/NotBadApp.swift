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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            MistakeListView()
                .tabItem { Label("错题本", systemImage: "book.closed") }
            PaperListView()
                .tabItem { Label("试卷", systemImage: "doc.on.doc") }
            ReviewView()
                .tabItem { Label("复习", systemImage: "arrow.triangle.2.circlepath") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        // 启动和回到前台时，继续生成还没完成的答案
        .task { AnswerGenerator.shared.run(context: modelContext) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { AnswerGenerator.shared.run(context: modelContext) }
        }
    }
}
