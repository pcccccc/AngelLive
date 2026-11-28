#if os(tvOS) || (os(macOS) && DEBUG)
import Foundation

struct TVBackCommandSequence {
    enum Event { case menu, escapeDown, escapeRepeat, escapeUp }
    enum Destination: Equatable { case source, modal(UUID) }
    private struct Modal {
        let id: UUID
        var isClosing = false
    }
    private struct HeldEscape {
        let source: UUID
        let began: ContinuousClock.Instant
        let pairedWithMenu: Bool
    }

    private struct Cooldown {
        let until: ContinuousClock.Instant
        let modalDismissed: Bool

        init(from now: ContinuousClock.Instant, modalDismissed: Bool = false) {
            until = now.advanced(by: .milliseconds(400))
            self.modalDismissed = modalDismissed
        }
    }

    private var heldEscape: HeldEscape?
    private var lastReturn: (source: UUID, event: Event, time: ContinuousClock.Instant)?
    private var cooldowns: [UUID: Cooldown] = [:]
    private var activeModals: [Modal] = []

    mutating func beginModal(_ source: UUID) {
        guard !activeModals.contains(where: { $0.id == source }) else { return }
        if heldEscape?.source != source { heldEscape = nil }
        activeModals.append(Modal(id: source))
    }

    mutating func markModalClosing(_ source: UUID, at now: ContinuousClock.Instant) {
        guard let index = activeModals.firstIndex(where: { $0.id == source }),
              !activeModals[index].isClosing else { return }
        activeModals[index].isClosing = true
        if heldEscape?.source == source { heldEscape = nil }
        cooldowns[source] = Cooldown(from: now)
    }

    mutating func endModal(_ source: UUID, at now: ContinuousClock.Instant) {
        guard let index = activeModals.firstIndex(where: { $0.id == source }) else { return }
        activeModals.remove(at: index)
        if heldEscape?.source == source { heldEscape = nil }
        cooldowns[source] = Cooldown(from: now, modalDismissed: true)
    }

    mutating func cancelSource(_ source: UUID, at now: ContinuousClock.Instant) {
        expire(at: now)
        guard heldEscape?.source == source else { return }
        heldEscape = nil
        cooldowns[source] = Cooldown(from: now)
    }

    private mutating func expire(at now: ContinuousClock.Instant) {
        cooldowns = cooldowns.filter { now < $0.value.until }
        if let heldEscape, heldEscape.began.duration(to: now) >= .seconds(5) {
            self.heldEscape = nil
        }
    }

    mutating func route(for event: Event, source: UUID, at now: ContinuousClock.Instant) -> Destination? {
        expire(at: now)
        // Transparent covers can deliver keyboard and remote input to different views.
        if let top = activeModals.last {
            guard !top.isClosing, accepts(event, source: top.id, at: now) else { return nil }
            markModalClosing(top.id, at: now)
            return .modal(top.id)
        }
        return accepts(event, source: source, at: now) ? .source : nil
    }

    private mutating func accepts(_ event: Event, source: UUID, at now: ContinuousClock.Instant) -> Bool {
        switch event {
        case .escapeDown:
            guard heldEscape == nil else { return false }
            // A key-down delivered just after dismissal cannot start a press on the revealed view.
            guard !cooldowns.contains(where: { $0.key != source && $0.value.modalDismissed }) else { return false }
            // Menu can dismiss a modal before this same press delivers key-down to its parent.
            let paired = isRecentReturn(.menu, at: now)
            if paired { lastReturn = nil }
            heldEscape = HeldEscape(source: source, began: now, pairedWithMenu: paired)
            return false
        case .escapeRepeat:
            return false
        case .escapeUp:
            guard let held = heldEscape else { return false }
            heldEscape = nil
            guard held.source == source else {
                cooldowns[held.source] = Cooldown(from: now)
                return false
            }
            if held.pairedWithMenu { return false }
        case .menu:
            guard heldEscape == nil else { return false }
        }

        guard !cooldowns.keys.contains(where: { $0 != source }) else { return false }
        if event == .menu, lastReturn?.source == source, isRecentReturn(.escapeUp, at: now) {
            lastReturn = nil
            return false
        }
        lastReturn = (source, event, now)
        cooldowns[source] = Cooldown(from: now)
        return true
    }

