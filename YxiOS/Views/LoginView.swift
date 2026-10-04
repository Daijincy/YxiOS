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
//  Platform login (移植自 YunX WebLoginAutoDetect + QuarkLoginScreen):
//    - 夸克 / 百度: WKWebView + 自定义 PC UA，登录后自动轮询检测 Cookie，
//      检测到有效登录态（夸克需 __pus+__puus，百度需 BDUSS）自动保存；
//      右上角「完成登录」保留作手动兜底；另支持手动粘贴 Cookie。
//    - 123 云盘:    WKWebView，登录后自动读取 localStorage authorToken（JWT）
//    - 迅雷:        guest-only this version, info card
//

import SwiftUI
import WebKit
import Combine

// MARK: - Top level login view

public struct LoginView: View {
    @EnvironmentObject private var loginSession: LoginSession
    @Environment(\.dismiss) private var dismiss

    private let initialPlatform: Platform
    @State private var selected: Platform
    @State private var showWeb = false
    @State private var showManualCookie = false
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
            .sheet(isPresented: $showManualCookie) {
                ManualCookieSheet(platform: selected)
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
            return isAuthed ? "已获取 pan.quark.cn 登录 Cookie" : "在浏览器中登录夸克网页版后自动抓取 Cookie"
        case .baidu:
            return isAuthed ? "已获取 pan.baidu.com 登录 Cookie" : "在浏览器中登录百度网盘网页版后自动抓取 Cookie"
        case .pan123:
            return isAuthed ? "已获取 authorToken（JWT）" : "在浏览器中登录 123 云盘网页版后自动读取 authorToken"
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
                HStack(spacing: 10) {
                    GlassButton("打开登录页", systemImage: "safari") {
                        showWeb = true
                    }
                    Button {
                        showManualCookie = true
                    } label: {
                        Label("手动输入", systemImage: "keyboard")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
            return "将打开夸克网盘 PC 网页版。请在页面中完成登录，登录成功后 App 会自动检测并保存 Cookie（需含 __pus 与 __puus）。若未自动检测，可点右上角「完成登录」手动保存，或用「手动输入」粘贴 Cookie。"
        case .baidu:
            return "将打开百度网盘网页版。请在页面中完成登录（建议扫码），登录成功后 App 会自动检测并保存 Cookie（需含 BDUSS）。若未自动检测，可点右上角「完成登录」手动保存。"
        case .pan123:
            return "将打开 123 云盘网页版。请在页面中完成登录，登录成功后 App 会自动读取 localStorage 中的 authorToken（JWT）并保存。"
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

// MARK: - WKWebView login sheet（含自动登录检测）

public struct WebLoginSheet: View {
    public let platform: Platform
    @EnvironmentObject private var loginSession: LoginSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WebLoginModel()
    @State private var message: String?
    @State private var isAutoSaving = false
    @State private var showTutorial = true
    // 自动检测定时器
    @State private var autoDetectCancellable: Cancellable?

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

    /// 该平台 WebView 需使用的自定义 User-Agent（PC 环境，避免被识别为移动端）
    private var customUA: String {
        switch platform {
        case .quark:
            // 夸克 PC 客户端 UA（与 YunX QuarkConstants.USER_AGENT 一致）
            return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 QuarkPC/6.0.8.649"
        default:
            // 普通 PC Chrome UA
            return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
        }
    }

    public var body: some View {
        NavigationStack {
            CookieWebView(url: targetURL, model: model, customUA: customUA)
                .navigationTitle(platform.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            autoDetectCancellable?.cancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isAutoSaving ? "检测中…" : "完成登录") {
                            completeLogin()
                        }
                        .disabled(isAutoSaving)
                    }
                }
                .onAppear {
                    startAutoDetect()
                }
                .onDisappear {
                    autoDetectCancellable?.cancel()
                }
                .alert(isPresented: Binding<Bool>(get: { message != nil },
                                                  set: { if !$0 { message = nil } })) {
                    Alert(title: Text("提示"),
                          message: Text(message ?? ""),
                          dismissButton: .default(Text("好")))
                }
                .alert("登录教程", isPresented: $showTutorial) {
                    Button("知道了") { }
                } message: {
                    Text(tutorialText)
                }
        }
    }

    private var tutorialText: String {
        switch platform {
        case .quark:
            return "1. 在下方网页中登录夸克账号\n2. 登录完成后将自动检测登录态并保存 Cookie\n3. 若未自动登录，点右上角「完成登录」手动保存\n4. 或在登录页用「手动输入」粘贴 Cookie（需含 __pus= 与 __puus=）\n5. Cookie 约 30 天有效，失效后需重新登录"
        case .baidu:
            return "1. 在下方网页中登录百度网盘（建议扫码）\n2. 登录完成后将自动检测登录态并保存 Cookie（需含 BDUSS）\n3. 若未自动登录，点右上角「完成登录」手动保存"
        case .pan123:
            return "1. 在下方网页中登录 123 云盘\n2. 登录完成后将自动读取 localStorage 中的 authorToken 并保存\n3. 若未自动读取，点右上角「完成登录」手动保存"
        case .xunlei:
            return ""
        }
    }

    // MARK: - 自动登录检测（移植自 YunX rememberWebLoginAutoDetect）

    /// 每 1.5 秒轮询一次网页登录凭证；检测到有效凭证后自动保存并关闭页面。
    private func startAutoDetect() {
        autoDetectCancellable?.cancel()
        let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
        autoDetectCancellable = timer.sink { _ in
            guard !isAutoSaving else { return }
            sampleAndValidate()
        }
    }

    private func sampleAndValidate() {
        switch platform {
        case .quark, .baidu:
            let domain = (platform == .quark) ? "pan.quark.cn" : "pan.baidu.com"
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                DispatchQueue.main.async {
                    let filtered = cookies.filter { $0.domain.contains(domain) }
                    let cookieString = filtered
                        .map { "\($0.name)=\($0.value)" }
                        .joined(separator: "; ")
                    guard !cookieString.isEmpty else { return }
                    // 廉价预检：凭证关键字段是否齐全（不发网络请求）
                    guard isPlausibleCookie(cookieString) else { return }
                    // 校验通过，自动保存
                    autoSave(cookie: cookieString, token: nil)
                }
            }
        case .pan123:
            model.webView.evaluateJavaScript("localStorage.getItem('authorToken')") { result, _ in
                DispatchQueue.main.async {
                    if let token = result as? String, !token.isEmpty {
                        autoSave(cookie: nil, token: token)
                    }
                }
            }
        case .xunlei:
            break
        }
    }

    /// 廉价预检：凭证关键字段是否齐全（绝不发网络请求）
    private func isPlausibleCookie(_ cookie: String) -> Bool {
        switch platform {
        case .quark:
            return cookie.contains("__pus=") && cookie.contains("__puus=")
        case .baidu:
            return cookie.contains("BDUSS=")
        default:
            return false
        }
    }

    private func autoSave(cookie: String?, token: String?) {
        isAutoSaving = true
        loginSession.setAuth(PlatformAuth(cookie: cookie, token: token, extra: [:]),
                             for: platform)
        autoDetectCancellable?.cancel()
        isAutoSaving = false
        dismiss()
    }

    // MARK: - 手动完成登录（兜底）

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
                    self.autoDetectCancellable?.cancel()
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
                    self.autoDetectCancellable?.cancel()
                    dismiss()
                } else {
                    message = "未读取到 authorToken，请确认已在 123 云盘网页中完成登录。"
                }
            }
        }
    }
}

