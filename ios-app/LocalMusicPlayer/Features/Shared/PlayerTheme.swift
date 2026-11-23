import SwiftUI

enum PlayerTheme {
    static let background = Color(red: 0.055, green: 0.05, blue: 0.07)
    static let panel = Color(red: 0.10, green: 0.09, blue: 0.12)
    static let accent = Color(red: 0.00, green: 0.54, blue: 0.51)
    static let muted = Color(red: 0.60, green: 0.57, blue: 0.62)
}

enum PlayerAppearance: String, CaseIterable, Identifiable {
    case gradient, light, dark
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .gradient: "渐变"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

enum PlayerVisualMode: String, CaseIterable, Identifiable {
    case cover, vinyl, classic
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .cover: "封面"
        case .vinyl: "黑胶"
        case .classic: "复古转盘"
        }
    }
}

struct RefreshBackdrop: View {
    @AppStorage("player.appearance") private var appearance = PlayerAppearance.gradient

    var body: some View {
        Group {
            switch appearance {
            case .gradient:
                LinearGradient(colors: [
                    Color(red: 0.82, green: 0.91, blue: 1),
                    Color(red: 0.93, green: 0.90, blue: 0.99),
                    Color(red: 0.99, green: 0.93, blue: 0.94)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .light, .dark:
                Color(uiColor: .systemGroupedBackground)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct PlayerPersonalizationView: View {
    @AppStorage("player.appearance") private var appearance = PlayerAppearance.gradient
    @AppStorage("player.visualMode") private var visualMode = PlayerVisualMode.cover

    var body: some View {
        Form {
            Picker("界面主题", selection: $appearance) {
                ForEach(PlayerAppearance.allCases) { item in Text(item.title).tag(item) }
            }
            Picker("播放外观", selection: $visualMode) {
                ForEach(PlayerVisualMode.allCases) { item in Text(item.title).tag(item) }
            }
        }
        .navigationTitle("主题与个性化")
    }
}
