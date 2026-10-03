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
    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
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
