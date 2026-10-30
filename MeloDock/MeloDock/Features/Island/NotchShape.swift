import SwiftUI

/// Island outline: a flat top edge flush with the screen top and continuous rounded bottom corners.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = max(0, min(bottomRadius, rect.width / 2, rect.height / 2))
        return UnevenRoundedRectangle(
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            style: .continuous
        )
        .path(in: rect)
    }
}
