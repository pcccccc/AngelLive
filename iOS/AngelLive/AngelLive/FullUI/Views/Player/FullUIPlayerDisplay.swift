import AngelLiveCore
import SwiftUI
import UIKit

struct FullUIPlayerName: View {
    private let name: String
    private let font: UIFont
    private let maximumWidth: CGFloat?

    init(_ name: String, font: UIFont, maximumWidth: CGFloat? = nil) {
        self.name = name
        self.font = font
        self.maximumWidth = maximumWidth
    }

    var body: some View {
        let text = BracketSafeName(name)
        Text(verbatim: text.fullTitle)
            .font(Font(font))
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: maximumWidth)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    let title = text.title { value in
                        (value as NSString).size(withAttributes: [.font: font]).width <= proxy.size.width
                    }
                    Text(verbatim: title)
                        .font(Font(font))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
    }
}
