//
//  ShareLinkParser.swift
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
//  Share-link detection — regexes copied verbatim from platform-spec §1.
//

import Foundation

public enum ShareLinkParser {

    /// 输入任意文本，识别出第一个网盘分享链接并解析；识别失败返回 nil。
    public static func parse(_ text: String) -> ShareInfo? {
        guard let rawURL = firstURL(in: text) else { return nil }
        guard let platform = detectPlatform(from: rawURL) else { return nil }

        let shareID: String?
        switch platform {
        case .quark:
            shareID = match("pan\\.quark\\.cn/s/([A-Za-z0-9]+)", in: rawURL)
        case .baidu:
            if var s = match("pan\\.baidu\\.com/s/(1[A-Za-z0-9_-]+)", in: rawURL) {
                if s.hasPrefix("1") { s.removeFirst() }
                shareID = s
            } else {
                shareID = nil
            }
        case .pan123:
            shareID = match("123(?:865|pan)\\.(?:com|cn)/s/([A-Za-z0-9]+-[A-Za-z0-9]+)", in: rawURL)
                ?? match("share\\.123pan\\.cn/123pan/([A-Za-z0-9-]+)", in: rawURL)
                ?? match("api/srr\\?sk=([A-Za-z0-9-]+)", in: rawURL)
        case .xunlei:
            shareID = match("pan\\.xunlei\\.com/s/([A-Za-z0-9_-]+)", in: rawURL)
        }

        guard let sid = shareID, !sid.isEmpty else { return nil }

        // 提取码：URL ?pwd= 优先，其次文案中的「提取码/访问码/密码：xxxx」
        var pwd = match("[?&]pwd=([A-Za-z0-9]+)", in: rawURL)
        if pwd == nil {
            pwd = match("(?:提取码|访问码|密码)[：:]\\s*([A-Za-z0-9]{4,8})", in: text)
        }

        return ShareInfo(platform: platform, shareID: sid, password: pwd, rawURL: rawURL)
    }

    /// 从一段 URL 中识别平台（按夸克/百度/123/迅雷顺序匹配）。
    public static func detectPlatform(from urlString: String) -> Platform? {
        if match("pan\\.quark\\.cn/s/", in: urlString) != nil { return .quark }
        if match("pan\\.baidu\\.com/s/", in: urlString) != nil { return .baidu }
        if match("123(?:865|pan)\\.(?:com|cn)/s/", in: urlString) != nil
            || match("share\\.123pan\\.cn/123pan/", in: urlString) != nil
            || match("api/srr\\?sk=", in: urlString) != nil {
            return .pan123
        }
        if match("pan\\.xunlei\\.com/s/", in: urlString) != nil { return .xunlei }
        return nil
    }

    // MARK: - Helpers

    /// 抓第一个 URL，并 trim 结尾标点。
    private static func firstURL(in text: String) -> String? {
        guard var url = match("https?://[^\\s]+", in: text) else { return nil }
        // 去掉结尾标点：。，,；;) ] } " '
        while let last = url.last, "。，,；;)]}\"'".contains(last) {
            url.removeLast()
        }
        return url
    }

    /// 用 NSRegularExpression 取第一个捕获组（IGNORE CASE）。
    private static func match(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: range),
              result.numberOfRanges >= 2,
              let r = Range(result.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }
}
