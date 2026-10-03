//
//  Crypto.swift
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
//  Pure-Swift MD5 / CRC32 / Base64 helpers. No CommonCrypto / zlib dependency,
//  to keep the iOS build dependency-free and lower compile risk.
//

import Foundation

/// 标准 CRC-32/IEEE 查表实现（等价 zlib.crc32，输出 8 位小写十六进制）。
public enum CRC32 {

    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            t[i] = c
        }
        return t
    }()

    public static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            let idx = Int((crc ^ UInt32(b)) & 0xFF)
            crc = (crc >> 8) ^ table[idx]
        }
        return crc ^ 0xFFFFFFFF
    }

    /// 对字符串（UTF-8）计算 CRC32，返回 8 位小写十六进制。
    public static func hex(_ string: String) -> String {
        let v = checksum(Array(string.utf8))
        return String(format: "%08x", v)
    }
}

/// 纯 Swift MD5（RFC 1321）。仅用于内部签名/设备指纹，避免依赖 CommonCrypto。
public enum MD5 {

    public static func hex(_ string: String) -> String {
        return md5(Array(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func md5(_ data: [UInt8]) -> [UInt8] {
        let s: [UInt32] = [
            7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
            5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
            4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
            6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
        ]
        // 按 RFC1321 公式生成 K 表：K[i] = floor(abs(sin(i+1)) * 2^32)
        let k: [UInt32] = (0..<64).map { i -> UInt32 in
            let f = Foundation.sin(Double(i + 1))
            let v = f < 0 ? -f : f
            return UInt32(v * 4294967296.0)
        }

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xefcdab89
        var h2: UInt32 = 0x98badcfe
        var h3: UInt32 = 0x10325476

        var msg = data
        let bitLength = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 {
            msg.append(0)
        }
        for i in 0..<8 {
            msg.append(UInt8((bitLength >> (UInt64(i) * 8)) & 0xFF))
        }

        var offset = 0
        while offset < msg.count {
            let block = Array(msg[offset..<(offset + 64)])
            var M = [UInt32](repeating: 0, count: 16)
            for j in 0..<16 {
                let b0 = UInt32(block[j * 4])
                let b1 = UInt32(block[j * 4 + 1])
                let b2 = UInt32(block[j * 4 + 2])
                let b3 = UInt32(block[j * 4 + 3])
                M[j] = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
            }
            var a = h0, b = h1, c = h2, d = h3
            for i in 0..<64 {
                var f: UInt32 = 0
                var g: Int = 0
                switch i / 16 {
                case 0:
                    f = (b & c) | ((~b) & d)
                    g = i
                case 1:
                    f = (d & b) | ((~d) & c)
                    g = (5 * i + 1) % 16
                case 2:
                    f = b ^ c ^ d
                    g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | (~d))
                    g = (7 * i) % 16
                }
                let temp = d
                d = c
                c = b
                let rot = a &+ f &+ k[i] &+ M[g]
                let shift = Int(s[i])
                b = b &+ ((rot << shift) | (rot >> (32 - shift)))
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            offset += 64
        }

        var out = [UInt8]()
        for h in [h0, h1, h2, h3] {
            out.append(UInt8(h & 0xFF))
            out.append(UInt8((h >> 8) & 0xFF))
            out.append(UInt8((h >> 16) & 0xFF))
            out.append(UInt8((h >> 24) & 0xFF))
        }
        return out
    }
}

/// Base64 / Base64URL 解码工具（123 云盘直链解码用）。
public enum Base64Tool {

    /// 标准 Base64 解码整串（自动补 padding）。
    public static func decodeString(_ s: String) -> String? {
        var src = s.replacingOccurrences(of: "\n", with: "")
        src = src.replacingOccurrences(of: " ", with: "")
        var pad = src
        while pad.count % 4 != 0 { pad += "=" }
        guard let data = Data(base64Encoded: pad, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Base64URL 解码（- → +，_ → /，自动补 padding）。
    public static func decodeURL(_ s: String) -> String? {
        var src = s.replacingOccurrences(of: "-", with: "+")
        src = src.replacingOccurrences(of: "_", with: "/")
        return decodeString(src)
    }
}
