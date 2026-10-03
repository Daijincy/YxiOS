//
//  LoginView.swift
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
//  Platform login:
//    - 夸克 / 百度: WKWebView, after manual login grab the domain cookie string
//    - 123 云盘:    WKWebView, read localStorage 'authorToken' (JWT)
//    - 迅雷:        guest-only this version, info card
//

import SwiftUI
import WebKit

// MARK: - Top level login view

public struct LoginView: View {
    @EnvironmentObject private var loginSession: LoginSession
    @Environment(\.dismiss) private var dismiss

    private let initialPlatform: Platform
    @State private var selected: Platform
    @State private var showWeb = false
    @State private var notice: String?

    public init(platform: Platform) {
        self.initialPlatform = platform
        _selected = State(initialValue: platform)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("平台", selection: $selected) {
                        ForEach(Platform.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    statusCard

                    switch selected {
                    case .xunlei:
                        xunleiCard
                    default:
                        webLoginCard
                    }

                    clearButton
                }
                .padding()
            }
            .background(LiquidGlassBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showWeb) {
                WebLoginSheet(platform: selected)
            }
        }
    }

    private var isAuthed: Bool {
        loginSession.auth(for: selected) != nil
    }

    private var statusCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: isAuthed ? "checkmark.seal.fill" : "xmark.seal")
                    .font(.title2)
                    .foregroundStyle(isAuthed ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAuthed ? "已登录" : "未登录")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var statusDetail: String {
        switch selected {
        case .quark:
            return isAuthed ? "已获取 pan.quark.cn 登录 Cookie" : "在浏览器中登录夸克网页版后抓取 Cookie"
        case .baidu:
            return isAuthed ? "已获取 pan.baidu.com 登录 Cookie" : "在浏览器中登录百度网盘网页版后抓取 Cookie"
        case .pan123:
            return isAuthed ? "已获取 authorToken（JWT）" : "在浏览器中登录 123 云盘网页版后读取 authorToken"
        case .xunlei:
            return "当前版本支持游客解析分享链接"
        }
    }

    private var webLoginCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(loginGuideTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(loginGuideBody)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GlassButton("打开登录页", systemImage: "safari") {
                    showWeb = true
                }
            }
        }
    }

    private var loginGuideTitle: String {
        switch selected {
        case .quark: return "夸克网盘登录"
        case .baidu: return "百度网盘登录"
        case .pan123: return "123 云盘登录"
        case .xunlei: return "迅雷云盘"
        }
    }

    private var loginGuideBody: String {
        switch selected {
        case .quark:
            return "将打开夸克网盘网页版。请在页面中完成登录，然后返回本页点击右上角「完成登录」，App 会自动抓取 pan.quark.cn 的登录 Cookie。"
        case .baidu:
            return "将打开百度网盘网页版。请在页面中完成登录（建议扫码），然后返回本页点击右上角「完成登录」，App 会自动抓取 pan.baidu.com 的登录 Cookie（需含 BDUSS）。"
        case .pan123:
            return "将打开 123 云盘网页版。请在页面中完成登录，然后返回本页点击右上角「完成登录」，App 会自动读取 localStorage 中的 authorToken。"
        case .xunlei:
            return ""
        }
    }

    private var xunleiCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("游客模式", systemImage: "person.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("当前版本支持游客解析迅雷云盘分享链接；登录能力后续开放。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            loginSession.clearAuth(for: selected)
        } label: {
            Label("清除登录态", systemImage: "trash")
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - WKWebView login sheet

public struct WebLoginSheet: View {
    public let platform: Platform
    @EnvironmentObject private var loginSession: LoginSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WebLoginModel()
    @State private var message: String?

    public init(platform: Platform) {
        self.platform = platform
    }

    private var targetURL: URL {
        switch platform {
        case .quark:
            return URL(string: "https://pan.quark.cn/?fr=pc&platform=pc")!
        case .baidu:
            return URL(string: "https://pan.baidu.com/")!
        case .pan123:
            return URL(string: "https://yun.123pan.cn/")!
        case .xunlei:
            return URL(string: "https://pan.xunlei.com/")!
        }
    }

    public var body: some View {
        NavigationStack {
            CookieWebView(url: targetURL, model: model)
                .navigationTitle(platform.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成登录") { completeLogin() }
                    }
                }
        }
        .alert(isPresented: Binding<Bool>(get: { message != nil },
                                          set: { if !$0 { message = nil } })) {
            Alert(title: Text("提示"),
                  message: Text(message ?? ""),
                  dismissButton: .default(Text("好")))
        }
    }

    private func completeLogin() {
        switch platform {
        case .quark, .baidu:
            grabCookie()
        case .pan123:
            grabToken()
        case .xunlei:
            dismiss()
        }
    }

    private func grabCookie() {
        let domain: String = (platform == .quark) ? "pan.quark.cn" : "pan.baidu.com"
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            DispatchQueue.main.async {
                let filtered = cookies.filter { $0.domain.contains(domain) }
                let cookieString = filtered
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                if cookieString.isEmpty {
                    message = "未抓取到 \(domain) 的登录 Cookie，请确认已在网页中完成登录。"
                } else {
                    loginSession.setAuth(PlatformAuth(cookie: cookieString, token: nil, extra: [:]),
                                         for: self.platform)
                    dismiss()
                }
            }
        }
    }

    private func grabToken() {
        model.webView.evaluateJavaScript("localStorage.getItem('authorToken')") { result, _ in
            DispatchQueue.main.async {
                if let token = result as? String, !token.isEmpty {
                    loginSession.setAuth(PlatformAuth(cookie: nil, token: token, extra: [:]),
                                         for: .pan123)
                    dismiss()
                } else {
                    message = "未读取到 authorToken，请确认已在 123 云盘网页中完成登录。"
                }
            }
        }
    }
}

// MARK: - WKWebView model + representable

public final class WebLoginModel: ObservableObject {
    public let webView: WKWebView
    public init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
    }
}

public struct CookieWebView: UIViewRepresentable {
    public let url: URL
    public let model: WebLoginModel

    public init(url: URL, model: WebLoginModel) {
        self.url = url
        self.model = model
    }

    public func makeUIView(context: Context) -> WKWebView {
        model.webView.load(URLRequest(url: url))
        return model.webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
