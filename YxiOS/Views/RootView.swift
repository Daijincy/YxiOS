//
//  RootView.swift
//  YxiOS
//
//  YxiOS — iOS port of YunX (https://github.com/CYQawa/YunX)
//  Copyright (C) 2026 CYQawa
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Root tab container: 解析 / 下载 / 登录 / 设置.
//

import SwiftUI

public struct RootView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var selection = 0
    @State private var showOnboarding = false
    // Onboarding 后需要配置的平台（用于跳转到登录页时默认选中）
    @State private var pendingPlatform: Platform?
    // 下载开始提示
    @State private var showDownloadToast = false
    @State private var downloadToastName = ""

    public init() {
        // 首次启动检测
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            _showOnboarding = State(initialValue: true)
        }
    }

    public var body: some View {
        TabView(selection: $selection) {
            ResolveView()
                .tabItem {
                    Label("解析", systemImage: "link")
                }
                .tag(0)

            DownloadsView()
                .tabItem {
                    Label("下载", systemImage: "arrow.down.circle.fill")
                }
                .tag(1)

            LoginView(initialPlatform: pendingPlatform ?? .quark)
                .tabItem {
                    Label("登录", systemImage: "person.crop.circle")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(Color(red: 0.45, green: 0.6, blue: 1.0))
        // 下载开始提示 Toast
        .overlay(alignment: .top) {
            if showDownloadToast {
                downloadToast
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // 监听下载开始
        .onChange(of: downloadManager.downloadStartedFileName) { fileName in
            if let fileName = fileName, !fileName.isEmpty {
                downloadToastName = fileName
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showDownloadToast = true
                }
                // 1.5 秒后自动消失并跳转到下载页
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showDownloadToast = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selection = 1
                    }
                }
                // 清空，避免重复触发
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    downloadManager.downloadStartedFileName = nil
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { platformsToConfig in
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                showOnboarding = false
                // Onboarding 结束后：如果选了平台，跳到登录页并默认选中第一个
                if let first = platformsToConfig.first {
                    pendingPlatform = first
                    selection = 2
                }
            }
        }
    }

    // 下载开始 Toast
    private var downloadToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(Color(red: 0.45, green: 0.6, blue: 1.0))
            VStack(alignment: .leading, spacing: 2) {
                Text("已开始下载")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(downloadToastName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20)
    }
}
