//
//  YxiOSError.swift
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
//  All core-layer errors are thrown as YxiOSError with a Chinese description.
//

import Foundation

public enum YxiOSError: LocalizedError, Equatable {
    /// 直接给出的中文错误信息。
    case message(String)
    /// 服务端返回错误码时的透传（message + code）。
    case server(message: String, code: Int?)

    public var errorDescription: String? {
        switch self {
        case .message(let m):
            return m
        case .server(let m, let code):
            if let code = code {
                return "\(m)（code=\(code)）"
            }
            return m
        }
    }

    public static func wrap(_ error: Error) -> YxiOSError {
        if let e = error as? YxiOSError {
            return e
        }
        return .message(error.localizedDescription)
    }
}
