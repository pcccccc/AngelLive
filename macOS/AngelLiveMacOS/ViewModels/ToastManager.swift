//
//  ToastManager.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/22/25.
//  Supported by AI助手Claude
//

import SwiftUI

// Toast 数据模型
struct ToastMessage: Identifiable {
    let id = UUID()
    let icon: String
    let message: String
    let type: ToastType

    enum ToastType {
        case success
        case error
        case info

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .info: return .blue
            }
        }
    }
}

// Toast Manager
@Observable
class ToastManager {
    var currentToast: ToastMessage?
    private var hideTask: Task<Void, Never>?

    func show(icon: String, message: String, type: ToastMessage.ToastType = .info, duration: TimeInterval = 2.0) {
        // 取消之前的隐藏任务
        hideTask?.cancel()

        // 显示新的 Toast
        currentToast = ToastMessage(icon: icon, message: message, type: type)

        // 设置自动隐藏
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run {
                    currentToast = nil
                }
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        currentToast = nil
    }
}

// Toast View
struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon)
                .font(.title3)
                .foregroundColor(toast.type.color)

            Text(toast.message)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
