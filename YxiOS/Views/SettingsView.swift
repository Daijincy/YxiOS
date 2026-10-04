//
//  SettingsView.swift
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
//  About page: version, AGPL-3.0 attribution, upstream repo, disclaimer,
//  supported-platform notes.
//

import SwiftUI

public struct SettingsView: View {
    @State private var threadCount: Int = Storage.downloadThreads
    @State private var customThreads: String = ""
    @State private var showCustomInput = false

    private let presetThreads = [8, 16, 32, 64, 128, 256]

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    downloadCard
                    appCard
                    licenseCard
                    platformsCard
                    disclaimerCard
                }
                .padding()
            }
            .background(LiquidGlassBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("设置")
        }
    }

    // MARK: - 下载设置

    private var downloadCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("下载设置", systemImage: "bolt.horizontal.fill")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 6) {
                    Text("下载线程数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("线程越多速度越快，但过高可能被网盘 CDN 限流。建议 32-64。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // 预设线程数按钮组
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                    ForEach(presetThreads, id: \.self) { count in
                        ThreadButton(title: "\(count)", isSelected: threadCount == count && !showCustomInput) {
                            threadCount = count
                            showCustomInput = false
                            Storage.downloadThreads = count
                        }
                    }
                    // 自定义按钮
                    ThreadButton(title: "自定义", isSelected: showCustomInput) {
                        showCustomInput = true
                        customThreads = "\(threadCount)"
                    }
                }

                // 自定义输入框
                if showCustomInput {
                    HStack(spacing: 8) {
                        TextField("输入线程数 (1-512)", text: $customThreads)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                        Button("确定") {
                            if let v = Int(customThreads), v >= 1, v <= 512 {
                                threadCount = v
                                Storage.downloadThreads = v
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                // 当前生效值
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("当前：\(threadCount) 线程（\(threadCount) 分片并发下载）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var appCard: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: "cloud")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.45, green: 0.4, blue: 0.9),
                                     Color(red: 0.3, green: 0.55, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("YxiOS")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("云析 · iOS 移植版")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("版本 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var licenseCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("开源协议", systemImage: "curlybraces")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("本项目为开源项目 YunX（云析）的 iOS 移植版，以 AGPL-3.0 协议开源。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Link(destination: URL(string: "https://github.com/CYQawa/YunX")!) {
                    Label("原项目 YunX · GitHub", systemImage: "link")
                        .font(.subheadline)
                }
            }
        }
    }

    private var platformsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("支持平台", systemImage: "square.stack.3d.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                platformRow("夸克网盘", "支持游客解析小文件；登录后可下载大文件")
                Divider().background(Color.white.opacity(0.1))
                platformRow("百度网盘", "需要登录（BDUSS）后解析与下载")
                Divider().background(Color.white.opacity(0.1))
                platformRow("123 云盘", "可游客浏览分享；登录后获取下载直链")
                Divider().background(Color.white.opacity(0.1))
                platformRow("迅雷云盘", "当前支持游客解析分享链接")
            }
        }
    }

    private func platformRow(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline).foregroundStyle(.white)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var disclaimerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("免责声明", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("本项目仅用于个人学习与研究，请遵守各网盘平台的服务条款与相关版权法规。请勿用于任何商业用途或侵犯他人合法权益。使用本软件所产生的一切后果由使用者自行承担。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 线程数按钮

private struct ThreadButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color(red: 0.45, green: 0.55, blue: 0.95).opacity(0.8) : Color.white.opacity(0.08))
                )
                .foregroundStyle(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}
