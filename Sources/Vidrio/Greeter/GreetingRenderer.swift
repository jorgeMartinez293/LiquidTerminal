import CoreGraphics
import Foundation

/// Builds the greeting sereno used to print via `fastfetch --logo-type iterm`
/// (an OSC 1337 inline image + a column of system-info lines) as a plain byte
/// buffer, natively, with no fastfetch/ImageMagick/Pillow subprocess involved.
/// Feed the result into a terminal with `feed(byteArray:)` — it's terminal
/// *output*, not shell input, so it needs no `.zshrc` cooperation.
enum GreetingRenderer {
    private static let boxWidthCells = 35
    private static let boxHeightCells = 15
    private static let gapCells = 2
    private static let topBlankLines = 1

    static func render(spriteURL: URL, displayMode: DisplayMode, shellExecutable: String) -> [UInt8] {
        let onBattery = SystemInfo.isOnBattery()
        let wantsAnimation: Bool
        switch displayMode {
        case .gif: wantsAnimation = true
        case .image: wantsAnimation = false
        case .auto: wantsAnimation = !onBattery
        }

        guard let sprite = ImagePipeline.render(fileAt: spriteURL, staticFrameOnly: !wantsAnimation) else {
            return Array(SystemInfo.lines(shellExecutable: shellExecutable)
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n").utf8)
        }

        let color = ColorExtractor.dominantColor(for: spriteURL)
        let infoLines = SystemInfo.lines(shellExecutable: shellExecutable)

        let logoWidth = min(boxWidthCells, max(1, Int((sprite.nativeSize.width * CGFloat(boxWidthCells) / 80).rounded())))
        let logoHeight = min(boxHeightCells, max(1, Int((sprite.nativeSize.height * CGFloat(boxHeightCells) / 80).rounded())))
        let paddingLeft = (boxWidthCells - logoWidth) / 2
        let paddingTop = (boxHeightCells - logoHeight) / 2

        let totalRows = max(boxHeightCells, topBlankLines + infoLines.count + 1)

        var out: [UInt8] = []
        out += esc("7") // DECSC: remember the top-left of the block
        out += Array(String(repeating: "\n", count: totalRows).utf8)
        out += esc("8") // DECRC: back to the remembered start

        // Image, offset within its 35x15 box exactly like the old script's
        // LOGO_PADDING_TOP/LEFT centering.
        out += csi("\(paddingTop)B")
        out += csi("\(paddingLeft + 1)G")
        out += iterm1337(data: sprite.data, widthCells: logoWidth, heightCells: logoHeight)

        for (i, line) in infoLines.enumerated() {
            out += esc("8")
            out += csi("\(topBlankLines + i)B")
            out += csi("\(boxWidthCells + gapCells + 1)G")
            out += color.ansiForeground
            out += Array("\u{25CF} \(line.key)".utf8)
            out += csi("0m")
            out += Array(" \(line.value)".utf8)
        }

        out += esc("8")
        out += csi("\(totalRows)B")
        out += Array("\r\n".utf8)
        return out
    }

    private static func esc(_ s: String) -> [UInt8] { Array("\u{1B}\(s)".utf8) }
    private static func csi(_ s: String) -> [UInt8] { Array("\u{1B}[\(s)".utf8) }

    private static func iterm1337(data: Data, widthCells: Int, heightCells: Int) -> [UInt8] {
        let payload = data.base64EncodedString()
        let header = "\u{1B}]1337;File=inline=1;width=\(widthCells);height=\(heightCells);preserveAspectRatio=0:"
        return Array(header.utf8) + Array(payload.utf8) + [0x07]
    }
}
