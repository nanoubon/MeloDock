import CoreGraphics

/// Pure description of the physical notch on a screen, in global screen coordinates.
struct NotchGeometry: Equatable {
    let centerX: CGFloat
    let width: CGFloat
    let height: CGFloat

    static func make(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        backingScale: CGFloat,
        auxLeft: CGRect?,
        auxRight: CGRect?,
        fallbackCenterX: CGFloat
    ) -> NotchGeometry? {
        guard safeAreaTop > 0, let auxLeft, let auxRight else { return nil }

        // Some configurations report auxiliary areas in backing-space coordinates.
        // Decide jointly: if either rect looks like backing space, convert both.
        let scale = backingScale > 0 ? backingScale : 1
        let looksLikeBackingSpace = [auxLeft, auxRight].contains {
            $0.maxX > screenFrame.maxX * 1.25 || $0.width > screenFrame.width * 1.25
        }

        func normalize(_ rect: CGRect) -> CGRect {
            var r = rect
            if looksLikeBackingSpace {
                r = CGRect(x: r.minX / scale, y: r.minY / scale,
                           width: r.width / scale, height: r.height / scale)
            }
            // Local (0...width) coordinates are translated to global coordinates.
            let localX = r.minX >= -1 && r.maxX <= screenFrame.width + 1
            let localY = r.minY >= -1 && r.maxY <= screenFrame.height + 1
            if localX && localY {
                r = r.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
            }
            return r
        }

        let left = normalize(auxLeft)
        let right = normalize(auxRight)
        guard !left.isEmpty, !right.isEmpty else { return nil }

        let width = right.minX - left.maxX
        guard width > 0 else { return nil }

        let centerX = (left.maxX + right.minX) / 2
        // Defensive clamp: ignore obviously incorrect notch centers.
        let maxDeviation = max(60, screenFrame.width * 0.18)
        guard abs(centerX - fallbackCenterX) <= maxDeviation else { return nil }

        return NotchGeometry(centerX: centerX, width: width, height: safeAreaTop)
    }
}
