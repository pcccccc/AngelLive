//
//  BilibiliWebLoginView.swift
//  AngelLive
//
//  Created by pangchong on 11/28/25.
//

import SwiftUI
import AngelLiveCore

// MARK: - Main Login View

struct BilibiliWebLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BilibiliLoginViewModel()
    @StateObject private var syncService = BilibiliCookieSyncService.shared

    @State private var showLogoutConfirm = false
    @State private var showTvOSSyncSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                if !viewModel.isLoggedIn {
                    webLoginView
                } else {
                    loggedInView
                }
            }
            .navigationTitle("哔哩哔哩登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isLoggedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("退出登录") {
                            showLogoutConfirm = true
                        }
                        .foregroundStyle(AppConstants.Colors.error)
                    }
                }
            }
            .alert("退出登录", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) {}
                Button("确定", role: .destructive) {
                    viewModel.logout()
                }
            } message: {
                Text("确定要退出账号吗？")
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    // MARK: - Web Login View

    private var webLoginView: some View {
        VStack(spacing: 0) {
            BilibiliLoginWebView(
                url: viewModel.loginURL,
                onWebViewCreated: { webView in
                    viewModel.currentWebView = webView
                },
                onNavigationStateChange: { title, url, didFinish in
                    viewModel.checkLoginStatus(title: title, url: url, didFinish: didFinish)
                }
            )
            .id(viewModel.webViewKey)
            .ignoresSafeArea(.all, edges: .bottom)

            statusBar
        }
    }

    private var statusBar: some View {
        VStack(spacing: AppConstants.Spacing.xs) {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppConstants.Spacing.md)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    // MARK: - Logged In View

    private var loggedInView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppConstants.Spacing.xl) {
                userHeader
                    .padding(.top, AppConstants.Spacing.xxl)

                accountInfoCard

                tvOSSyncCard

                Spacer(minLength: AppConstants.Spacing.xxl)
            }
        }
        .scrollContentBackground(.hidden)
        .task {
            if viewModel.userInfo == nil && !viewModel.cookie.isEmpty {
                await viewModel.validateCookie()
            }
        }
        .sheet(isPresented: $showTvOSSyncSheet) {
            TvOSSyncSheet(syncService: syncService, cookie: viewModel.cookie)
        }
    }

    // MARK: - User Header

    private var userHeader: some View {
        VStack(spacing: AppConstants.Spacing.lg) {
            if viewModel.isValidatingCookie {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(width: 80, height: 80)
            } else if let user = viewModel.userInfo {
                AsyncImage(url: URL(string: user.face ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(AppConstants.Colors.success.gradient)
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppConstants.Colors.success, lineWidth: 3))

                Text(user.displayName)
                    .font(.title.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)

                if let sign = user.sign, !sign.isEmpty {
                    Text(sign)
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            } else {
                Image(systemName: viewModel.validationError != nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(viewModel.validationError != nil ? AppConstants.Colors.warning.gradient : AppConstants.Colors.success.gradient)

                Text(viewModel.validationError != nil ? "验证失败" : "登录成功")
                    .font(.title.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)

                if let error = viewModel.validationError {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(AppConstants.Colors.error)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Account Info Card

    private var accountInfoCard: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            Text("账号信息")
                .font(.headline)
                .foregroundStyle(AppConstants.Colors.primaryText)

            if let user = viewModel.userInfo {
                BilibiliInfoRow(title: "用户名", value: user.displayName)

                if let mid = user.mid {
                    BilibiliInfoRow(title: "用户 ID", value: "\(mid)")
                }
            } else if let uid = viewModel.extractUidFromCookie() {
                BilibiliInfoRow(title: "用户 ID", value: uid)
            }

            cookieStatusRow

            if viewModel.validationError != nil {
                Button {
                    Task {
                        await viewModel.validateCookie()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("重新验证")
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppConstants.Colors.link)
                }
                .padding(.top, AppConstants.Spacing.xs)
            }
        }
        .padding()
        .background(AppConstants.Colors.materialBackground)
        .cornerRadius(AppConstants.CornerRadius.lg)
        .padding(.horizontal)
    }

    private var cookieStatusRow: some View {
        HStack {
            Text("Cookie 状态")
                .foregroundStyle(AppConstants.Colors.secondaryText)
            Spacer()
            if viewModel.isValidatingCookie {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("验证中...")
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
            } else if viewModel.validationError != nil {
                Text("已失效")
                    .foregroundStyle(AppConstants.Colors.error)
            } else {
                Text("有效")
                    .foregroundStyle(AppConstants.Colors.success)
            }
        }
    }

    // MARK: - tvOS Sync Card

    private var tvOSSyncCard: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HStack {
                Image(systemName: "appletvremote.gen4.fill")
                    .font(.title2)
                    .foregroundStyle(AppConstants.Colors.link)
                Text("同步到 tvOS")
                    .font(.headline)
                    .foregroundStyle(AppConstants.Colors.primaryText)
                Spacer()
            }

            Text("将登录信息同步到同一局域网内的 Apple TV")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)

            Button {
                showTvOSSyncSheet = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("开始同步")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppConstants.Spacing.sm)
                .background(AppConstants.Colors.link)
                .cornerRadius(AppConstants.CornerRadius.md)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(AppConstants.Colors.materialBackground)
        .cornerRadius(AppConstants.CornerRadius.lg)
        .padding(.horizontal)
    }
}

// MARK: - Helper Views

private struct BilibiliInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(AppConstants.Colors.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(AppConstants.Colors.primaryText)
        }
    }
}

#Preview {
    BilibiliWebLoginView()
}
