//
//  YxiOSApp.swift
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
//  App entry: inject DownloadManager & LoginSession, force dark mode to
//  preserve the liquid-glass aesthetic.
//

import SwiftUI

@main
struct YxiOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(DownloadManager.shared)
                .environmentObject(LoginSession.shared)
                .preferredColorScheme(.dark)
        }
    }
}
