import SwiftUI

@main
struct LocalMusicPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
                .preferredColorScheme(.dark)
        }
    }
}
