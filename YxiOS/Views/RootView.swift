//
//  RootView.swift
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
//  Root tab container: 解析 / 下载 / 设置.
//

import SwiftUI

public struct RootView: View {
    @State private var selection = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            ResolveView()
                .tabItem {
                    Label("解析", systemImage: "link")
                }
                .tag(0)

            DownloadsView()
                .tabItem {
                    Label("下载", systemImage: "arrow.down.circle.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
                .tag(2)
        }
        .tint(Color(red: 0.45, green: 0.6, blue: 1.0))
    }
}
