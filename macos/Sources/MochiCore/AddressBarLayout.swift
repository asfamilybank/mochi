import Foundation

/// Where the Smart Address Field's pieces sit inside its capsule — framework-agnostic so the
/// centering math can be unit tested without AppKit.
///
/// Modelled on Safari's own address bar (read off its accessibility tree): the site icon and the
/// refresh affordance are *siblings* of the text field inside one container, not subviews of it,
/// and the container — not the field — owns the capsule. That is what lets the capsule's rim and
/// the icons show a plain arrow cursor while only the text itself is an I-beam, and what lets the
/// icon and the text be placed independently: on the Empty Page the magnifying glass travels with
/// the placeholder, centered together; on a page the site icon stays at the leading edge,
/// mirroring the refresh affordance at the trailing one, with the title centered between them.
/// Editing always parks the icon at the leading edge and gives the field the whole middle.
public enum AddressBarLayout {
    public struct Placement: Equatable {
        /// The site icon's leading edge, in the capsule's coordinate space.
        public let iconMinX: Double
        /// The text field's frame along the capsule's horizontal axis.
        public let fieldMinX: Double
        public let fieldWidth: Double

        public init(iconMinX: Double, fieldMinX: Double, fieldWidth: Double) {
            self.iconMinX = iconMinX
            self.fieldMinX = fieldMinX
            self.fieldWidth = fieldWidth
        }
    }

    /// - Parameter capsuleWidth: the capsule's own width (the container minus its focus-ring inset).
    /// - Parameter contentWidth: what the field needs to show its current text (or placeholder)
    ///   without truncating. Only consulted while not editing.
    /// - Parameter isEditing: the field is a live input — the icon parks at the leading edge and
    ///   the field takes every point up to the trailing reservation, so typing never re-centers.
    /// - Parameter pinsIcon: the icon stays at the leading edge even while not editing, and only
    ///   the text is centered on the capsule.
    /// - Parameter trailingReserved: points kept clear at the trailing edge — the refresh
    ///   affordance and its padding while it is shown, just the edge padding while it is not.
    public static func placement(
        capsuleWidth: Double,
        contentWidth: Double,
        isEditing: Bool,
        pinsIcon: Bool,
        leadingPadding: Double,
        iconSize: Double,
        iconTextGap: Double,
        trailingReserved: Double
    ) -> Placement {
        let editingFieldMinX = leadingPadding + iconSize + iconTextGap
        let availableWidth = max(0, capsuleWidth - editingFieldMinX - trailingReserved)
        if isEditing {
            return Placement(iconMinX: leadingPadding, fieldMinX: editingFieldMinX, fieldWidth: availableWidth)
        }
        // Either way a text that fills the whole middle lands exactly where the editing layout
        // would put it, so a long title doesn't jump when the field is clicked.
        let fieldWidth = min(max(0, contentWidth), availableWidth)
        if pinsIcon {
            // The text alone on the capsule's center, held between the icon and the trailing edge.
            let centered = ((capsuleWidth - fieldWidth) / 2).rounded()
            let fieldMinX = min(max(centered, editingFieldMinX), capsuleWidth - trailingReserved - fieldWidth)
            return Placement(iconMinX: leadingPadding, fieldMinX: fieldMinX, fieldWidth: fieldWidth)
        }
        // Icon and text centered as one group, the way Safari centers its magnifying glass and
        // placeholder — pushed back inside the reserved edges when the group is too wide.
        let groupWidth = iconSize + iconTextGap + fieldWidth
        let centered = ((capsuleWidth - groupWidth) / 2).rounded()
        let iconMinX = min(max(centered, leadingPadding), capsuleWidth - trailingReserved - groupWidth)
        return Placement(iconMinX: iconMinX, fieldMinX: iconMinX + iconSize + iconTextGap, fieldWidth: fieldWidth)
    }
}
