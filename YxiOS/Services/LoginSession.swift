//
//  LoginSession.swift
//  YxiOS (云析 iOS 移植版)
//
//  移植自 YunX https://github.com/CYQawa/YunX
//  Copyright (C) 2026 CYQawa
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Login session store — frozen per API-CONTRACT §4.
//

import Foundation
import Combine

@MainActor
public final class LoginSession: ObservableObject {

    public static let shared = LoginSession()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    /// 界面层 WebView 登录成功后调用，会持久化到 UserDefaults，
    /// 并同步下发给 PlatformRegistry 对应客户端，保证解析/取链使用最新登录态。
    public func setAuth(_ auth: PlatformAuth, for platform: Platform) {
        if let data = try? encoder.encode(auth) {
            defaults.set(data, forKey: key(for: platform))
        }
        PlatformRegistry.client(for: platform).setAuth(auth)
    }

    public func auth(for platform: Platform) -> PlatformAuth? {
        guard let data = defaults.data(forKey: key(for: platform)),
              let auth = try? decoder.decode(PlatformAuth.self, from: data) else {
            return nil
        }
        return auth
    }

    public func clearAuth(for platform: Platform) {
        defaults.removeObject(forKey: key(for: platform))
        PlatformRegistry.client(for: platform).setAuth(nil)
    }

    /// 启动时把持久化登录态下发到各客户端（由 App 入口调用一次即可）。
    public func bootstrap() {
        for p in Platform.allCases {
            if let a = auth(for: p) {
                PlatformRegistry.client(for: p).setAuth(a)
            }
        }
    }

    private func key(for platform: Platform) -> String {
        return "yx_auth_\(platform.rawValue)"
    }
}
