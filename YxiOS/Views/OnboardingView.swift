//
//  OnboardingView.swift
//  YxiOS
//
//  首次启动引导：逐个网盘询问配置 → 欢迎页 → 进入主界面
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: (_ platformsToConfig: [Platform]) -> Void

    @State private var currentPage = 0
    @State private var selectedPlatforms: [Platform] = []
    // 每页元素的动画状态
    @State private var animStates: [Bool] = Array(repeating: false, count: 6)

    private let pages: [OnboardingPage] = [
        .platform(.quark),
        .platform(.baidu),
        .platform(.pan123),
        .platform(.xunlei),
        .welcome
    ]

    var body: some View {
        ZStack {
            // 动态渐变背景
            animatedBackground

            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { idx in
                    pageContent(for: pages[idx], index: idx)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))

            // 底部页面指示器
            VStack {
                Spacer()
                pageIndicator
                    .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea()
        .onAppear { triggerAnimations(for: 0) }
        .onChange(of: currentPage) { newPage in
            triggerAnimations(for: newPage)
        }
    }

    // MARK: - 动态背景

    private var animatedBackground: some View {
        ZStack {
            Color.black
            // 流动渐变光斑
            Circle()
                .fill(Color(red: 0.45, green: 0.6, blue: 1.0).opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: -100, y: -150)
            Circle()
                .fill(Color(red: 0.6, green: 0.45, blue: 1.0).opacity(0.12))
                .frame(width: 350, height: 350)
                .blur(radius: 70)
                .offset(x: 120, y: 100)
            Circle()
                .fill(Color(red: 0.45, green: 0.8, blue: 0.9).opacity(0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: 0, y: 200)
        }
    }

    // MARK: - 页面内容

    @ViewBuilder
    private func pageContent(for page: OnboardingPage, index: Int) -> some View {
        switch page {
        case .platform(let p):
            platformAskPage(p, index: index)
        case .welcome:
            welcomePage(index: index)
        }
    }

    // MARK: - 网盘询问页

    private func platformAskPage(_ platform: Platform, index: Int) -> some View {
        let info = platformInfo(platform)
        return VStack(spacing: 28) {
            Spacer()

            // 平台大图标
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: info.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                    .shadow(color: info.gradient[0].opacity(0.4), radius: 30)

                Image(systemName: info.icon)
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.white)
            }
            .opacity(animStates[safe: index] ?? false ? 1 : 0)
            .scaleEffect((animStates[safe: index] ?? false) ? 1 : 0.5)

            // 平台名称
            Text(info.name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .opacity(animStates[safe: index] ?? false ? 1 : 0)
                .offset(y: (animStates[safe: index] ?? false) ? 0 : 20)

            // 平台说明
            Text(info.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(animStates[safe: index] ?? false ? 1 : 0)
                .offset(y: (animStates[safe: index] ?? false) ? 0 : 20)

            Spacer()

            // 按钮组
            VStack(spacing: 12) {
                // 立即配置
                Button(action: {
                    selectedPlatforms.append(platform)
                    nextPage()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("立即配置")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: info.gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .padding(.horizontal, 40)
                }
                .buttonStyle(ScaleButtonStyle())

                // 稍后再说
                Button(action: { nextPage() }) {
                    Text("稍后再说")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .opacity(animStates[safe: index] ?? false ? 1 : 0)
            .offset(y: (animStates[safe: index] ?? false) ? 0 : 30)

            Spacer().frame(height: 40)
        }
    }

    // MARK: - 欢迎页

    private func welcomePage(index: Int) -> some View {
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
                    .frame(width: 110, height: 110)
                    .shadow(color: Color(red: 0.45, green: 0.6, blue: 1.0).opacity(0.5), radius: 30)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.white)
            }
            .opacity(animStates[safe: index] ?? false ? 1 : 0)
            .scaleEffect((animStates[safe: index] ?? false) ? 1 : 0.5)

            // 标题
            Text("云析 YxiOS")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .opacity(animStates[safe: index] ?? false ? 1 : 0)
                .offset(y: (animStates[safe: index] ?? false) ? 0 : 20)

            // 副标题
            Text("多网盘分享链接解析与下载\n已为你准备就绪")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(animStates[safe: index] ?? false ? 1 : 0)
                .offset(y: (animStates[safe: index] ?? false) ? 0 : 20)

            // 已选平台摘要
            if !selectedPlatforms.isEmpty {
                HStack(spacing: 16) {
                    ForEach(selectedPlatforms, id: \.self) { p in
                        VStack(spacing: 4) {
                            Image(systemName: platformInfo(p).icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color(red: 0.45, green: 0.6, blue: 1.0))
                            Text(platformInfo(p).shortName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.08))
                        )
                    }
                }
                .opacity(animStates[safe: index] ?? false ? 1 : 0)
                .offset(y: (animStates[safe: index] ?? false) ? 0 : 20)
            }

            Spacer()

            // 开始按钮
            Button(action: { onFinish(selectedPlatforms) }) {
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
            .buttonStyle(ScaleButtonStyle())
            .opacity(animStates[safe: index] ?? false ? 1 : 0)
            .offset(y: (animStates[safe: index] ?? false) ? 0 : 30)

            Spacer().frame(height: 40)
        }
    }

    // MARK: - 页面指示器

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { idx in
                Circle()
                    .fill(currentPage == idx ? Color(red: 0.45, green: 0.6, blue: 1.0) : .white.opacity(0.2))
                    .frame(width: currentPage == idx ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }

    // MARK: - 动画控制

    private func triggerAnimations(for page: Int) {
        // 重置所有页动画状态
        animStates = Array(repeating: false, count: pages.count)
        // 延迟后触发当前页动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animStates[page] = true
            }
        }
    }

    private func nextPage() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if currentPage < pages.count - 1 {
                currentPage += 1
            }
        }
    }

    // MARK: - 平台信息

    private struct PlatformInfo {
        let name: String
        let shortName: String
        let icon: String
        let description: String
        let gradient: [Color]
    }

    private func platformInfo(_ p: Platform) -> PlatformInfo {
        switch p {
        case .quark:
            return PlatformInfo(
                name: "夸克网盘",
                shortName: "夸克",
                icon: "q.circle.fill",
                description: "支持夸克分享链接解析与高速下载，需登录获取 Cookie",
                gradient: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.1, green: 0.4, blue: 0.8)]
            )
        case .baidu:
            return PlatformInfo(
                name: "百度网盘",
                shortName: "百度",
                icon: "b.circle.fill",
                description: "支持百度网盘分享链接解析下载，需登录获取 BDUSS",
                gradient: [Color(red: 0.9, green: 0.4, blue: 0.2), Color(red: 0.7, green: 0.2, blue: 0.1)]
            )
        case .pan123:
            return PlatformInfo(
                name: "123 云盘",
                shortName: "123",
                icon: "1.circle.fill",
                description: "支持 123 云盘分享链接解析下载，需登录获取 authorToken",
                gradient: [Color(red: 0.1, green: 0.75, blue: 0.6), Color(red: 0.05, green: 0.55, blue: 0.45)]
            )
        case .xunlei:
            return PlatformInfo(
                name: "迅雷云盘",
                shortName: "迅雷",
                icon: "x.circle.fill",
                description: "支持迅雷分享链接解析，当前版本游客模式即可使用",
                gradient: [Color(red: 0.55, green: 0.3, blue: 0.9), Color(red: 0.35, green: 0.15, blue: 0.7)]
            )
        }
    }
}

// MARK: - 页面类型

private enum OnboardingPage {
    case platform(Platform)
    case welcome
}

// MARK: - 缩放按钮样式（防止交互意外，点击有明确反馈）

public struct ScaleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

// MARK: - 数组安全下标

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
