import Foundation
import CoreGraphics

/// Choose one usable panel, without assuming a device, orientation, or hinge angle.
public enum ContiguousLayoutRegion {
    public static func resolve(bounds: CGRect, divisions: [CGRect]) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        var regions = [bounds]
        for division in divisions {
            regions = regions.flatMap { region -> [CGRect] in
                let fold = region.intersection(division)
                guard !fold.isNull, !fold.isEmpty else { return [region] }
                let candidates: [CGRect]
                if division.height > division.width {
                    candidates = [CGRect(x: region.minX, y: region.minY, width: fold.minX - region.minX, height: region.height),
                                  CGRect(x: fold.maxX, y: region.minY, width: region.maxX - fold.maxX, height: region.height)]
                } else {
                    candidates = [CGRect(x: region.minX, y: region.minY, width: region.width, height: fold.minY - region.minY),
                                  CGRect(x: region.minX, y: fold.maxY, width: region.width, height: region.maxY - fold.maxY)]
                }
                return candidates.filter { $0.width > 0 && $0.height > 0 }
            }
        }
        return regions.max { $0.width * $0.height < $1.width * $1.height } ?? .zero
    }
}
