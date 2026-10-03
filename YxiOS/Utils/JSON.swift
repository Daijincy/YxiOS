//
//  JSON.swift
//  YxiOS (云析 iOS 移植版)
//
//  移植自 YunX https://github.com/CYQawa/YunX
//  Copyright (C) 2026 CYQawa
//
//  Tolerant JSON accessor (mirrors Kotlin JSONObject.optXxx semantics):
//  tolerates missing keys, and number/string dual forms (e.g. baidu isdir == "1").
//

import Foundation

/// 轻量、宽容的 JSON 包装。内部使用，不对外暴露。
final class JSON {

    let raw: Any

    init(_ raw: Any) {
        self.raw = raw
    }

    /// 解析 Data 为 JSON；失败返回 nil。
    static func parse(_ data: Data) -> JSON? {
        guard !data.isEmpty else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return JSON(obj)
    }

    var dictionary: [String: Any]? {
        return raw as? [String: Any]
    }

    var array: [JSON]? {
        guard let arr = raw as? [Any] else { return nil }
        return arr.map { JSON($0) }
    }

    subscript(_ key: String) -> JSON? {
        guard let dict = dictionary, let v = dict[key] else { return nil }
        return JSON(v)
    }

    /// 字符串形态：兼容数字/布尔转字符串。
    var string: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber {
            // 避免布尔被当成 1/0 时误判；这里仅做纯数值转换
            if CFBooleanGetTypeID() == CFGetTypeID(n) {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        }
        return nil
    }

    /// 整数形态：兼容字符串 "123" / 数字 123 / 浮点 123.0。
    var int64: Int64? {
        if let s = raw as? String {
            return Int64(s)
        }
        if let n = raw as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(n) {
                return n.boolValue ? 1 : 0
            }
            return n.int64Value
        }
        return nil
    }

    var double: Double? {
        if let s = raw as? String {
            return Double(s)
        }
        if let n = raw as? NSNumber {
            return n.doubleValue
        }
        return nil
    }

    var bool: Bool? {
        if let b = raw as? Bool { return b }
        if let s = raw as? String {
            if s == "1" || s.lowercased() == "true" { return true }
            if s == "0" || s.lowercased() == "false" { return false }
            return nil
        }
        if let n = raw as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(n) {
                return n.boolValue
            }
            return n.intValue != 0
        }
        return nil
    }
}
