//
//  HTTP.swift
//  YxiOS (云析 iOS 移植版)
//
//  移植自 YunX https://github.com/CYQawa/YunX
//  Copyright (C) 2026 CYQawa
//
//  Minimal async HTTP helper + URL/form encoding helpers. Internal use only.
//

import Foundation

/// 网络响应包装。
struct HTTPResponse {
    let data: Data
    let response: HTTPURLResponse

    var statusCode: Int { response.statusCode }
    var headers: [String: String] {
        var out = [String: String]()
        for (k, v) in response.allHeaderFields {
            if let ks = k as? String, let vs = v as? String {
                out[ks] = vs
            }
        }
        return out
    }

    /// 从所有 Set-Cookie 里抽取指定名字的值（如 __pugs）。
    func cookieValue(named name: String) -> String? {
        let setCookies = response.allHeaderFields.filter {
            ($0.key as? String)?.lowercased() == "set-cookie"
        }.compactMap { $0.value as? String }
        for sc in setCookies {
            // 每条 Set-Cookie 形如 "name=value; Path=/; ..."
            for part in sc.components(separatedBy: ",") {
                let items = part.components(separatedBy: ";")
                if let first = items.first {
                    let kv = first.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
                    if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == name {
                        return kv[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        return nil
    }
}

enum HTTP {

    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 300
        // 不自动管理 Cookie，各平台手动塞 Cookie 头（见 platform-spec §8.2）
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        // ★ 关键：解除 iOS 默认每主机 4 连接限制，否则多线程下载被硬钳到 4 并发
        cfg.httpMaximumConnectionsPerHost = 512
        return URLSession(configuration: cfg)
    }()

    /// 发起请求并返回 (Data, HTTPURLResponse)。网络错误抛 YxiOSError。
    static func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse else {
                throw YxiOSError.message("无效的网络响应")
            }
            return HTTPResponse(data: data, response: http)
        } catch let e as YxiOSError {
            throw e
        } catch {
            throw YxiOSError.message("网络请求失败：\(error.localizedDescription)")
        }
    }

    /// 流式下载：把 URLSession 的逐字节 AsyncBytes（Element == UInt8）缓冲成
    /// 约 64KB 一块的 Data 序列，便于直接 FileHandle.write(contentsOf:)。
    /// 返回 (Data chunk 流, HTTPURLResponse)。
    static func dataChunks(for request: URLRequest, chunkSize: Int = 64 * 1024)
        async throws -> (AsyncThrowingStream<Data, Error>, HTTPURLResponse) {
        let (bytes, resp) = try await session.bytes(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw YxiOSError.message("无效的网络响应")
        }
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let producer = Task {
                var buffer = Data()
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
        return (stream, http)
    }
}

/// URL 拼接 / 表单编码工具。
enum URLEncoder {

    /// application/x-www-form-urlencoded 编码（空格 → +）。
    static func form(_ items: [String: String?]) -> String {
        var parts = [String]()
        for (k, v) in items {
            let value = v ?? ""
            parts.append("\(escape(k))=\(escape(value))")
        }
        return parts.joined(separator: "&")
    }

    /// 宽松的 percent-encode（用于 query 段，空格 → %20）。
    static func query(items: [String: String?]) -> String {
        var parts = [String]()
        for (k, v) in items {
            guard let v = v else { continue }
            parts.append("\(percent(k))=\(percent(v))")
        }
        return parts.joined(separator: "&")
    }

    private static func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func percent(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
