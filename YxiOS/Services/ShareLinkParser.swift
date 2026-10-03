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
//  Share-link detection. 统一使用同一套规则做「平台识别 + shareID 提取」，
//  避免平台判断与 ID 提取用两套不一致正则导致识别失败。
//

import Foundation

public enum ShareLinkParser {

    /// 平台识别 + shareID 提取 一体的规则表（按优先级顺序匹配）。
    /// - quark:   pan.quark.cn/s/<key>
    /// - baidu:   pan.baidu.com/s/1<surl>  (shareID 需去掉开头的 "1")
    /// - pan123:  三种形态，key 允许带或不带连字符
    /// - xunlei:  pan.xunlei.com/s/<key>
    private static let rules: [(platform: Platform, pattern: String, stripLeading1: Bool)] = [
        (.quark,  #"pan\.quark\.cn/s/([A-Za-z0-9]+)"#, false),
        (.baidu,  #"pan\.baidu\.com/s/(1[A-Za-z0-9_-]+)"#, true),
        (.pan123, #"123(?:865|pan)\.(?:com|cn)/s/([A-Za-z0-9]+(?:-[A-Za-z0-9]+)?)"#, false),
        (.pan123, #"share\.123pan\.cn/123pan/([A-Za-z0-9]+(?:-[A-Za-z0-9]+)?)"#, false),
        (.pan123, #"api/srr\?sk=([A-Za-z0-9]+(?:-[A-Za-z0-9]+)?)"#, false),
        (.xunlei, #"pan\.xunlei\.com/s/([A-Za-z0-9_-]+)"#, false),
    ]

    /// 输入任意文本，识别出第一个网盘分享链接并解析；识别失败返回 nil。
    public static func parse(_ text: String) -> ShareInfo? {
        guard let rawURL = firstURL(in: text) else { return nil }
        guard let (platform, shareID) = detect(in: rawURL), !shareID.isEmpty else { return nil }

        // 提取码：URL ?pwd= 优先，其次文案中的「提取码/访问码/密码：xxxx」
        var pwd = match("[?&]pwd=([A-Za-z0-9]+)", in: rawURL)
        if pwd == nil {
            pwd = match("(?:提取码|访问码|密码)[：:]\\s*([A-Za-z0-9]{4,8})", in: text)
        }

        return ShareInfo(platform: platform, shareID: shareID, password: pwd, rawURL: rawURL)
    }

    /// 从一段 URL 中识别平台。
    public static func detectPlatform(from urlString: String) -> Platform? {
        detect(in: urlString).map { $0.0 }
    }

    // MARK: - Detection

    /// 用统一规则表匹配，返回 (平台, shareID)。baidu 自动去掉 surl 开头的 "1"。
    private static func detect(in urlString: String) -> (Platform, String)? {
        for rule in rules {
            if let id = match(rule.pattern, in: urlString) {
                var sid = id
                if rule.stripLeading1, sid.hasPrefix("1") { sid.removeFirst() }
                return (rule.platform, sid)
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// 抓第一个 URL，并 trim 结尾标点。
    private static func firstURL(in text: String) -> String? {
        guard var url = match("https?://[^\\s]+", in: text) else { return nil }
        // 去掉结尾标点：。，,；;)] } " '
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
