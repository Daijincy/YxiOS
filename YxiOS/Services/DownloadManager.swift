//
//  DownloadManager.swift
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
//  Multi-chunk, resumable download engine — contract §5 + spec §7.
//

import Foundation
import Combine

@MainActor
public final class DownloadManager: ObservableObject {

    public static let shared = DownloadManager()

    @Published public private(set) var tasks: [DownloadTask] = []
    /// 下载成功启动时的文件名提示（用于 UI 弹出"已开始下载"并跳转）
    @Published public var downloadStartedFileName: String?

    private var runtimes: [UUID: Runtime] = [:]
    private let fm = FileManager.default
    /// 实时下载速度（字节/秒），非持久化，UI 显示用
    private var speeds: [UUID: Double] = [:]

    /// 获取指定任务的实时下载速度（字节/秒）
    public func speed(for taskID: UUID) -> Double { speeds[taskID] ?? 0 }

    /// 格式化速度为人类可读字符串（如 "1.2 MB/s"）
    public static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond <= 0 { return "0 B/s" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSecond
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    /// 格式化剩余时间（如 "1分23秒"、"2小时5分"）
    public static func formatRemaining(_ seconds: Double) -> String {
        if seconds <= 0 || seconds.isInfinite { return "计算中…" }
        if seconds < 60 { return String(format: "%.0f秒", seconds) }
        if seconds < 3600 {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return "\(m)分\(s)秒"
        }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return "\(h)小时\(m)分"
    }

    private init() {
        tasks = Storage.loadTasks()
        // 上次未完成的任务回退到暂停态，等待用户手动恢复
        for i in 0..<tasks.count {
            if tasks[i].status == .downloading || tasks[i].status == .queued {
                tasks[i].status = .paused
                tasks[i].errorMessage = nil
            }
        }
        Storage.saveTasks(tasks)
    }

    // MARK: - Public API (contract §5)

    /// 新增下载任务（file 的 downloadURL 为 nil 时，内部用 platform client 取直链）
    public func addDownload(platform: Platform, share: ShareInfo, file: FileEntry) async {
        let task = DownloadTask(
            id: UUID(), platform: platform, fileName: file.name, fileID: file.id,
            status: .queued, progress: 0, downloadedBytes: 0, totalBytes: 0,
            errorMessage: nil, createdAt: Date(), localPath: nil
        )
        tasks.append(task)
        Storage.saveTasks(tasks)

        do {
            let client = PlatformRegistry.client(for: platform)
            let ctx: ResolvedDirectURL
            if let provider = client as? DirectURLProvider {
                ctx = try await provider.directDownloadURL(for: file, share: share)
            } else {
                let u = try await client.getDirectURL(for: file, share: share)
                ctx = ResolvedDirectURL(url: u, headers: [:])
            }

            let rt = Runtime(url: ctx.url, headers: ctx.headers, dir: Storage.taskDirectory(for: task))
            runtimes[task.id] = rt

            let total = try await probeTotal(url: ctx.url, headers: ctx.headers)
            rt.total = total
            updateTask(task.id) { $0.totalBytes = total }

            setupChunks(rt)
            markDownloading(task.id)
            launchChunks(task.id)
            // 下载成功启动，通知 UI 弹出提示并跳转
            downloadStartedFileName = file.name
        } catch {
            let msg = (error as? YxiOSError)?.errorDescription ?? error.localizedDescription
            updateTask(task.id) {
                $0.status = .failed
                $0.errorMessage = msg
            }
            Storage.saveTasks(tasks)
        }
    }

    public func pause(_ id: UUID) {
        guard let rt = runtimes[id] else { return }
        rt.paused = true
        for w in rt.workers { w.cancel() }
        rt.workers.removeAll()
        updateTask(id) { $0.status = .paused }
        Storage.saveTasks(tasks)
    }

    public func resume(_ id: UUID) {
        guard let rt = runtimes[id] else { return }
        rt.paused = false
        rt.cancelled = false
        rt.settled = 0
        rt.nextChunkIndex = 0  // 重置，从头扫描未完成分片
        rt.downloadedBytes = onDiskBytes(rt)
        updateTask(id) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
        launchChunks(id)
        Storage.saveTasks(tasks)
    }

    public func remove(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let rt = runtimes[id] {
            rt.cancelled = true
            for w in rt.workers { w.cancel() }
            rt.workers.removeAll()
        }
        let dir = Storage.downloadsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fm.removeItem(at: dir)
        runtimes[id] = nil
        tasks.remove(at: idx)
        Storage.saveTasks(tasks)
    }

    public func retry(_ id: UUID) {
        guard let rt = runtimes[id] else { return }
        rt.cancelled = false
        rt.paused = false
        rt.taskRetries = 0
        rt.settled = 0
        rt.lastError = nil
        rt.downloadedBytes = onDiskBytes(rt)
        updateTask(id) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
        launchChunks(id)
        Storage.saveTasks(tasks)
    }

    public func task(with id: UUID) -> DownloadTask? {
        return tasks.first(where: { $0.id == id })
    }

    public func fileURL(for task: DownloadTask) -> URL? {
        guard let rel = task.localPath else { return nil }
        return Storage.downloadsDirectory.appendingPathComponent(rel)
    }

    // MARK: - Runtime

    private final class Runtime {
        let url: URL
        let headers: [String: String]
        let dir: URL
        var total: Int64 = -1
        var partCount: Int = 1
        var ranges: [(start: Int64, end: Int64)] = []
        var done: [Bool] = []
        var settled: Int = 0
        var downloadedBytes: Int64 = 0
        var workers: [Task<Void, Never>] = []
        var paused = false
        var cancelled = false
        var rangeIgnored = 0
        var taskRetries = 0
        var lastError: String?
        /// 当前活跃分片数（用于并发控制）
        var activeCount: Int = 0
        /// 下一个待启动的分片索引
        var nextChunkIndex: Int = 0
        /// 上次进度 UI 更新时间戳（节流用）
        var lastProgressUpdate: TimeInterval = 0
        /// 速度统计：上次计算速度时的时间戳和已下载字节数
        var lastSpeedTime: TimeInterval = 0
        var lastSpeedBytes: Int64 = 0

        init(url: URL, headers: [String: String], dir: URL) {
            self.url = url
            self.headers = headers
            self.dir = dir
        }

        func partFile(_ index: Int) -> URL {
            return dir.appendingPathComponent("part.\(index)")
        }
    }

    /// Range 探测总大小：206 + Content-Range 解析；失败退回 Content-Length。
    private func probeTotal(url: URL, headers: [String: String]) async throws -> Int64 {
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        do {
            let (_, resp) = try await HTTP.session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw YxiOSError.message("无效的响应")
            }
            if http.statusCode == 206,
               let cr = http.value(forHTTPHeaderField: "Content-Range") {
                // bytes 0-0/<total>
                let pattern = "bytes\\s+\\d+-\\d+/(\\d+|\\*)"
                if let re = try? NSRegularExpression(pattern: pattern, options: []),
                   let m = re.firstMatch(in: cr, range: NSRange(cr.startIndex..<cr.endIndex, in: cr)),
                   let r = Range(m.range(at: 1), in: cr),
                   let total = Int64(cr[r]), total > 0 {
                    return total
                }
            }
            // 防盗链/链接失效检查：返回 HTML 错误页
            if let ct = http.value(forHTTPHeaderField: "Content-Type"),
               ct.lowercased().contains("text/html") {
                throw YxiOSError.message("下载失败：直链已失效或防盗链拦截（返回 HTML 页），请重新获取下载链接")
            }
            let len = http.expectedContentLength
            if len > 0 { return len }
        } catch let e as YxiOSError {
            throw e
        } catch {
            // 探测失败视为未知大小，走流式
        }
        return -1
    }

