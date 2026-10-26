import Foundation

enum WebStaticAssets {
    static func filename(for path: String) -> String? {
        ["/": "index.html", "/app.js": "app.js", "/i18n.js": "i18n.js", "/style.css": "style.css"][path]
    }
}
