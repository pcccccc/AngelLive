import AngelLiveCore
import AppKit
import SwiftUI

struct MacPlayerName: View {
    private let name: String
    private let font: NSFont
    private let maximumWidth: CGFloat?

    init(_ name: String, font: NSFont, maximumWidth: CGFloat? = nil) {
        self.name = name
        self.font = font
        self.maximumWidth = maximumWidth
    }

    var body: some View {
        let text = BracketSafeName(name)
        let intrinsicWidth = ceil((text.fullTitle as NSString).size(withAttributes: [.font: font]).width)
        Text(verbatim: text.fullTitle)
            .font(Font(font))
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: maximumWidth.map { min($0, intrinsicWidth) })
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    let title = text.title { value in
                        (value as NSString).size(withAttributes: [.font: font]).width <= proxy.size.width
                    }
                    if !title.isEmpty {
                        Text(verbatim: title)
                            .font(Font(font))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
    }
}
