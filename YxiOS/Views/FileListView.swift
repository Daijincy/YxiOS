//
//  FileListView.swift
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
//  Generic file / directory row list used inside the resolver browser.
//  Directories are NavigationLinks (value: FileEntry) pushed onto the
//  enclosing NavigationStack; files expose an inline download button.
//

import SwiftUI

public struct FileListView: View {
    public let entries: [FileEntry]
    public var onDownload: ((FileEntry) -> Void)?

    public init(entries: [FileEntry], onDownload: ((FileEntry) -> Void)? = nil) {
        self.entries = entries
        self.onDownload = onDownload
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                if entry.isDirectory {
                    NavigationLink(value: entry) {
                        FileRow(entry: entry, onDownload: nil)
                    }
                    .buttonStyle(.plain)
                } else {
                    FileRow(entry: entry, onDownload: onDownload)
                }
            }
        }
    }
}

// MARK: - Single row

public struct FileRow: View {
    public let entry: FileEntry
    public var onDownload: ((FileEntry) -> Void)?

    public init(entry: FileEntry, onDownload: ((FileEntry) -> Void)? = nil) {
        self.entry = entry
        self.onDownload = onDownload
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundStyle(entry.isDirectory
                                ? Color(red: 0.45, green: 0.6, blue: 1.0)
                                : Color(white: 0.7))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.isDirectory ? "文件夹" : Formatters.fileSize(entry.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if let onDownload {
                Button {
                    onDownload(entry)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(red: 0.45, green: 0.6, blue: 1.0))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var iconName: String {
        if entry.isDirectory { return "folder.fill" }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp":
            return "photo"
        case "mp4", "mov", "mkv", "avi", "flv":
            return "play.rectangle.fill"
        case "mp3", "wav", "flac", "aac", "m4a":
            return "music.note"
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return "archivebox.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx", "csv":
            return "tablecells"
        case "txt", "md", "log":
            return "doc.text"
        default:
            return "doc"
        }
    }
}
