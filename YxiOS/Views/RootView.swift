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
    @State private var selection = 0
    @State private var showOnboarding = false
    // Onboarding 后需要配置的平台（用于跳转到登录页时默认选中）
    @State private var pendingPlatform: Platform?

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
}