// MARK: - 手动输入 Cookie/Token 兜底

public struct ManualCookieSheet: View {
    public let platform: Platform
    @EnvironmentObject private var loginSession: LoginSession
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var isSaving = false
    @State private var message: String?

    public init(platform: Platform) {
        self.platform = platform
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(guideText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $inputText)
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    GlassButton(isSaving ? "保存中…" : "保存", systemImage: "checkmark.circle") {
                        save()
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
                .padding()
            }
            .background(LiquidGlassBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("手动输入\(platform == .pan123 ? "Token" : "Cookie")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert(isPresented: Binding<Bool>(get: { message != nil },
                                              set: { if !$0 { message = nil } })) {
                Alert(title: Text("提示"), message: Text(message ?? ""),
                      dismissButton: .default(Text("好")))
            }
        }
    }

    private var guideText: String {
        switch platform {
        case .quark:
            return "从网页登录态复制完整的 Cookie（需包含 __pus= 与 __puus=），格式如：__pus=xxx; __puus=yyy; ..."
        case .baidu:
            return "从网页登录态复制完整的 Cookie（需包含 BDUSS=），格式如：BDUSS=xxx; ..."
        case .pan123:
            return "从 123 云盘网页 localStorage 中复制 authorToken（JWT），直接粘贴即可。"
        case .xunlei:
            return ""
        }
    }

    private func save() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true

        // 廉价预检
        switch platform {
        case .quark:
            guard trimmed.contains("__pus=") && trimmed.contains("__puus=") else {
                message = "Cookie 无效，请检查是否包含 __pus= 与 __puus="
                isSaving = false
                return
            }
            loginSession.setAuth(PlatformAuth(cookie: trimmed, token: nil, extra: [:]), for: .quark)
        case .baidu:
            guard trimmed.contains("BDUSS=") else {
                message = "Cookie 无效，请检查是否包含 BDUSS="
                isSaving = false
                return
            }
            loginSession.setAuth(PlatformAuth(cookie: trimmed, token: nil, extra: [:]), for: .baidu)
        case .pan123:
            loginSession.setAuth(PlatformAuth(cookie: nil, token: trimmed, extra: [:]), for: .pan123)
        case .xunlei:
            break
        }

        isSaving = false
        dismiss()
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
    public let customUA: String

    public init(url: URL, model: WebLoginModel, customUA: String) {
        self.url = url
        self.model = model
        self.customUA = customUA
    }

    public func makeUIView(context: Context) -> WKWebView {
        // 必须在 load 之前设置 customUserAgent
        model.webView.customUserAgent = customUA
        model.webView.load(URLRequest(url: url))
        return model.webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
