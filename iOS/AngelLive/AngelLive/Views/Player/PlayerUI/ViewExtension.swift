//
//  ViewExtension.swift
//  KSPlayer
//
//  Created by kintan on 11/30/24.
//

import SwiftUI
import KSPlayer

#if !os(tvOS)
@MainActor
public struct PlayBackCommands: Commands {
    @FocusedObject
    private var config: KSVideoPlayer.Coordinator?
    public init() {}

    public var body: some Commands {
        CommandMenu("PlayBack") {
            if let config {
                Button(config.state.isPlaying ? "Pause" : "Resume") {
                    if config.state.isPlaying {
                        config.playerLayer?.pause()
                    } else {
                        config.playerLayer?.play()
                    }
                }
                .keyboardShortcut(.space, modifiers: .none)
                Button(config.isMuted ? "Mute" : "Unmute") {
                    config.isMuted.toggle()
                }
            }
        }
    }
}
#endif

public struct MenuView<SelectionValue, Content, Label>: View where SelectionValue: Hashable, Content: View, Label: View {
    public let selection: Binding<SelectionValue>
    @ViewBuilder
    public let content: () -> Content
    @ViewBuilder
    public let label: () -> Label
    @State
    private var showMenu = false
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.selection = selection
        self.content = content
        self.label = label
        showMenu = showMenu
    }

    public var body: some View {
        Menu {
            Picker(selection: selection) {
                content()
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            label()
                .menuLabelStyle()
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
    }
}

public extension View {
    func ksMenuLabelStyle() -> some View {
        modifier(MenuLabelStyleModifier())
    }

    func ksIsFocused(_ binding: Binding<Bool>) -> some View {
        modifier(WhenFocusedModifier(isFocuse: binding))
    }

    func ksIsFocused<T: Hashable>(_ binding: Binding<T?>, equals value: T) -> some View {
        modifier(FocusModifier(binding: binding, value: value))
    }

    @ViewBuilder
    func ksBorderlessButton() -> some View {
        #if os(tvOS)
        if #available(tvOS 17, *) {
            self.buttonStyle(.borderless)
        } else {
            self
        }
        #else
        buttonStyle(.borderless)
        #endif
    }
}

public extension Binding {
    var option: Binding<Value?> {
        Binding<Value?>(
            get: { wrappedValue },
            set: { newValue in
                if let newValue {
                    wrappedValue = newValue
                }
            }
        )
    }
}

/// 这是只读的焦点状态，用于根据焦点调整样式
private struct WhenFocusedModifier: ViewModifier {
    @Environment(\.isFocused)
    private var isFocused: Bool
    @Binding
    var isFocuse: Bool
    func body(content: Content) -> some View {
        content
            .onChange(of: isFocused) { newValue in
                isFocuse = newValue
            }
    }
}

private struct FocusModifier<T: Hashable>: ViewModifier {
    @Binding
    var binding: T?
    let value: T
    @FocusState
    private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: binding) { newValue in
                focused = (newValue == value)
            }
            .onChange(of: focused) { newValue in
                if newValue {
                    binding = value
                } else if binding == value {
                    binding = nil
                }
            }
    }
}

private struct MenuLabelStyleModifier: ViewModifier {
    @State
    private var isFocus: Bool = false

    func body(content: Content) -> some View {
        content
            .symbolVariant(isFocus ? .fill : .none)
            .foregroundStyle(isFocus ? .black : .secondary)
            .scaleEffect(isFocus ? 1.25 : 1)
        #if os(tvOS)
            .background {
                Circle()
                    .fill(.white)
                    .opacity(isFocus ? 1 : 0)
                    .scaleEffect(isFocus ? 2.2 : 1)
            }
            .animation(.spring(duration: 0.18), value: isFocus)
        #else
            .font(.title3.weight(.semibold))
            .imageScale(.medium)
        #endif
            .ksIsFocused($isFocus)
    }
}

public struct KSPlatformView<Content: View>: View {
    private let content: () -> Content
    public var body: some View {
        #if os(tvOS)
        // tvos需要加NavigationStack，不然无法出现下拉框。iOS不能加NavigationStack，不然会丢帧。
        NavigationStack {
            ScrollView {
                content()
                    .padding()
            }
        }
        .pickerStyle(.navigationLink)
        #else
        Form {
            content()
        }
        .formStyle(.grouped)
        #endif
    }

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
}

extension EventModifiers {
    static let none = Self()
}

extension View {
    func then(_ body: (inout Self) -> Void) -> Self {
        var result = self
        body(&result)
        return result
    }
}

public extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder
    func `if`(_ condition: @autoclosure () -> Bool, transform: (Self) -> some View) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`(_ condition: @autoclosure () -> Bool, if ifTransform: (Self) -> some View, else elseTransform: (Self) -> some View) -> some View {
        if condition() {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }

    @ViewBuilder
    func ifLet<T: Any>(_ optionalValue: T?, transform: (Self, T) -> some View) -> some View {
        if let value = optionalValue {
            transform(self, value)
        } else {
            self
        }
    }
}


extension View {
    func onKeyPressLeftArrow(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.leftArrow) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }

    func onKeyPressRightArrow(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.rightArrow) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }

    func onKeyPressSapce(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.space) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }

    func allowedDynamicRange() -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return self.allowedDynamicRange(KSOptions.subtitleDynamicRange)
        } else {
            return self
        }
    }

    #if !os(tvOS)
    func textSelection() -> some View {
        self.textSelection(.enabled)
    }
    #endif

    func italic(value: Bool) -> some View {
        self.italic(value)
    }

    func ksIgnoresSafeArea() -> some View {
        self.ignoresSafeArea()
    }

    func onHoverActive(point: @escaping (CGPoint?) -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onContinuousHover { phase in
                switch phase {
                case let .active(value):
                    point(value)
                default:
                    point(nil)
                }
            }
        } else {
            return self
        }
    }
}