    private func isRecentReturn(_ event: Event, at now: ContinuousClock.Instant) -> Bool {
        guard let lastReturn else { return false }
        return lastReturn.event == event && lastReturn.time.duration(to: now) < .milliseconds(100)
    }
}

@MainActor
final class TVBackCommandRouter {
    private var sequence = TVBackCommandSequence()
    private var modalActions: [UUID: () -> Void] = [:]

    func beginModal(_ id: UUID, perform: @escaping () -> Void) {
        sequence.beginModal(id)
        modalActions[id] = perform
    }

    func markModalClosing(_ id: UUID, at now: ContinuousClock.Instant) {
        sequence.markModalClosing(id, at: now)
    }

    func endModal(_ id: UUID, at now: ContinuousClock.Instant) {
        sequence.endModal(id, at: now)
        modalActions.removeValue(forKey: id)
    }

    func cancelSource(_ id: UUID, at now: ContinuousClock.Instant) {
        sequence.cancelSource(id, at: now)
    }

    func handle(_ event: TVBackCommandSequence.Event, from source: UUID,
                at now: ContinuousClock.Instant, perform: () -> Void) {
        switch sequence.route(for: event, source: source, at: now) {
        case .modal(let id): modalActions[id]?()
        case .source: perform()
        case nil: break
        }
    }
}
#endif

#if os(tvOS)
import SwiftUI

public extension EnvironmentValues {
    @Entry var tvFullUIBackNavigation = false
}

@MainActor
public enum TVBackCommandInput {
    private static let router = TVBackCommandRouter()

    public static func beginModal(_ source: UUID, perform: @escaping () -> Void) {
        router.beginModal(source, perform: perform)
    }

    public static func markModalClosing(_ source: UUID) {
        router.markModalClosing(source, at: .now)
    }

    public static func endModal(_ source: UUID) {
        router.endModal(source, at: .now)
    }

    static func cancelSource(_ source: UUID) {
        router.cancelSource(source, at: .now)
    }

    static func menu(from source: UUID, perform: () -> Void) {
        router.handle(.menu, from: source, at: .now, perform: perform)
    }

    static func escape(_ press: KeyPress, from source: UUID, perform: () -> Void) -> KeyPress.Result {
        let event: TVBackCommandSequence.Event
        switch press.phase {
        case .down: event = .escapeDown
        case .up: event = .escapeUp
        default: event = .escapeRepeat
        }
        router.handle(event, from: source, at: .now, perform: perform)
        return .handled
    }
}

private struct TVFullUIBackModifier: ViewModifier {
    let enabled: Bool
    let modalSource: UUID?
    let perform: () -> Void
    @State private var localSourceID = UUID()

    private var sourceID: UUID { modalSource ?? localSourceID }

    func body(content: Content) -> some View {
        content
            .onExitCommand(perform: enabled ? { TVBackCommandInput.menu(from: sourceID, perform: perform) } : nil)
            .onKeyPress(keys: enabled ? [.escape] : [], phases: .all) {
                TVBackCommandInput.escape($0, from: sourceID, perform: perform)
            }
            .onChange(of: enabled) { _, enabled in
                if !enabled { TVBackCommandInput.cancelSource(sourceID) }
            }
            .onDisappear { TVBackCommandInput.cancelSource(sourceID) }
    }
}

public extension View {
    func tvFullUIBackCommand(enabled: Bool = true, source: UUID? = nil, perform: @escaping () -> Void) -> some View {
        modifier(TVFullUIBackModifier(enabled: enabled, modalSource: source, perform: perform))
    }
}
#endif
