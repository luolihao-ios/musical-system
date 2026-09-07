import Foundation

enum AppLanguage: Equatable, Sendable {
    case simplifiedChinese
    case traditionalChinese
    case english

    init(localeIdentifier: String) {
        let language = localeIdentifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if language.hasPrefix("zh-hans") || language == "zh-cn" || language == "zh-sg" {
            self = .simplifiedChinese
        } else if language.hasPrefix("zh-hant") || language == "zh-tw" || language == "zh-hk" || language == "zh-mo" {
            self = .traditionalChinese
        } else {
            self = .english
        }
    }

    static var current: AppLanguage {
        AppLanguage(localeIdentifier: Locale.preferredLanguages.first ?? "en")
    }
}
