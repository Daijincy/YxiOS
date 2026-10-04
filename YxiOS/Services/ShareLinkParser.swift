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
//  链接刮削：从任意文本（含文案/换行/中文/emoji/无空格/多链接）中
//  可靠提取第一个网盘 URL。
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
    /// 支持从整段分享文案（含换行/中文/emoji/无空格）中刮削出链接。
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

    // MARK: - 链接刮削

    /// 从任意文本中提取第一个 http(s) URL。
    /// 处理场景：
    /// - URL 前后有中文文案/emoji/换行
    /// - URL 后紧跟中文（无空格），如 https://pan.quark.cn/s/xxx提取码：1234
    /// - URL 被 markdown 包裹，如 [链接](https://...)
    /// - URL 末尾有标点符号
    /// - 文本中有多个 URL，取第一个
    private static func firstURL(in text: String) -> String? {
        // 注意：必须有捕获组，否则 match() 会因 numberOfRanges < 2 返回 nil
        guard var url = match("(https?://[^\\s]+)", in: text) else { return nil }
        // 去掉结尾标点：。，,；;)] } " ' 以及全角括号
        while let last = url.last, "。，,；;)]}\"'）】》".contains(last) {
            url.removeLast()
        }
        // 如果 URL 末尾紧跟中文字符（无空格），截断到最后一个合法 URL 字符
        // 合法 URL 字符：字母数字 + -._~:/?#[]@!$&'()*+,;=%
        let validChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
        if let lastValidIndex = url.lastIndex(where: { $0.unicodeScalars.allSatisfy({ validChars.contains($0) }) }) {
            url = String(url[...lastValidIndex])
        }
        return url.isEmpty ? nil : url
    }

    // MARK: - Helpers

    /// 用 NSRegularExpression 取第一个捕获组（IGNORE CASE）。
    /// 注意：pattern 必须包含至少一个捕获组 (...)，否则返回 nil。
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