    /// 用户设置的下载线程数（同时作为最大分片数和最大并发数）
    private var threadCount: Int { Storage.downloadThreads }

    private func setupChunks(_ rt: Runtime) {
        if rt.total <= 0 {
            rt.partCount = 1
            rt.ranges = [(start: 0, end: Int64.max - 1)]
            rt.done = [false]
            return
        }
        // 目标分片数 = 用户设置的线程数（每个分片一个并发连接，跑满带宽）
        let targetChunks = threadCount
        // 动态分片大小：确保分片数接近目标值，最小 256KB/片（避免过小文件分片过多）
        let minChunkSize: Int64 = 256 * 1024
        var n = targetChunks
        let perByTarget = (rt.total + Int64(n) - 1) / Int64(n)
        if perByTarget < minChunkSize {
            // 文件太小，按最小分片大小计算分片数
            n = Int((rt.total + minChunkSize - 1) / minChunkSize)
        }
        n = max(n, 1)
        rt.partCount = n
        rt.ranges = []
        rt.done = []
        let per = (rt.total + Int64(n) - 1) / Int64(n)
        for i in 0..<n {
            let start = Int64(i) * per
            let end = min(start + per - 1, rt.total - 1)
            rt.ranges.append((start, end))
            rt.done.append(false)
        }
        rt.downloadedBytes = onDiskBytes(rt)
        rt.nextChunkIndex = 0
        rt.activeCount = 0
    }

