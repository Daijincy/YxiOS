//
//  PlatformClient.swift
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
//  Public protocol frozen per API-CONTRACT §3.
//

import Foundation

public protocol PlatformClient: Sendable {
    var platform: Platform { get }
    /// 该平台是否必须登录才能解析/取直链
    var requiresLogin: Bool { get }
    /// 解析分享链接 → 返回根目录文件列表（尽量返回带直链的文件；目录项 downloadURL 为 nil）
    func resolveShare(_ info: ShareInfo) async throws -> [FileEntry]
    /// 目录展开：给定目录项 id，返回子文件列表
    func listChildren(_ dirID: String, of info: ShareInfo) async throws -> [FileEntry]
    /// 获取单个文件的直链（若 FileEntry.downloadURL 已有值可直接返回）
    func getDirectURL(for file: FileEntry, share: ShareInfo) async throws -> URL
    /// 平台标识（登录状态变更后用）
    func setAuth(_ auth: PlatformAuth?)
}

/// 各平台登录态（由界面层经 LoginSession 写入，核心层读取）
public struct PlatformAuth: Codable, Equatable, Sendable {
    public var cookie: String?          // quark/baidu 用（"k1=v1; k2=v2"）
    public var token: String?           // pan123 JWT / xunlei 用
    public var extra: [String: String]  // 其他字段（uid 等）
    public init(cookie: String?, token: String?, extra: [String: String]) {
        self.cookie = cookie
        self.token = token
        self.extra = extra
    }
}

public enum PlatformRegistry {
    public static func client(for platform: Platform) -> PlatformClient {
        switch platform {
        case .quark: return QuarkClient.shared
        case .baidu: return BaiduClient.shared
        case .pan123: return Pan123Client.shared
        case .xunlei: return XunleiClient.shared
        }
    }
}

// MARK: - Internal helpers (not part of the frozen contract)

/// 取直链时附带的下载请求头（UA / Referer / Cookie），供下载引擎携带。
struct ResolvedDirectURL {
    let url: URL
    let headers: [String: String]
}

/// 核心层内部约定：每个客户端除契约的 getDirectURL 外，还能给出直链+下载头。
protocol DirectURLProvider: PlatformClient {
    func directDownloadURL(for file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL
}

/// 线程安全的可变值容器（登录态、缓存）。@unchecked Sendable 配 NSLock。final class 不会被继承。final
final class Protected<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) { self.value = value }

    func read() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func write(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func mutate(_ fn: (inout T) -> Void) {
        lock.lock()
        fn(&value)
        lock.unlock()
    }
}
