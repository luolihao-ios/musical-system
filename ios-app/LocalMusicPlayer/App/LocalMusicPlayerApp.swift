import SwiftUI

@main
@MainActor
struct LocalMusicPlayerApp: App {
    @State private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            BootstrapView(bootstrap: bootstrap)
                .preferredColorScheme(.dark)
                .onOpenURL { url in Task { try? await bootstrap.container?.transferHandoffImporter.importURL(url) } }
        }
    }
}

private struct BootstrapView: View {
    @Bindable var bootstrap: AppBootstrap

    var body: some View {
        Group {
            if let container = bootstrap.container {
                AppShellView(container: container)
            } else if let error = bootstrap.errorMessage {
                ContentUnavailableView(
                    "资料库无法打开",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("正在准备本地资料库…")
            }
        }
        .task {
            bootstrap.start()
        }
    }
}
