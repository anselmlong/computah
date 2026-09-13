import AppKit

struct NotchGeometry: Equatable {
    static let externalDisplayFallback = NotchGeometry(
        notchWidth: 120,
        notchHeight: 24,
        collapsedHeight: 32
    )

    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let collapsedHeight: CGFloat

    init(screen: NSScreen) {
        self.init(
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    init(
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea left: CGRect?,
        auxiliaryTopRightArea right: CGRect?
    ) {
        guard safeAreaTop > 0,
              let left,
              let right,
              right.minX > left.maxX else {
            self = Self.externalDisplayFallback
            return
        }

        notchWidth = right.minX - left.maxX
        notchHeight = safeAreaTop
        collapsedHeight = safeAreaTop
    }

    private init(notchWidth: CGFloat, notchHeight: CGFloat, collapsedHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.collapsedHeight = collapsedHeight
    }
}
