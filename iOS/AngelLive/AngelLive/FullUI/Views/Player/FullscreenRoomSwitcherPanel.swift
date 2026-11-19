import SwiftUI
import AngelLiveCore

struct FullscreenRoomSwitcherPanel: View {
    let content: RoomSwitcherListContent
    @Binding var selectedSource: RoomSwitchSource
    let onSelect: (LiveModel) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            roomList
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    private var header: some View {
        HStack(spacing: 8) {
            sourceMenu
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭换台")
        }
        .frame(minHeight: FullUIPlayerChrome.controlSize)
        .padding(.horizontal, FullUIPlayerDetailChrome.inset)
    }

    private var sourceMenu: some View {
        Menu {
            Picker("来源", selection: $selectedSource) {
                ForEach(RoomSwitchSource.allCases, id: \.self) { source in
                    Label(source.title, systemImage: source.systemImage)
                        .tag(source)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("换台")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize()
                Text("·")
                    .fixedSize()
                Text(selectedSource.inlineTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: FullUIPlayerChrome.controlSize, minHeight: FullUIPlayerChrome.controlSize)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("换台来源")
        .accessibilityValue(selectedSource.inlineTitle)
    }

    private var roomList: some View {
        GeometryReader { geometry in
            ScrollView {
                RoomSwitcherRows(
                    content: content,
                    coverWidth: RoomSwitcherRows.coverWidth(in: geometry.size.width),
                    onSelect: onSelect
                )
                .padding(.horizontal, FullUIPlayerDetailChrome.inset)
                .padding(.vertical, 8)
            }
            .id(selectedSource)
        }
    }
}
