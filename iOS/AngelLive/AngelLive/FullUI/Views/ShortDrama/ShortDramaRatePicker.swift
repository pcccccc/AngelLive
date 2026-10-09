import SwiftUI

struct ShortDramaRatePicker: View {
    @Binding var selection: Float
    let availableWidth: CGFloat
    let onSelect: (Float) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return 2 }
        return availableWidth >= 332 && dynamicTypeSize <= .large ? 6 : 3
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 52), spacing: 4), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Self.rates, id: \.self) { rate in
                let isSelected = selection == rate
                Button {
                    selection = rate
                    onSelect(rate)
                } label: {
                    Text(ShortDramaRateLabel.text(for: rate))
                        .font(.callout.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .black : .white)
                        .lineLimit(1)
                        .frame(minWidth: 52, maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? Color.white : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ShortDramaRateLabel.text(for: rate)) 倍速")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }

    private static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2, 3]
}

enum ShortDramaRateLabel {
    private static let cycleRates: [Float] = [1, 1.25, 1.5, 2, 3]

    static func text(for rate: Float) -> String {
        switch rate {
        case 0.75: "0.75×"
        case 1: "1×"
        case 1.25: "1.25×"
        case 1.5: "1.5×"
        case 2: "2×"
        case 3: "3×"
        default: "\(rate)×"
        }
    }

    static func nextCycleRate(after rate: Float) -> Float {
        guard let index = cycleRates.firstIndex(of: rate) else { return 1 }
        return cycleRates[(index + 1) % cycleRates.count]
    }
}
