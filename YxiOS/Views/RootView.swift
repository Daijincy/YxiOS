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
    @State private var showWelcome = false

    public init() {
        // 首次启动检测
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            _showWelcome = State(initialValue: true)
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

            LoginView()
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
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                showWelcome = false
                // 欢迎结束后跳到登录页引导配置
                selection = 2
            }
        }
    }
}

// MARK: - 欢迎动画

struct WelcomeView: View {
    let onFinish: () -> Void
    @State private var phase = 0
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonScale: CGFloat = 0.8

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.45, green: 0.6, blue: 1.0),
                                         Color(red: 0.6, green: 0.45, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color(red: 0.45, green: 0.6, blue: 1.0).opacity(0.5), radius: 30)

                    Image(systemName: "cloud.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // 标题
                Text("云析 YxiOS")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)

                // 副标题
                VStack(spacing: 8) {
                    Text("多网盘分享链接解析与下载")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        platformBadge("夸克", "q.circle")
                        platformBadge("百度", "b.circle")
                        platformBadge("123", "1.circle")
                        platformBadge("迅雷", "x.circle")
                    }
                }
                .opacity(subtitleOpacity)

                Spacer()

                // 开始按钮
                Button(action: onFinish) {
                    HStack(spacing: 8) {
                        Text("开始使用")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.45, green: 0.6, blue: 1.0),
                                             Color(red: 0.6, green: 0.45, blue: 1.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .padding(.horizontal, 40)
                }
                .opacity(buttonOpacity)
                .scaleEffect(buttonScale)

                Spacer().frame(height: 40)
            }
        }
        .onAppear {
            // 动画序列
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut.delay(0.6)) {
                titleOpacity = 1.0
            }
            withAnimation(.easeOut.delay(0.9)) {
                subtitleOpacity = 1.0
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(1.2)) {
                buttonOpacity = 1.0
                buttonScale = 1.0
            }
        }
    }

    private func platformBadge(_ name: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.6, blue: 1.0))
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 56, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.08))
        )
    }
}