    private func onDiskBytes(_ rt: Runtime) -> Int64 {
        var sum: Int64 = 0
        for i in 0..<rt.partCount {
            let p = rt.partFile(i)
            if let size = (try? fm.attributesOfItem(atPath: p.path))?[.size] as? UInt64 {
                sum += Int64(size)
            }
        }
        return min(sum, rt.total > 0 ? rt.total : sum)
    }

    private func launchChunks(_ taskID: UUID) {
        guard let rt = runtimes[taskID] else { return }
        // 启动最多 threadCount 个未完成的分片（并发数 = 用户设置的线程数）
        let maxConcurrent = threadCount
        var started = 0
        while started < maxConcurrent && rt.nextChunkIndex < rt.partCount {
            let idx = rt.nextChunkIndex
            rt.nextChunkIndex += 1
            if rt.done[idx] { continue }
            let t = Task { await self.runChunk(taskID: taskID, index: idx) }
            rt.workers.append(t)
            started += 1
        }
    }

    /// 启动下一个未完成的分片（在当前分片完成后调用）
    private func launchNextChunk(_ taskID: UUID) {
        guard let rt = runtimes[taskID] else { return }
        guard !rt.cancelled, !rt.paused else { return }
        while rt.nextChunkIndex < rt.partCount {
            let idx = rt.nextChunkIndex
            rt.nextChunkIndex += 1
            if rt.done[idx] { continue }
            let t = Task { await self.runChunk(taskID: taskID, index: idx) }
            rt.workers.append(t)
            return
        }
    }

