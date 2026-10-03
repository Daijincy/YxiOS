//
//  DownloadsView.swift
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
//  Lists DownloadManager.shared.tasks with live progress, pause/resume/retry/
//  delete actions, and a share sheet for completed files.
//

import SwiftUI
import UIKit

public struct DownloadsView: View {
    @EnvironmentObject private var dm: DownloadManager

    @State private var taskToDelete: DownloadTask?
    @State private var shareItem: ShareItem?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if dm.tasks.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(dm.tasks) { task in
                            taskRow(task)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { dm.remove(dm.tasks[$0].id) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(LiquidGlassBackground())
            .navigationTitle("下载")
            .alert("删除任务", isPresented: Binding<Bool>(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            )) {
                Button(role: .destructive) {
                    if let task = taskToDelete { dm.remove(task.id) }
                    taskToDelete = nil
                } label: {
                    Text("删除")
                }
                Button("取消", role: .cancel) { taskToDelete = nil }
            } message: {
                Text("确认删除「\(taskToDelete?.fileName ?? "")」？未完成的分片将被清理。")
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无下载任务")
                .font(.headline)
                .foregroundStyle(.white)
            Text("在「解析」页选择文件后，下载任务会显示在这里")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func taskRow(_ task: DownloadTask) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: iconName(task))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.fileName)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        PlatformBadge(task.platform.displayName)
                        Text(statusText(task))
                            .font(.caption)
                            .foregroundStyle(statusColor(task))
                    }
                }
                Spacer()
            }

            ProgressView(value: max(0, min(task.progress, 1)))
                .tint(Color(red: 0.45, green: 0.6, blue: 1.0))

            HStack {
                Text(Formatters.progressText(downloaded: task.downloadedBytes,
                                             total: task.totalBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let msg = task.errorMessage, task.status == .failed {
                    Text("· \(msg)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                if task.status == .downloading {
                    smallAction("暂停", systemImage: "pause.circle", role: .secondary) {
                        dm.pause(task.id)
                    }
                }
                if task.status == .queued || task.status == .paused {
                    smallAction("继续", systemImage: "play.circle", role: .primary) {
                        dm.resume(task.id)
                    }
                }
                if task.status == .failed {
                    smallAction("重试", systemImage: "arrow.clockwise.circle", role: .primary) {
                        dm.retry(task.id)
                    }
                }
                if task.status == .completed {
                    smallAction("分享", systemImage: "square.and.arrow.up", role: .secondary) {
                        if let url = dm.fileURL(for: task) {
                            shareItem = ShareItem(url: url)
                        }
                    }
                }
                smallAction("删除", systemImage: "trash", role: .destructive) {
                    taskToDelete = task
                }
            }
        }
        .padding(14)
        .glassCardStyle(cornerRadius: 18)
    }

    private func smallAction(_ title: String,
                             systemImage: String,
                             role: ButtonRole,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : (role == .primary ? .blue : .secondary))
    }

    private func statusText(_ t: DownloadTask) -> String {
        switch t.status {
        case .queued: return "排队中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }

    private func statusColor(_ t: DownloadTask) -> Color {
        switch t.status {
        case .completed: return .green
        case .failed: return .red
        case .paused: return .orange
        default: return .secondary
        }
    }

    private func iconName(_ t: DownloadTask) -> String {
        switch t.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .paused: return "pause.circle.fill"
        default: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Share item + sheet

public struct ShareItem: Identifiable {
    public let id = UUID()
    public let url: URL
}

public struct ShareSheet: UIViewControllerRepresentable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
