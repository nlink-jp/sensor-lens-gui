import CoreGraphics

/// How tall the popover's scrolling area should be.
///
/// This exists because a `ScrollView` cannot size itself. It is infinitely
/// flexible, so its ideal height is zero — and a `MenuBarExtra` window sizes to
/// its content's ideal size, which collapsed the list to nothing and left a
/// header sitting on a footer. A `maxHeight` does not help: it caps a height
/// nothing ever asked for.
///
/// So the height is estimated from the rows instead. The estimate does not have
/// to be exact — the view scrolls — it only has to be close enough that a short
/// list is not followed by a pane of empty space, and a long one does not run
/// off the screen.
enum PopoverLayout {
    /// A sparkline row: two lines of labels and a 34pt chart.
    static let sparklineRowHeight: CGFloat = 96
    /// A device card: a name and a row of values.
    static let deviceRowHeight: CGFloat = 62
    /// The divider between the two sections.
    static let sectionDividerHeight: CGFloat = 13
    static let rowSpacing: CGFloat = 8

    /// Never so short that the list looks broken…
    static let minimum: CGFloat = 120
    /// …and never so tall that the popover runs off a laptop screen.
    static let maximum: CGFloat = 420

    static func contentHeight(sparklines: Int, devices: Int) -> CGFloat {
        let rows = sparklines + devices
        guard rows > 0 else { return minimum }

        var height = CGFloat(sparklines) * sparklineRowHeight
            + CGFloat(devices) * deviceRowHeight
            + CGFloat(rows - 1) * rowSpacing
        if sparklines > 0 && devices > 0 {
            height += sectionDividerHeight + rowSpacing
        }
        return min(max(height, minimum), maximum)
    }
}