    private func runChunk(taskID: UUID, index: Int) async {
        guard let rt = runtimes[taskID] else { return }
        rt.activeCount += 1
        defer {
            rt.activeCount -= 1
            // 当前分片完成后，启动下一个未完成的分片
            launchNextChunk(taskID)
        }
        for attempt in 0..<3 {
            if rt.cancelled || rt.paused { return }
            do {
                try await downloadOneChunk(taskID: taskID, index: index)
                rt.done[index] = true
                refreshProgress(taskID, force: true)  // 分片完成时强制刷新，避免最后进度卡在节流间隔里
                chunkSettled(taskID, error: nil)
                return
            } catch is CancellationError {
                return
            } catch {
                if attempt >= 2 {
                    rt.lastError = (error as? YxiOSError)?.errorDescription ?? error.localizedDescription
                    chunkSettled(taskID, error: error)
                    return
                }
                let delay = min(500 * (attempt + 1), 3000)
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
        }
    }

    private func downloadOneChunk(taskID: UUID, index: Int) async throws {
        guard let rt = runtimes[taskID] else { return }
        let partURL = rt.partFile(index)
        if !fm.fileExists(atPath: partURL.path) {
            fm.createFile(atPath: partURL.path, contents: Data())
        }
        let existing = ((try? fm.attributesOfItem(atPath: partURL.path))?[.size] as? UInt64) ?? 0
        var start: Int64
        let end: Int64
        if rt.total <= 0 {
            // 流式开放区间
            start = Int64(existing)
            end = -1
        } else {
            start = rt.ranges[index].start + Int64(existing)
            end = rt.ranges[index].end
            if start > end { return } // 已完成
        }

        var req = URLRequest(url: rt.url)
        for (k, v) in rt.headers { req.setValue(v, forHTTPHeaderField: k) }
        if end < 0 {
            req.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
        } else {
            req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        }

        let (bytes, http) = try await HTTP.dataChunks(for: req)
        // 防盗链/链接失效检查：CDN 返回 HTML 错误页而非文件
        if let ct = http.value(forHTTPHeaderField: "Content-Type"),
           ct.lowercased().contains("text/html") {
            throw YxiOSError.message("下载失败：直链已失效或防盗链拦截（返回 HTML 页），请重新获取下载链接")
        }
        if http.statusCode == 200 {
            // 服务器忽略了 Range（整文件）
            rt.rangeIgnored += 1
            throw YxiOSError.message("服务器忽略了 Range 请求")
        }
        guard http.statusCode == 206 || http.statusCode == 200 else {
            throw YxiOSError.message("下载失败，HTTP \(http.statusCode)")
        }

        let handle = try FileHandle(forWritingTo: partURL)
        do {
            try handle.seekToEnd()
            for try await chunk in bytes {
                if Task.isCancelled || rt.cancelled || rt.paused {
                    try? handle.close()
                    throw CancellationError()
                }
                try handle.write(contentsOf: chunk)
                rt.downloadedBytes += Int64(chunk.count)
                self.refreshProgress(taskID)
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func chunkSettled(_ taskID: UUID, error: Error?) {
        guard let rt = runtimes[taskID] else { return }
        rt.settled += 1
        guard !rt.cancelled, !rt.paused else { return }

        if rt.rangeIgnored >= 3 {
            Task { await self.singleStreamFallback(taskID) }
            return
        }

        if rt.settled < rt.partCount { return }

        let allDone = rt.done.allSatisfy { $0 }
        if allDone {
            Task { await self.merge(taskID) }
        } else if rt.taskRetries < 3 {
            rt.taskRetries += 1
            let waitMs = 1200 * rt.taskRetries
            Task {
                try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000)
                guard let r = self.runtimes[taskID], !r.cancelled, !r.paused else { return }
                r.settled = 0
                r.nextChunkIndex = 0  // 重置，从头扫描未完成分片
                self.launchChunks(taskID)
            }
        } else {
            markFailed(taskID, rt.lastError ?? "下载失败，请重试")
        }
    }

    /// 单流回退下载到独立文件（Range 被忽略累计 3 次后）。
    private func singleStreamFallback(_ taskID: UUID) async {
        guard let rt = runtimes[taskID] else { return }
        let singleFile = rt.dir.appendingPathComponent("full_single.bin")
        try? fm.removeItem(at: singleFile)
        fm.createFile(atPath: singleFile.path, contents: Data())
        guard let handle = try? FileHandle(forWritingTo: singleFile) else {
            markFailed(taskID, "无法创建下载文件")
            return
        }
        do {
            var req = URLRequest(url: rt.url)
            for (k, v) in rt.headers { req.setValue(v, forHTTPHeaderField: k) }
            let (bytes, http) = try await HTTP.dataChunks(for: req)
            // 防盗链/链接失效检查
            if let ct = http.value(forHTTPHeaderField: "Content-Type"),
               ct.lowercased().contains("text/html") {
                try? handle.close()
                markFailed(taskID, "下载失败：直链已失效或防盗链拦截（返回 HTML 页），请重新获取下载链接")
                return
            }
            for try await chunk in bytes {
                if Task.isCancelled || rt.cancelled || rt.paused {
                    try? handle.close()
                    return
                }
                try handle.write(contentsOf: chunk)
            }
            try handle.close()
            let size = ((try? fm.attributesOfItem(atPath: singleFile.path))?[.size] as? UInt64) ?? 0
            // 完整性校验放宽：CDN 可能返回不准确的 Content-Length（如压缩/转码后大小）。
            // 仅当下载大小为 0，或与预期差异超过 10% 且超过 1MB 时才判失败。
            if size == 0 {
                try? fm.removeItem(at: singleFile)
                markFailed(taskID, "下载内容为空")
                return
            }
            if rt.total > 0 {
                let diff = abs(Int64(size) - rt.total)
                if diff > rt.total / 10 && diff > 1_000_000 {
                    try? fm.removeItem(at: singleFile)
                    markFailed(taskID, "下载内容不完整（预期 \(rt.total) 字节，实际 \(size) 字节）")
                    return
                }
            }
            try? await finalize(taskID, from: singleFile)
        } catch {
            try? handle.close()
            markFailed(taskID, (error as? YxiOSError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 按偏移拼接分片为最终文件，边写边删分片。
    private func merge(_ taskID: UUID) async {
        guard let rt = runtimes[taskID] else { return }
        // 完整性校验：已写字节应等于 total（流式除外）
        if rt.total > 0 && onDiskBytes(rt) != rt.total {
            cleanupTaskDir(rt)
            markFailed(taskID, "下载分片不完整")
            return
        }
        // 用第一个分片作中转（直接移动再合并其余分片）
        guard rt.partCount > 0 else {
            markFailed(taskID, "无分片可合并")
            return
        }
        let firstPart = rt.partFile(0)
        guard fm.fileExists(atPath: firstPart.path) else {
            markFailed(taskID, "分片缺失")
            return
        }
        do {
            // 先输出到临时文件，校验通过后再改名
            let tmpOut = rt.dir.appendingPathComponent("output.tmp")
            try? fm.removeItem(at: tmpOut)
            fm.createFile(atPath: tmpOut.path, contents: Data())
            guard let outHandle = try? FileHandle(forWritingTo: tmpOut) else {
                markFailed(taskID, "无法写入文件")
                return
            }
            var written: Int64 = 0
            for i in 0..<rt.partCount {
                let p = rt.partFile(i)
                if let d = try? Data(contentsOf: p) {
                    try outHandle.write(contentsOf: d)
                    written += Int64(d.count)
                }
                try? fm.removeItem(at: p)
            }
            try outHandle.close()
            if rt.total > 0 && written != rt.total {
                try? fm.removeItem(at: tmpOut)
                cleanupTaskDir(rt)
                markFailed(taskID, "合并字节数与预期不符")
                return
            }
            try await finalize(taskID, from: tmpOut)
        } catch {
            markFailed(taskID, "合并文件失败：\(error.localizedDescription)")
        }
    }

    /// 把临时/分片文件落到 Downloads/<fileName>，更新任务完成态。
    private func finalize(_ taskID: UUID, from tempFile: URL) async throws {
        guard let task = task(with: taskID) else { return }
        let dest = uniqueDownloadURL(name: task.fileName)
        if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
        try fm.moveItem(at: tempFile, to: dest)
        let rel = dest.lastPathComponent
        updateTask(taskID) {
            $0.status = .completed
            $0.progress = 1.0
            $0.localPath = rel
            $0.errorMessage = nil
            if $0.totalBytes <= 0 {
                $0.totalBytes = ((try? fm.attributesOfItem(atPath: dest.path))?[.size] as? UInt64).map { Int64($0) } ?? 0
                $0.downloadedBytes = $0.totalBytes
            }
        }
        cleanupTaskDir(runtimes[taskID]!)
        runtimes[taskID] = nil
        Storage.saveTasks(tasks)
    }

    // MARK: - Helpers

    private func uniqueDownloadURL(name: String) -> URL {
        let base = Storage.downloadsDirectory.appendingPathComponent(name)
        if !fm.fileExists(atPath: base.path) { return base }
        // base_yyyyMMddHHmmss.ext
        let ext = (name as NSString).pathExtension
        let noExt = (name as NSString).deletingPathExtension
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMddHHmmss"
        let stamp = fmt.string(from: Date())
        let newName: String
        if ext.isEmpty {
            newName = "\(noExt)_\(stamp)"
        } else {
            newName = "\(noExt)_\(stamp).\(ext)"
        }
        return Storage.downloadsDirectory.appendingPathComponent(newName)
    }

    private func cleanupTaskDir(_ rt: Runtime) {
        try? fm.removeItem(at: rt.dir)
    }

    private func markDownloading(_ taskID: UUID) {
        updateTask(taskID) { $0.status = .downloading }
    }

    private func markFailed(_ taskID: UUID, _ message: String) {
        updateTask(taskID) {
            $0.status = .failed
            $0.errorMessage = message
        }
        runtimes[taskID] = nil
        Storage.saveTasks(tasks)
    }

    /// 进度 UI 更新节流：每 200ms 最多刷新一次，避免高速下载时每秒上百次 @Published 触发 SwiftUI 掉帧
    private let progressThrottleInterval: TimeInterval = 0.2

    private func refreshProgress(_ taskID: UUID, force: Bool = false) {
        guard let rt = runtimes[taskID] else { return }
        let now = Date().timeIntervalSince1970
        if !force {
            guard now - rt.lastProgressUpdate >= progressThrottleInterval else { return }
        }
        rt.lastProgressUpdate = now

        // 计算实时下载速度（基于上次检查到现在的字节差/时间差）
        if rt.lastSpeedTime > 0 {
            let dt = now - rt.lastSpeedTime
            if dt > 0.1 {
                let dB = Double(rt.downloadedBytes - rt.lastSpeedBytes)
                if dB >= 0 {
                    let instantSpeed = dB / dt
                    // 滑动平均（70% 历史 + 30% 瞬时），避免抖动
                    let prev = speeds[taskID] ?? instantSpeed
                    speeds[taskID] = prev * 0.7 + instantSpeed * 0.3
                }
            }
        }
        rt.lastSpeedTime = now
        rt.lastSpeedBytes = rt.downloadedBytes

        updateTask(taskID) {
            $0.downloadedBytes = rt.downloadedBytes
            if rt.total > 0 {
                $0.progress = min(1.0, Double(rt.downloadedBytes) / Double(rt.total))
            }
        }
    }

    private func updateTask(_ id: UUID, _ fn: (inout DownloadTask) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        fn(&tasks[idx])
    }
}
