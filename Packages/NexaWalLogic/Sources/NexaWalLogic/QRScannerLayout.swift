import Foundation
import CoreGraphics

/// Geometry shared by the live camera, simulator placeholder, and resize tests.
/// `divisions` already includes the platform's recommended interaction margins.
public struct QRScannerLayout {
    public let contentRegion: CGRect
    public let scanArea: CGRect
    public let instruction: CGRect
    public let close: CGRect
    public let cancel: CGRect

    public static func resolve(safeBounds: CGRect, divisions: [CGRect] = [], instructionHeight: CGFloat = 52) -> Self {
        guard safeBounds.width > 0, safeBounds.height > 0 else {
            return Self(contentRegion: .zero, scanArea: .zero, instruction: .zero, close: .zero, cancel: .zero)
        }
        let region = ContiguousLayoutRegion.resolve(bounds: safeBounds, divisions: divisions)
        guard region.width > 0, region.height > 0 else {
            return Self(contentRegion: .zero, scanArea: .zero, instruction: .zero, close: .zero, cancel: .zero)
        }
        let padding = min(16, max(0, min(region.width, region.height) / 10))
        let content = region.insetBy(dx: padding, dy: padding)
        let button = min(44, max(0, min(content.width, content.height)))
        let close = CGRect(x: content.maxX - button, y: content.minY, width: button, height: button)
        let labelHeight = min(max(24, instructionHeight), max(0, content.height - button * 2 - 16))

        if content.width > content.height * 1.25 {
            let edge = max(0, min(250, content.height, content.width * 0.52))
            let scan = CGRect(x: content.minX, y: content.midY - edge / 2, width: edge, height: edge)
            let details = CGRect(x: scan.maxX + 16, y: content.minY,
                                 width: max(0, content.maxX - scan.maxX - 16), height: content.height)
            let cancelWidth = min(160, details.width)
            return Self(contentRegion: region, scanArea: scan,
                        instruction: CGRect(x: details.minX, y: details.midY - labelHeight / 2,
                                            width: details.width, height: labelHeight),
                        close: close,
                        cancel: CGRect(x: details.midX - cancelWidth / 2, y: content.maxY - button,
                                       width: cancelWidth, height: button))
        }

        let cancelWidth = min(160, content.width)
        let cancel = CGRect(x: content.midX - cancelWidth / 2, y: content.maxY - button,
                            width: cancelWidth, height: button)
        let top = close.maxY + 12
        let bottom = max(top, cancel.minY - labelHeight - 24)
        let edge = max(0, min(250, content.width, bottom - top))
        let scan = CGRect(x: content.midX - edge / 2, y: top + (bottom - top - edge) / 2,
                          width: edge, height: edge)
        return Self(contentRegion: region, scanArea: scan,
                    instruction: CGRect(x: content.minX, y: scan.maxY + 12, width: content.width, height: labelHeight),
                    close: close, cancel: cancel)
    }
}
