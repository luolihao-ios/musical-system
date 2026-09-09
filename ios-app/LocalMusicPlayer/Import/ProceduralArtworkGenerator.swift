import CryptoKit
import UIKit

@MainActor
protocol ImportedArtworkGenerating {
    func generateArtwork(
        title: String,
        artist: String,
        seed: String
    ) throws -> Data
}

@MainActor
final class ProceduralArtworkGenerator: ImportedArtworkGenerating {
    private static let canvasSize = CGSize(width: 768, height: 768)

    func generateArtwork(
        title: String,
        artist: String,
        seed: String
    ) throws -> Data {
        autoreleasepool {
            renderArtwork(title: title, artist: artist, seed: seed)
        }
    }

    private func renderArtwork(
        title: String,
        artist: String,
        seed: String
    ) -> Data {
        let digest = Array(
            SHA256.hash(data: Data("\(seed)|\(title)|\(artist)".utf8))
        )
        let palette = palette(for: digest)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(
            size: Self.canvasSize,
            format: format
        )
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            drawBackground(in: context, palette: palette)
            drawAmbientGlow(in: context, palette: palette, digest: digest)
            drawRecord(in: context, palette: palette, digest: digest)
            drawTrackIdentity(title: title, artist: artist, palette: palette)
            drawWaveform(in: context, palette: palette, digest: digest)
        }
        return image.jpegData(compressionQuality: 0.88) ?? Data()
    }

    private func palette(for digest: [UInt8]) -> Palette {
        let hue = CGFloat(digest[0]) / 255
        let accentHue = (
            hue + 0.08 + CGFloat(digest[1] % 38) / 100
        ).truncatingRemainder(dividingBy: 1)
        return Palette(
            background: UIColor(
                hue: hue,
                saturation: 0.72,
                brightness: 0.13,
                alpha: 1
            ),
            secondary: UIColor(
                hue: accentHue,
                saturation: 0.82,
                brightness: 0.34,
                alpha: 1
            ),
            accent: UIColor(
                hue: accentHue,
                saturation: 0.68,
                brightness: 0.96,
                alpha: 1
            )
        )
    }

    private func drawBackground(in context: CGContext, palette: Palette) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [palette.background.cgColor, palette.secondary.cgColor] as CFArray,
            locations: [0, 1]
        )
        if let gradient {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 40, y: 20),
                end: CGPoint(x: 728, y: 748),
                options: []
            )
        } else {
            context.setFillColor(palette.background.cgColor)
            context.fill(CGRect(origin: .zero, size: Self.canvasSize))
        }
    }

    private func drawAmbientGlow(
        in context: CGContext,
        palette: Palette,
        digest: [UInt8]
    ) {
        context.saveGState()
        context.setBlendMode(.screen)
        for index in 0..<4 {
            let x = CGFloat(digest[2 + index]) / 255 * 768
            let y = CGFloat(digest[6 + index]) / 255 * 768
            let diameter = 150 + CGFloat(digest[10 + index] % 100)
            context.setFillColor(palette.accent.withAlphaComponent(0.08).cgColor)
            context.fillEllipse(
                in: CGRect(
                    x: x - diameter / 2,
                    y: y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            )
        }
        context.restoreGState()
    }

    private func drawRecord(
        in context: CGContext,
        palette: Palette,
        digest: [UInt8]
    ) {
        let recordRect = CGRect(x: 94, y: 78, width: 580, height: 580)
        context.setShadow(
            offset: CGSize(width: 0, height: 20),
            blur: 32,
            color: UIColor.black.withAlphaComponent(0.7).cgColor
        )
        context.setFillColor(UIColor(white: 0.018, alpha: 1).cgColor)
        context.fillEllipse(in: recordRect)
        context.setShadow(offset: .zero, blur: 0)

        for index in 0..<24 {
            let inset = CGFloat(index) * 8 + 8
            let value = (Int(digest[index % digest.count]) + index) % 14
            let brightness = 0.08 + CGFloat(value) / 255
            context.setStrokeColor(
                UIColor(white: brightness, alpha: 0.85).cgColor
            )
            context.setLineWidth(1)
            context.strokeEllipse(in: recordRect.insetBy(dx: inset, dy: inset))
        }

        let labelRect = recordRect.insetBy(dx: 184, dy: 184)
        context.setFillColor(palette.secondary.cgColor)
        context.fillEllipse(in: labelRect)
        context.setStrokeColor(
            palette.accent.withAlphaComponent(0.75).cgColor
        )
        context.setLineWidth(5)
        context.strokeEllipse(in: labelRect.insetBy(dx: 7, dy: 7))
        context.setFillColor(UIColor(white: 0.02, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: 374, y: 358, width: 20, height: 20))
    }

    private func drawTrackIdentity(
        title: String,
        artist: String,
        palette: Palette
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = normalizedTitle.first.map(String.init) ?? "♫"
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineBreakMode = .byTruncatingTail
        (symbol as NSString).draw(
            in: CGRect(x: 284, y: 274, width: 200, height: 142),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 112, weight: .black),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centered
            ]
        )

        ((normalizedTitle.isEmpty ? "本地音乐" : normalizedTitle) as NSString).draw(
            in: CGRect(x: 70, y: 664, width: 628, height: 48),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centered
            ]
        )
        ((normalizedArtist.isEmpty ? "爱乐之城" : normalizedArtist) as NSString).draw(
            in: CGRect(x: 90, y: 716, width: 588, height: 30),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: palette.accent.withAlphaComponent(0.88),
                .paragraphStyle: centered
            ]
        )
    }

    private func drawWaveform(
        in context: CGContext,
        palette: Palette,
        digest: [UInt8]
    ) {
        context.saveGState()
        context.setStrokeColor(
            palette.accent.withAlphaComponent(0.85).cgColor
        )
        context.setLineWidth(4)
        context.setLineCap(.round)
        for index in 0..<32 {
            let height = 12 + CGFloat(digest[index % digest.count] % 42)
            let x = 198 + CGFloat(index) * 12
            context.move(to: CGPoint(x: x, y: 618 - height / 2))
            context.addLine(to: CGPoint(x: x, y: 618 + height / 2))
        }
        context.strokePath()
        context.restoreGState()
    }
}

private struct Palette {
    let background: UIColor
    let secondary: UIColor
    let accent: UIColor
}
