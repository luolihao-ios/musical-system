import SwiftUI

@main
struct MuseTransferApp: App {
    @State private var model: TransferModel
    init() { let container = AppContainer(); _model = State(initialValue: TransferModel(container: container)) }
    var body: some Scene {
        WindowGroup {
            TabView { TransferView(model: model).tabItem { Label("互传", systemImage: "arrow.left.arrow.right") }; HistoryView(model: model).tabItem { Label("历史", systemImage: "clock") }; SettingsView(model: model).tabItem { Label("设置", systemImage: "gearshape") } }
                .task { model.start() }
        }
    }
}
