import Foundation
import ImageIO
import SwiftUI

struct ArtworkRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }

    private var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return linear(red) * 0.2126 + linear(green) * 0.7152 + linear(blue) * 0.0722
    }

    func contrast(with other: Self) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }

    func mixed(with other: Self, amount: Double) -> Self {
        .init(
            red: red * (1 - amount) + other.red * amount,
            green: green * (1 - amount) + other.green * amount,
            blue: blue * (1 - amount) + other.blue * amount
        )
    }

    static let white = Self(red: 1, green: 1, blue: 1)
    static let black = Self(red: 0, green: 0, blue: 0)
}

/// 从真实封面小缩略图取色；网络补图与程序生成封面采用同一条路径。
struct NowPlayingArtworkTheme: Equatable, Sendable {
    let top: ArtworkRGB
    let bottom: ArtworkRGB
    let foreground: ArtworkRGB

    static let fallback = from(pixels: [.init(red: 0.3, green: 0.45, blue: 0.8)])

    static func from(pixels: [ArtworkRGB]) -> Self {
        guard !pixels.isEmpty else { return fallback }
        // 程序生成封面的黑胶唱片占较大面积；取其彩色背景而不是黑色圆盘。
        let chromaticPixels = pixels.filter {
            max($0.red, $0.green, $0.blue) - min($0.red, $0.green, $0.blue) > 0.025
        }
        let candidates = chromaticPixels.count * 10 >= pixels.count ? chromaticPixels : pixels
        // 量化颜色而非整体求平均，避免互补色被混成灰色。
        var bins: [Int: (sum: ArtworkRGB, count: Int)] = [:]
        for pixel in candidates {
            let key = Int(pixel.red * 7) * 64 + Int(pixel.green * 7) * 8 + Int(pixel.blue * 7)
            let previous = bins[key] ?? (.black, 0)
            bins[key] = (
                ArtworkRGB(red: previous.sum.red + pixel.red,
                           green: previous.sum.green + pixel.green,
                           blue: previous.sum.blue + pixel.blue),
                previous.count + 1
            )
        }
        // 相同频次按量化值排序，保证同一张封面的结果稳定。
        guard let winner = bins.max(by: {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count < $1.value.count
        })?.value else { return fallback }
        let count = Double(winner.count)
        let dominant = ArtworkRGB(red: winner.sum.red / count, green: winner.sum.green / count, blue: winner.sum.blue / count)
        let maximum = max(dominant.red, dominant.green, dominant.blue)
        let minimum = min(dominant.red, dominant.green, dominant.blue)
        var top: ArtworkRGB
        if maximum - minimum < 0.025 {
            // 黑白封面保留中性倾向，以柔和蓝灰避免纯黑背景。
            top = .init(red: 0.58, green: 0.64, blue: 0.72)
        } else {
            // 保持主色相，将过暗封面抬至可见色域而不是渐变到黑色。
            let scale = 0.76 / max(maximum, 0.001)
            top = ArtworkRGB(red: dominant.red * scale, green: dominant.green * scale, blue: dominant.blue * scale)
                .mixed(with: .white, amount: 0.08)
        }
        var bottom = top.mixed(with: .white, amount: 0.12)
        let whiteContrast = min(ArtworkRGB.white.contrast(with: top), ArtworkRGB.white.contrast(with: bottom))
        let blackContrast = min(ArtworkRGB.black.contrast(with: top), ArtworkRGB.black.contrast(with: bottom))
        let foreground: ArtworkRGB = whiteContrast > blackContrast ? .white : .black
        if max(whiteContrast, blackContrast) < 4.5 {
            // 少数中间亮度落在两种文字颜色的临界区，统一提亮两端。
            while ArtworkRGB.black.contrast(with: top) < 4.5 || ArtworkRGB.black.contrast(with: bottom) < 4.5 {
                top = top.mixed(with: .white, amount: 0.1)
                bottom = bottom.mixed(with: .white, amount: 0.1)
            }
            return Self(top: top, bottom: bottom, foreground: .black)
        }
        return Self(top: top, bottom: bottom, foreground: foreground)
    }

    /// 同步解码只允许由后台任务调用；最多解码 48 像素缩略图。
    static func load(atPath path: String?) -> Self {
        guard let path,
              let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: path) as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 48
              ] as CFDictionary) else { return fallback }

        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return fallback }
        let pixels: [ArtworkRGB] = stride(from: 0, to: bytes.count, by: 4).compactMap { index in
            let alpha = Double(bytes[index + 3]) / 255
            guard alpha > 0.5 else { return nil }
            return ArtworkRGB(
                red: min(1, Double(bytes[index]) / 255 / alpha),
                green: min(1, Double(bytes[index + 1]) / 255 / alpha),
                blue: min(1, Double(bytes[index + 2]) / 255 / alpha)
            )
        }
        return from(pixels: pixels)
    }
}
