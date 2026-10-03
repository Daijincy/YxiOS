//
//  SharedModels.swift
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
//  Core data models — signatures frozen per API-CONTRACT §1.
//

import Foundation

public enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
    case quark, baidu, pan123, xunlei
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .quark: return "夸克网盘"
        case .baidu: return "百度网盘"
        case .pan123: return "123云盘"
        case .xunlei: return "迅雷云盘"
        }
    }
}

public struct ShareInfo: Codable, Equatable, Sendable {
    public let platform: Platform
    public let shareID: String      // 分享链接中的资源标识（pwd 之前的 key）
    public let password: String?    // 提取码，可能为 nil
    public let rawURL: String       // 用户粘贴的原始链接
    public init(platform: Platform, shareID: String, password: String?, rawURL: String) {
        self.platform = platform
        self.shareID = shareID
        self.password = password
        self.rawURL = rawURL
    }
}

public struct FileEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String          // 平台文件标识（目录/文件通用）
    public let name: String
    public let size: Int64         // 字节；目录为 0
    public let isDirectory: Bool
    public let parentID: String?   // 目录层级用；根层为 nil
    public let downloadURL: String? // 直链（可能为 nil，需 getDirectURL 获取）
    public init(id: String, name: String, size: Int64, isDirectory: Bool,
                parentID: String?, downloadURL: String?) {
        self.id = id
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.parentID = parentID
        self.downloadURL = downloadURL
    }
}

public enum TaskStatus: String, Codable, Sendable {
    case queued, downloading, paused, completed, failed
}

public struct DownloadTask: Identifiable, Codable, Sendable {
    public let id: UUID
    public let platform: Platform
    public let fileName: String
    public let fileID: String
    public var status: TaskStatus
    public var progress: Double          // 0.0...1.0
    public var downloadedBytes: Int64
    public var totalBytes: Int64
    public var errorMessage: String?
    public let createdAt: Date
    public var localPath: String?        // 完成后 Documents/Downloads/ 下的相对路径
    public init(id: UUID, platform: Platform, fileName: String, fileID: String,
                status: TaskStatus, progress: Double, downloadedBytes: Int64,
                totalBytes: Int64, errorMessage: String?, createdAt: Date, localPath: String?) {
        self.id = id
        self.platform = platform
        self.fileName = fileName
        self.fileID = fileID
        self.status = status
        self.progress = progress
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.localPath = localPath
    }
}
