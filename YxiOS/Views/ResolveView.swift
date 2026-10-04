//
//  ResolveView.swift
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
//  Paste a share link (+ optional extract code), resolve it via
//  ShareLinkParser, then browse the file tree and queue downloads.
//

import SwiftUI

public struct ResolveView: View {
    @EnvironmentObject private var loginSession: LoginSession
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var linkText = ""
    @State private var passwordText = ""
    @State private var isParsing = false
    @State private var parseError: String?
    @State private var shareInfo: ShareInfo?
    @State private var showLogin = false
    @State private var authVersion = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    inputCard

                    if isParsing {
                        loadingCard
                    } else if let err = parseError {
                        errorCard(err)
                    } else if let info = shareInfo {
                        resolvedHeader(info)
                        if needsLoginGate(info) {
                            loginGate(info)
                        } else {
                            DirectoryBrowserView(dir: nil, share: info)
                        }
                    } else {
                        placeholderCard
                    }
                }
                .padding()
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isParsing)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: parseError == nil)
            }
            .background(LiquidGlassBackground())
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // 点击空白处收起键盘
            .onTapGesture { hideKeyboard() }
            .navigationTitle("云析 · 解析")
            .navigationDestination(for: FileEntry.self) { dir in
                if let info = shareInfo {
                    DirectoryBrowserView(dir: dir, share: info)
                        .navigationTitle(dir.name)
                }
            }
            .sheet(isPresented: $showLogin, onDismiss: { authVersion += 1 }) {
                if let info = shareInfo {
                    LoginView(platform: info.platform)
                }
            }
        }
    }

    // MARK: Input card

    private var inputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("分享链接")
                    .font(.headline)
                    .foregroundStyle(.white)
                GlassTextField("粘贴夸克 / 百度 / 123 / 迅雷分享链接",
                               text: $linkText,
                               systemImage: "link")
                // 快捷按钮：粘贴 / 清除
                HStack(spacing: 10) {
                    Button(action: pasteFromClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                            Text("粘贴")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(red: 0.45, green: 0.6, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.45, green: 0.6, blue: 1.0).opacity(0.15))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    Button(action: { linkText = ""; passwordText = "" }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                            Text("清除")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                GlassTextField("提取码（可选）",
                               text: $passwordText,
                               systemImage: "key")
                GlassButton("解析", systemImage: "magnifyingglass") {
                    hideKeyboard()
                    Task { await performParse() }
                }
                .disabled(isParsing)
            }
        }
    }

    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            linkText = text
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("正在解析分享链接…")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("解析失败")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var placeholderCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("粘贴网盘分享链接开始解析")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("支持夸克网盘 · 百度网盘 · 123云盘 · 迅雷云盘")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func resolvedHeader(_ info: ShareInfo) -> some View {
        HStack(spacing: 10) {
            PlatformBadge(info.platform.displayName)
            Text("分享解析成功")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func loginGate(_ info: ShareInfo) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("该平台需要登录")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Text("「\(info.platform.displayName)」需要登录后才能解析或下载，请先完成登录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GlassButton("去登录", systemImage: "person.badge.key") {
                    showLogin = true
                }
            }
        }
    }

    // MARK: Logic

    private func needsLoginGate(_ info: ShareInfo) -> Bool {
        _ = authVersion  // re-eval after returning from login sheet
        let client = PlatformRegistry.client(for: info.platform)
        return client.requiresLogin && loginSession.auth(for: info.platform) == nil
    }

    private func performParse() async {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parseError = "请先粘贴分享链接"
            return
        }
        let code = passwordText.trimmingCharacters(in: .whitespaces)
        let combined: String
        if code.isEmpty {
            combined = trimmed
        } else {
            combined = "\(trimmed)\n提取码：\(code)"
        }

        guard let info = ShareLinkParser.parse(combined) else {
            shareInfo = nil
            parseError = "未能识别出有效的网盘分享链接，请检查粘贴内容"
            return
        }

        shareInfo = info
        parseError = nil

        let client = PlatformRegistry.client(for: info.platform)
        if client.requiresLogin && loginSession.auth(for: info.platform) == nil {
            // Show the login gate; the browser appears automatically after login.
            return
        }
    }
}

// MARK: - Directory browser (root or a sub-directory)

public struct DirectoryBrowserView: View {
    /// nil means the share root; otherwise a directory FileEntry.
    public let dir: FileEntry?
    public let share: ShareInfo

    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var files: [FileEntry] = []
    @State private var isLoading = false
    @State private var error: String?

    public init(dir: FileEntry?, share: ShareInfo) {
        self.dir = dir
        self.share = share
    }

    public var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("加载中…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else if let error = error {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("加载失败").font(.headline).foregroundStyle(.white)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            Task { await load() }
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                    }
                }
            } else if files.isEmpty {
                Text("空目录")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                FileListView(entries: files) { file in
                    Task {
                        await downloadManager.addDownload(platform: share.platform,
                                                          share: share,
                                                          file: file)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let client = PlatformRegistry.client(for: share.platform)
            if let dir = dir {
                files = try await client.listChildren(dir.id, of: share)
            } else {
                files = try await client.resolveShare(share)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
