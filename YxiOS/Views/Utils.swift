//
//  Utils.swift
//  YxiOS
//
//  YxiOS — iOS port of YunX (https://github.com/CYQawa/YunX)
//  Copyright (C) 2026 CYQawa
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Small UI helpers (formatting only; core storage/network lives in Services/).
//

import Foundation

public enum Formatters {
    /// Human readable byte count: B / KB / MB / GB.
    public static func fileSize(_ bytes: Int64) -> String {
        if bytes <= 0 { return "—" }
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }

    /// Progress pair, e.g. "12.3 MB / 1.0 GB".
    public static func progressText(downloaded: Int64, total: Int64) -> String {
        if total <= 0 { return fileSize(downloaded) }
        return "\(fileSize(downloaded)) / \(fileSize(total))"
    }
}
