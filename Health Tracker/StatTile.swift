import SwiftUI

/// The small "value over label" tile used by the workout recap, the history
/// detail and the weekly snapshot.
///
/// All three had their own copy at three different type sizes, so the same
/// screen-to-screen number changed weight as you navigated. VoiceOver also read
/// them as two unrelated strings ("3", then "sets"); combining fixes that.
struct StatTile: View {
    enum Style {
        /// Sits on its own card.
        case card
        /// Sits inside a card that already exists.
        case plain
    }

    let value: String
    let label: String
    var style: Style = .card

    init(_ value: String, _ label: String, style: Style = .card) {
        self.value = value
        self.label = label
        self.style = style
    }

    init(_ value: Int, _ label: String, style: Style = .card) {
        self.init("\(value)", label, style: style)
    }

    var body: some View {
        stack
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(value) \(label)")
    }

    @ViewBuilder
    private var stack: some View {
        let content = VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }

        switch style {
        case .card:
            content
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .todayCard()
        case .plain:
            content
        }
    }
}

#Preview {
    HStack(spacing: 10) {
        StatTile(4, "exercises")
        StatTile(18, "sets")
        StatTile("48m", "time")
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
