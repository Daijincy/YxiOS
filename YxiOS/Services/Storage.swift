//
//  Storage.swift
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
//  Filesystem layout + task persistence — frozen per API-CONTRACT §6.
//

import Foundation

public enum Storage {

    public static var documentsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    public static var downloadsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var tasksFile: URL {
        return downloadsDirectory.appendingPathComponent("tasks.json")
    }

    public static func saveTasks(_ tasks: [DownloadTask]) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: tasksFile, options: .atomic)
    }

    public static func loadTasks() -> [DownloadTask] {
        guard let data = try? Data(contentsOf: tasksFile),
              let tasks = try? JSONDecoder().decode([DownloadTask].self, from: data) else {
            return []
        }
        return tasks
    }

    /// 单个任务的分片目录：Documents/Downloads/<uuid>/
    public static func taskDirectory(for task: DownloadTask) -> URL {
        let dir = downloadsDirectory.appendingPathComponent(task.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 用户设置（UserDefaults）

    private static let defaults = UserDefaults.standard

    /// 下载线程数（分片数=并发数），默认 32
    public static var downloadThreads: Int {
        get {
            let v = defaults.integer(forKey: "downloadThreads")
            return v > 0 ? v : 32
        }
        set { defaults.set(max(1, min(512, newValue)), forKey: "downloadThreads") }
    }
}
