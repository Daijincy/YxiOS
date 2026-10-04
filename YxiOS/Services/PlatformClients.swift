//
//  PlatformClients.swift
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
//  Concrete platform clients (Quark / Baidu / Pan123 / Xunlei), implemented
//  per platform-spec §3 ~ §6. Signatures frozen by API-CONTRACT §3.
//

import Foundation

// MARK: - 夸克 QUARK

final class QuarkClient: PlatformClient, DirectURLProvider, @unchecked Sendable {

    static let shared = QuarkClient()

    private let base = "https://drive-pc.quark.cn"
    private let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.12-a038f7b798 Safari/537.36 Channel/pckk_other_ch"

    private let authBox = Protected<PlatformAuth?>(nil)
    private let downloadHeadersBox = Protected<[String: String]>([:])
    // shareID → (stoken, firstFid)
    private let tokenCache = Protected<[String: (stoken: String, firstFid: String)]>([:])
    // fid → share_fid_token（游客取链需要）
    private let fidTokenCache = Protected<[String: String]>([:])

    let platform: Platform = .quark
    var requiresLogin: Bool { true }

    private init() {}

    func setAuth(_ auth: PlatformAuth?) {
        authBox.write(auth)
    }

    private var cookie: String? { authBox.read()?.cookie }
    private var isLoggedIn: Bool {
        guard let c = cookie else { return false }
        return c.contains("__pus=") && c.contains("__puus=")
    }

    func resolveShare(_ info: ShareInfo) async throws -> [FileEntry] {
        let token = try await fetchToken(info)
        return try await listFiles(info, pdirFid: token.firstFid)
    }

    func listChildren(_ dirID: String, of info: ShareInfo) async throws -> [FileEntry] {
        _ = try await fetchToken(info)
        return try await listFiles(info, pdirFid: dirID)
    }

    func getDirectURL(for file: FileEntry, share: ShareInfo) async throws -> URL {
        return try await directDownloadURL(for: file, share: share).url
    }

    func directDownloadURL(for file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL {
        let result = try await resolveDownloadURL(file: file, share: share)
        downloadHeadersBox.write(result.headers)
        return result
    }

    // MARK: Quark internals

    private func fetchToken(_ info: ShareInfo) async throws -> (stoken: String, firstFid: String) {
        if let cached = tokenCache.read()[info.shareID] { return cached }

        let urlString = base + "/1/clouddrive/share/sharepage/token?pr=ucpro&fr=pc"
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let c = cookie { req.setValue(c, forHTTPHeaderField: "Cookie") }
        let body: [String: Any] = [
            "pwd_id": info.shareID,
            "passcode": info.password ?? "",
            "support_visit_limit_private_share": true
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("夸克：响应解析失败")
        }
        let status = json["status"]?.int64 ?? -1
        guard status == 200,
              let stoken = json["data"]?["stoken"]?.string else {
            throw YxiOSError.message(serverMessage(json, fallback: "夸克：获取分享令牌失败"))
        }
        let firstFid = json["data"]?["first_fid"]?.string ?? "0"
        let pair = (stoken, firstFid)
        tokenCache.mutate { $0[info.shareID] = pair }
        return pair
    }

    private func listFiles(_ info: ShareInfo, pdirFid: String) async throws -> [FileEntry] {
        let token = try await fetchToken(info)
        let query = URLEncoder.query(items: [
            "pr": "ucpro", "fr": "pc",
            "pwd_id": info.shareID,
            "stoken": token.stoken,
            "pdir_fid": pdirFid,
            "ver": "2", "force": "0", "_page": "1", "_size": "100",
            "_fetch_banner": "0", "_fetch_share": "0",
            "fetch_relate_conversation": "0", "_fetch_total": "1",
            "_sort": "file_type:asc,file_name:asc"
        ])
        let urlString = base + "/1/clouddrive/share/sharepage/detail?" + query
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "GET"
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("https://pan.quark.cn", forHTTPHeaderField: "Origin")
        req.setValue("https://pan.quark.cn/", forHTTPHeaderField: "Referer")
        if let c = cookie { req.setValue(c, forHTTPHeaderField: "Cookie") }

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("夸克：文件列表解析失败")
        }
        let status = json["status"]?.int64 ?? -1
        guard status == 200 else {
            throw YxiOSError.message(serverMessage(json, fallback: "夸克：获取文件列表失败"))
        }
        guard let list = json["data"]?["list"]?.array else { return [] }

        var out: [FileEntry] = []
        for item in list {
            guard let fid = item["fid"]?.string, let name = item["file_name"]?.string else { continue }
            let size = item["size"]?.int64 ?? 0
            let isDir = item["dir"]?.bool ?? false
            let pdir = item["pdir_fid"]?.string
            if let ftk = item["share_fid_token"]?.string {
                fidTokenCache.mutate { $0[fid] = ftk }
            }
            out.append(FileEntry(id: fid, name: name, size: size, isDirectory: isDir,
                                 parentID: pdir, downloadURL: nil))
        }
        return out
    }

    private func resolveDownloadURL(file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL {
        _ = try await fetchToken(share)
        let referer = "https://pan.quark.cn/"

        if isLoggedIn {
            // 登录态：始终走转存流程（与 Android 版一致）
            // 分享文件 fid 不能直接调 download 接口，必须转存到个人盘后用新 fid 取链
            let url = try await largeFileDownloadURL(file: file, share: share)
            var headers: [String: String] = ["Referer": referer, "User-Agent": ua]
            if let c = cookie { headers["Cookie"] = c }
            return ResolvedDirectURL(url: URL(string: url)!, headers: headers)
        } else {
            // 游客直链（≤50MB）
            return try await guestDownloadURL(file: file, share: share, referer: referer)
        }
    }

    private func loggedInDownloadURL(fid: String) async throws -> String? {
        let urlString = base + "/1/clouddrive/file/download?pr=ucpro&fr=pc&sys=win32&ve=3.23.2"
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let c = cookie { req.setValue(c, forHTTPHeaderField: "Cookie") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["fids": [fid]], options: [])

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else { return nil }
        let status = json["status"]?.int64 ?? -1
        let code = json["code"]?.int64
        guard status == 200 || code == 0 else { return nil }
        return json["data"]?.array?.first?["download_url"]?.string
    }

    private func guestDownloadURL(file: FileEntry, share: ShareInfo, referer: String) async throws -> ResolvedDirectURL {
        let token = try await fetchToken(share)
        let ftk = fidTokenCache.read()[file.id] ?? ""
        let urlString = base + "/1/clouddrive/file/download?pr=ucpro&fr=pc&sys=win32&ve=3.23.2"
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        // 游客首次不带 Cookie
        let body: [String: Any] = [
            "fids": [file.id],
            "fids_token": [ftk],
            "pwd_id": share.shareID,
            "stoken": token.stoken,
            "speedup_session": "",
            "token": ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("夸克：取直链失败")
        }
        let code = json["code"]?.int64
        if code == 23018 {
            throw YxiOSError.message("该文件超出游客下载大小限制，请登录夸克账号")
        }
        if code == 31001 {
            throw YxiOSError.message("该文件需要登录夸克账号后下载")
        }
        guard let url = json["data"]?.array?.first?["download_url"]?.string else {
            throw YxiOSError.message(serverMessage(json, fallback: "夸克：获取下载链接失败"))
        }
        // 下载需带 __pugs
        var headers: [String: String] = ["Referer": referer, "User-Agent": ua]
        if let pugs = resp.cookieValue(named: "__pugs") {
            headers["Cookie"] = "__pugs=\(pugs)"
        }
        return ResolvedDirectURL(url: URL(string: url)!, headers: headers)
    }

    private func largeFileDownloadURL(file: FileEntry, share: ShareInfo) async throws -> String {
        let token = try await fetchToken(share)
        let ftk = fidTokenCache.read()[file.id] ?? ""
        // 转存到个人盘根目录（to_pdir_fid=0）
        let saveBody: [String: Any] = [
            "pwd_id": share.shareID,
            "stoken": token.stoken,
            "pdir_fid": "0",
            "to_pdir_fid": "0",
            "fid_list": [file.id],
            "fid_token_list": [ftk],
            "scene": "link"
        ]
        var req = URLRequest(url: URL(string: base + "/1/clouddrive/share/sharepage/save?pr=ucpro&fr=pc")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let c = cookie { req.setValue(c, forHTTPHeaderField: "Cookie") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: saveBody, options: [])
        let saveResp = try await HTTP.send(req)
        let saveJson = JSON.parse(saveResp.data)
        guard let taskID = saveJson?["data"]?["task_id"]?.string else {
            throw YxiOSError.message(serverMessage(saveJson, fallback: "夸克：转存失败"))
        }
        // 轮询最多 10 次
        var newFid: String?
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let pollURL = base + "/1/clouddrive/task?pr=ucpro&fr=pc&task_id=\(taskID)&retry_index=0"
            var preq = URLRequest(url: URL(string: pollURL)!)
            preq.setValue(ua, forHTTPHeaderField: "User-Agent")
            if let c = cookie { preq.setValue(c, forHTTPHeaderField: "Cookie") }
            let presp = try await HTTP.send(preq)
            if let pjson = JSON.parse(presp.data) {
                let finished = pjson["data"]?["finished_at"]?.int64 ?? 0
                let status = pjson["data"]?["status"]?.int64 ?? 0
                let taskStatus = pjson["data"]?["task_status"]?.int64 ?? 0
                if finished > 0 || status == 2 || taskStatus == 2 {
                    newFid = pjson["data"]?["save_as"]?["save_as_top_fids"]?.array?.first?.string
                    break
                }
            }
        }
        guard let nf = newFid, !nf.isEmpty else {
            throw YxiOSError.message("夸克：转存轮询超时")
        }
        // 取新 fid 的直链
        guard let url = try await loggedInDownloadURL(fid: nf) else {
            throw YxiOSError.message("夸克：获取大文件直链失败")
        }
        // 注意：不立即删除转存文件——夸克直链可能绑定文件，删除后直链会失效
        // 文件保留在用户网盘根目录，用户可自行清理
        return url
    }
}

// MARK: - 百度 BAIDU

final class BaiduClient: PlatformClient, DirectURLProvider, @unchecked Sendable {

    static let shared = BaiduClient()

    private let uaWeb = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let uaNetdisk = "netdisk;12.24.6;piano;android-android;16;JSbridge4.4.0;jointBridge;1.1.0"
    private let appID = "250528"

    private struct ShareCache {
        let surl: String
        let sekey: String?
        let shareID: String
        let uk: String
    }

    private let authBox = Protected<PlatformAuth?>(nil)
    private let downloadHeadersBox = Protected<[String: String]>([:])
    private let cache = Protected<[String: ShareCache]>([:])

    let platform: Platform = .baidu
    var requiresLogin: Bool { true }

    private init() {}

    func setAuth(_ auth: PlatformAuth?) { authBox.write(auth) }

    private var cookie: String? { authBox.read()?.cookie }
    private var isLoggedIn: Bool {
        guard let c = cookie else { return false }
        return c.contains("BDUSS=")
    }

    func resolveShare(_ info: ShareInfo) async throws -> [FileEntry] {
        guard isLoggedIn else {
            throw YxiOSError.message("百度网盘需要登录后才能解析分享")
        }
        let surl = info.shareID
        let sekey = try await verify(surl: surl, pwd: info.password)
        let list = try await listFiles(surl: surl, dir: "/", root: 1, sekey: sekey)
        return list
    }

    func listChildren(_ dirID: String, of info: ShareInfo) async throws -> [FileEntry] {
        let surl = info.shareID
        let sekey = (try? await verify(surl: surl, pwd: info.password)) ?? cache.read()[info.shareID]?.sekey
        return try await listFiles(surl: surl, dir: dirID, root: 0, sekey: sekey)
    }

    func getDirectURL(for file: FileEntry, share: ShareInfo) async throws -> URL {
        return try await directDownloadURL(for: file, share: share).url
    }

    func directDownloadURL(for file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL {
        let result = try await resolveDownloadURL(file: file, share: share)
        downloadHeadersBox.write(result.headers)
        return result
    }

    // MARK: Baidu internals

    private func effectiveCookie(sekey: String?) -> String? {
        guard let base = cookie else { return nil }
        guard let sekey = sekey, !sekey.isEmpty else { return base }
        if base.contains("BDCLND=") { return base }
        return base + "; BDCLND=" + sekey
    }

    private func verify(surl: String, pwd: String?) async throws -> String? {
        let urlString = "https://pan.baidu.com/share/verify?surl=" + surl
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(uaWeb, forHTTPHeaderField: "User-Agent")
        req.setValue("https://pan.baidu.com/s/" + surl, forHTTPHeaderField: "Referer")
        if let c = cookie { req.setValue(c, forHTTPHeaderField: "Cookie") }
        req.httpBody = URLEncoder.form(["pwd": pwd ?? "", "vcode_str": "", "vcode": ""]).data(using: .utf8)

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("百度：验证响应解析失败")
        }
        let errno = json["errno"]?.int64 ?? -1
        if errno == -12 { throw YxiOSError.message("提取码错误") }
        if errno == -6 { throw YxiOSError.message("登录状态失效，请重新登录百度网盘") }
        guard errno == 0 else {
            throw YxiOSError.message(serverMessage(json, fallback: "百度：提取码验证失败（errno=\(errno)）"))
        }
        return json["randsk"]?.string
    }

    private func listFiles(surl: String, dir: String, root: Int, sekey: String?) async throws -> [FileEntry] {
        var items: [String: String?] = [
            "method": "list", "shorturl": surl, "page": "1", "num": "100",
            "root": "\(root)", "dir": dir
        ]
        if let sekey = sekey, !sekey.isEmpty { items["sekey"] = sekey }
        let urlString = "https://pan.baidu.com/rest/2.0/xpan/share?" + URLEncoder.query(items: items)
        var req = URLRequest(url: URL(string: urlString)!)
        req.setValue(uaWeb, forHTTPHeaderField: "User-Agent")
        req.setValue("https://pan.baidu.com/s/" + surl, forHTTPHeaderField: "Referer")
        if let c = effectiveCookie(sekey: sekey) { req.setValue(c, forHTTPHeaderField: "Cookie") }

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("百度：文件列表解析失败")
        }
        let errno = json["errno"]?.int64 ?? -1
        if errno == -12 { throw YxiOSError.message("提取码错误") }
        if errno == -6 { throw YxiOSError.message("登录状态失效，请重新登录百度网盘") }
        guard errno == 0 else {
            throw YxiOSError.message(serverMessage(json, fallback: "百度：获取文件列表失败（errno=\(errno)）"))
        }

        // 缓存 share_id / uk
        let sid = json["data"]?["share_id"]?.string ?? ""
        let uk = json["data"]?["uk"]?.string ?? ""
        cache.mutate { $0[surl] = ShareCache(surl: surl, sekey: sekey, shareID: sid, uk: uk) }

        guard let list = json["data"]?["list"]?.array else { return [] }
        var out: [FileEntry] = []
        for item in list {
            let isDir = item["isdir"]?.string == "1"
            let name = item["server_filename"]?.string ?? ""
            let size = item["size"]?.int64 ?? 0
            let path = item["path"]?.string ?? ""
            let fsID = item["fs_id"]?.string ?? ""
            let fid = isDir ? path : fsID
            if fid.isEmpty { continue }
            out.append(FileEntry(id: fid, name: name, size: size, isDirectory: isDir,
                                 parentID: dir == "/" ? nil : dir, downloadURL: nil))
        }
        return out
    }

    private func resolveDownloadURL(file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL {
        guard let sc = cache.read()[share.shareID] else {
            throw YxiOSError.message("百度：分享信息缺失，请重新解析")
        }
        // 1. bdstoken
        let bdstoken = try await getBDSToken()
        // 2. 转存到个人盘根目录
        let newPath = try await transfer(fsID: file.id, sc: sc, bdstoken: bdstoken)
        // 3. locatedownload 取直链
        let url = try await locatedownload(path: newPath, sekey: sc.sekey)
        let headers: [String: String] = [
            "User-Agent": uaNetdisk,
            "Cookie": cookie ?? ""
        ]
        return ResolvedDirectURL(url: URL(string: url)!, headers: headers)
    }

    private func getBDSToken() async throws -> String {
        let fields = URLEncoder.percent("[\"bdstoken\"]")
        let urlString = "https://pan.baidu.com/api/gettemplatevariable?clienttype=0&app_id=\(appID)&web=1&fields=\(fields)"
        var req = URLRequest(url: URL(string: urlString)!)
        req.setValue(uaWeb, forHTTPHeaderField: "User-Agent")
        if let c = cookie { req.setValue(c, forHTTPHeaderField: "Cookie") }
        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data),
              let token = json["result"]?["bdstoken"]?.string else {
            throw YxiOSError.message("百度：获取 bdstoken 失败")
        }
        return token
    }

    private func transfer(fsID: String, sc: ShareCache, bdstoken: String) async throws -> String {
        let sekey = sc.sekey ?? ""
        let q = URLEncoder.query(items: [
            "shareid": sc.shareID, "from": sc.uk, "channel": "chunlei",
            "sekey": sekey, "ondup": "newcopy", "web": "1",
            "app_id": appID, "bdstoken": bdstoken, "clienttype": "0"
        ])
        let urlString = "https://pan.baidu.com/share/transfer?" + q
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(uaWeb, forHTTPHeaderField: "User-Agent")
        req.setValue("https://pan.baidu.com", forHTTPHeaderField: "Origin")
        req.setValue("https://pan.baidu.com/s/", forHTTPHeaderField: "Referer")
        if let c = effectiveCookie(sekey: sekey) { req.setValue(c, forHTTPHeaderField: "Cookie") }
        req.httpBody = "fsidlist=%5B%22\(fsID)%22%5D&path=%2F".data(using: .utf8)

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("百度：转存响应解析失败")
        }
        let errno = json["errno"]?.int64 ?? -1
        guard errno == 0 else {
            throw YxiOSError.message(serverMessage(json, fallback: "百度：转存失败（errno=\(errno)）"))
        }
        // 转存后返回新文件的完整路径（to 字段），用于 locatedownload
        let extra = json["extra"]?["list"]?.array?.first
        let newPath = extra?["to"]?.string
        guard let path = newPath, !path.isEmpty else {
            throw YxiOSError.message("百度：转存成功但未返回文件路径")
        }
        return path
    }

    private func locatedownload(path: String, sekey: String?) async throws -> String {
        let time = Int(Date().timeIntervalSince1970)
        let q = URLEncoder.query(items: [
            "method": "locatedownload", "app_id": appID, "clienttype": "17",
            "ver": "4.0", "ant": "1", "check_blue": "1", "es": "1", "esl": "1",
            "apn_id": "1_-1", "freeisp": "0", "queryfree": "0", "use": "1",
            "dtype": "1", "eck": "1", "ehps": "1", "err_ver": "1.0",
            "network_type": "WIFI", "channel": "0",
            "path": path, "time": "\(time)",
            "rand": "5ed606e9da222cde0474cdf70eda884b",
            "devuid": "0F1E9FC2E084472DA5A61C4CF4C759AF",
            "cuid": "0F1E9FC2E084472DA5A61C4CF4C759AF",
            "deviceid": "348642637967375013",
            "psign": "860a071f77c860e8cea06e4e54c518f3",
            "version": "2.2.111.34", "version_app": "12.24.6", "vip": "0"
        ])
        let urlString = "https://d.pcs.baidu.com/rest/2.0/pcs/file?" + q
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "POST"
        req.setValue(uaNetdisk, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let c = cookie { req.setValue(c, forHTTPHeaderField: "Cookie") }
        req.httpBody = "0".data(using: .utf8)

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("百度：取直链响应解析失败")
        }
        let errno = json["errno"]?.int64 ?? -1
        guard errno == 0, let urls = json["urls"]?.array else {
            throw YxiOSError.message(serverMessage(json, fallback: "百度：获取高速直链失败（errno=\(errno)）"))
        }
        // 选链：优先 encrypt==0 的 https，排除 d2-ant.baidu.com
        var chosen: String?
        for u in urls {
            guard let url = u["url"]?.string, url.hasPrefix("https://") else { continue }
            let encrypt = u["encrypt"]?.int64 ?? 1
            if encrypt == 0 && !url.contains("d2-ant.baidu.com") { chosen = url; break }
        }
        if chosen == nil {
            for u in urls {
                if let url = u["url"]?.string, url.hasPrefix("https://") { chosen = url; break }
            }
        }
        guard let finalURL = chosen ?? urls.first?["url"]?.string else {
            throw YxiOSError.message("百度：无可用直链")
        }
        return finalURL
    }
}

// MARK: - 123 云盘 PAN123

final class Pan123Client: PlatformClient, DirectURLProvider, @unchecked Sendable {

    static let shared = Pan123Client()

    private let apiBase = "https://yun.123pan.cn"
    private let downloadBase = "https://www.123865.com"
    private let webUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"
    private let dartUA = "Dart/3.12 (dart:io)"
    private let signTable = Array("adefghlmyijnopkqrstubcvwsz")

    private struct FileCache {
        let s3: String
        let etag: String
        let size: Int64
    }

    private let authBox = Protected<PlatformAuth?>(nil)
    private let downloadHeadersBox = Protected<[String: String]>([:])
    private let fileCache = Protected<[String: FileCache]>([:])
    private let loginUUIDBox = Protected<String>("")

    let platform: Platform = .pan123
    var requiresLogin: Bool { true }

    private init() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "yx_123_loginuuid"), !existing.isEmpty {
            loginUUIDBox.write(existing)
        } else {
            let uuid = Self.randomHex32()
            loginUUIDBox.write(uuid)
            defaults.set(uuid, forKey: "yx_123_loginuuid")
        }
    }

    func setAuth(_ auth: PlatformAuth?) { authBox.write(auth) }

    private var token: String? { authBox.read()?.token }

    private static func randomHex32() -> String {
        var s = ""
        for _ in 0..<32 { s.append("0123456789abcdef".randomElement()!) }
        return s
    }

    func resolveShare(_ info: ShareInfo) async throws -> [FileEntry] {
        return try await listShare(info, parentID: "0")
    }

    func listChildren(_ dirID: String, of info: ShareInfo) async throws -> [FileEntry] {
        return try await listShare(info, parentID: dirID)
    }

    func getDirectURL(for file: FileEntry, share: ShareInfo) async throws -> URL {
        return try await directDownloadURL(for: file, share: share).url
    }

    func directDownloadURL(for file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL {
        let result = try await resolveDownloadURL(file: file, share: share)
        downloadHeadersBox.write(result.headers)
        return result
    }

    // MARK: Pan123 internals

    private func listShare(_ info: ShareInfo, parentID: String) async throws -> [FileEntry] {
        var items: [String: String?] = [
            "limit": "100", "next": "0", "orderBy": "file_name",
            "orderDirection": "asc", "shareKey": info.shareID,
            "ParentFileId": parentID, "Page": "1"
        ]
        if let pwd = info.password, !pwd.isEmpty { items["SharePwd"] = pwd }
        let urlString = apiBase + "/b/api/share/get?" + URLEncoder.query(items: items)
        var req = URLRequest(url: URL(string: urlString)!)
        req.setValue(dartUA, forHTTPHeaderField: "User-Agent")

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("123云盘：列表响应解析失败")
        }
        let code = json["code"]?.int64 ?? -1
        guard code == 0 else {
            throw YxiOSError.message(serverMessage(json, fallback: "123云盘：获取分享列表失败（code=\(code)）"))
        }
        if json["data"]?["Expired"]?.bool ?? false {
            throw YxiOSError.message("该分享已失效")
        }
        guard let list = json["data"]?["InfoList"]?.array else { return [] }

        var out: [FileEntry] = []
        for item in list {
            guard let fid = item["FileId"]?.string else { continue }
            let name = item["FileName"]?.string ?? ""
            let size = item["Size"]?.int64 ?? 0
            let type = item["Type"]?.int64 ?? 0
            let parent = item["ParentFileId"]?.string
            // 暂存 S3KeyFlag|Etag|StorageNode 用于取直链
            let s3 = item["S3KeyFlag"]?.string ?? ""
            let etag = item["Etag"]?.string ?? ""
            fileCache.mutate { $0[fid] = FileCache(s3: s3, etag: etag, size: size) }
            out.append(FileEntry(id: fid, name: name, size: size, isDirectory: type == 1,
                                 parentID: parent, downloadURL: nil))
        }
        return out
    }

    /// 按 platform-spec §5.2 生成鉴权头。
    private func signedHeaders(path: String, platform: String, appVersion: String) throws -> [String: String] {
        guard let token = token, !token.isEmpty else {
            throw YxiOSError.message("123云盘下载需要登录，请先在「登录」页完成 123 云盘登录（读取 authorToken）")
        }
        let ts = Int(Date().timeIntervalSince1970)
        let t = ts + 57600
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmm"
        let tStr = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(t)))
        var substituted = ""
        for ch in tStr {
            if let d = Int(String(ch)) {
                substituted.append(signTable[d])
            } else {
                substituted.append(ch)
            }
        }
        let authKey = CRC32.hex(substituted)
        let random = Int.random(in: 0...9999999)
        let data = "\(ts)|\(random)|\(path)|web|3|\(authKey)"
        let authValue = "\(ts)-\(random)-" + CRC32.hex(data)
        return [
            "platform": platform,
            "app-version": appVersion,
            "authorization": "Bearer \(token)",
            "loginuuid": loginUUIDBox.read(),
            "auth-key": authKey,
            "auth-value": authValue,
            "User-Agent": webUA
        ]
    }

    private func resolveDownloadURL(file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL {
        guard let fc = fileCache.read()[file.id] else {
            throw YxiOSError.message("123云盘：文件信息缺失，请重新解析")
        }
        // 分享下载信息（android 平台头）
        let path = "/b/api/share/download/info"
        let headers = try signedHeaders(path: path, platform: "android", appVersion: "39")
        var req = URLRequest(url: URL(string: downloadBase + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let body: [String: Any] = [
            "ShareKey": share.shareID,
            "FileID": file.id,
            "S3KeyFlag": fc.s3,
            "Size": fc.size,
            "Etag": fc.etag
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("123云盘：下载信息解析失败")
        }
        let code = json["code"]?.int64 ?? -1
        guard code == 0, let rawURL = json["data"]?["DownloadURL"]?.string else {
            throw YxiOSError.message(serverMessage(json, fallback: "123云盘：获取下载地址失败（code=\(code)）"))
        }

        // §5.4 解码
        var current = decodeDirectURL(rawURL)
        // 跟随跳转最多 5 跳
        for _ in 0..<5 {
            var headReq = URLRequest(url: URL(string: current)!)
            headReq.setValue("https://yun.123pan.cn/", forHTTPHeaderField: "Referer")
            headReq.setValue(dartUA, forHTTPHeaderField: "User-Agent")
            let r = try await HTTP.send(headReq)
            let len = r.response.expectedContentLength
            let prefix = r.data.prefix(1)
            if len <= 8192, let first = prefix.first, first == UInt8(ascii: "{"),
               let j = JSON.parse(r.data),
               let redirect = j["data"]?["redirect_url"]?.string, !redirect.isEmpty {
                current = redirect
            } else {
                break
            }
        }

        // 下载头：与 Android 版一致——必须用浏览器 UA（WEB_UA），Dart UA 会被 CDN 拒绝或返回 HTML 错误页
        let downloadHeaders: [String: String] = [
            "Referer": "https://yun.123pan.cn/",
            "User-Agent": webUA
        ]
        guard let url = URL(string: current) else {
            throw YxiOSError.message("123云盘：直链无效")
        }
        return ResolvedDirectURL(url: url, headers: downloadHeaders)
    }

    private func decodeDirectURL(_ raw: String) -> String {
        if !raw.contains("://") {
            return Base64Tool.decodeString(raw) ?? raw
        }
        if let range = raw.range(of: "params=") {
            var seg = String(raw[range.upperBound...])
            if let amp = seg.firstIndex(of: "&") {
                seg = String(seg[..<amp])
            }
            if let decoded = Base64Tool.decodeURL(seg) {
                return decoded
            }
        }
        return raw
    }
}

// MARK: - 迅雷 XUNLEI

final class XunleiClient: PlatformClient, DirectURLProvider, @unchecked Sendable {

    static let shared = XunleiClient()

    private let panBase = "https://api-pan.xunlei.com"
    private let webUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

    private let authBox = Protected<PlatformAuth?>(nil)
    private let downloadHeadersBox = Protected<[String: String]>([:])
    private let passTokenCache = Protected<[String: String]>([:])
    private let deviceIDBox = Protected<String>("")

    let platform: Platform = .xunlei
    var requiresLogin: Bool { false }

    private init() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "xl_device_id"), !existing.isEmpty {
            deviceIDBox.write(existing)
        } else {
            var s = ""
            for _ in 0..<32 { s.append("0123456789abcdef".randomElement()!) }
            deviceIDBox.write(s)
            defaults.set(s, forKey: "xl_device_id")
        }
    }

    func setAuth(_ auth: PlatformAuth?) { authBox.write(auth) }

    private var token: String? { authBox.read()?.token }

    private func applyCommonHeaders(_ req: inout URLRequest, auth: Bool) {
        req.setValue(webUA, forHTTPHeaderField: "User-Agent")
        req.setValue(deviceIDBox.read(), forHTTPHeaderField: "X-Device-Id")
        req.setValue("8.31.0.9726", forHTTPHeaderField: "X-Client-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://pan.xunlei.com", forHTTPHeaderField: "Origin")
        req.setValue("https://pan.xunlei.com/", forHTTPHeaderField: "Referer")
        if auth, let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
    }

    func resolveShare(_ info: ShareInfo) async throws -> [FileEntry] {
        let q = URLEncoder.query(items: [
            "share_id": info.shareID,
            "pass_code": info.password ?? "",
            "limit": "100", "page_token": "",
            "thumbnail_size": "SIZE_SMALL"
        ])
        var req = URLRequest(url: URL(string: panBase + "/drive/v1/share?" + q)!)
        req.httpMethod = "GET"
        applyCommonHeaders(&req, auth: false) // 游客：不带 Authorization

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("迅雷：分享解析失败")
        }
        let status = json["data"]?["share_status"]?.string
        switch status {
        case "PASS_CODE_EMPTY": throw YxiOSError.message("该分享需要提取码")
        case "PASS_CODE_ERROR": throw YxiOSError.message("提取码错误")
        case "PASS_CODE_NEED": throw YxiOSError.message("请输入提取码")
        default: break
        }
        if let token = json["data"]?["pass_code_token"]?.string {
            passTokenCache.mutate { $0[info.shareID] = token }
        }
        guard let files = json["data"]?["files"]?.array else { return [] }
        return mapFiles(files, parent: nil)
    }

    func listChildren(_ dirID: String, of info: ShareInfo) async throws -> [FileEntry] {
        let passToken = passTokenCache.read()[info.shareID] ?? ""
        let q = URLEncoder.query(items: [
            "share_id": info.shareID,
            "parent_id": dirID,
            "pass_code_token": passToken,
            "limit": "100", "page_token": "",
            "thumbnail_size": "SIZE_SMALL"
        ])
        var req = URLRequest(url: URL(string: panBase + "/drive/v1/share/detail?" + q)!)
        req.httpMethod = "GET"
        applyCommonHeaders(&req, auth: false)

        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("迅雷：目录解析失败")
        }
        guard let files = json["data"]?["files"]?.array else { return [] }
        return mapFiles(files, parent: dirID)
    }

    private func mapFiles(_ files: [JSON], parent: String?) -> [FileEntry] {
        var out: [FileEntry] = []
        for f in files {
            guard let id = f["id"]?.string else { continue }
            let name = f["name"]?.string ?? ""
            let size = f["size"]?.int64 ?? 0
            let kind = f["kind"]?.string ?? ""
            let isDir = kind == "drive#folder"
            out.append(FileEntry(id: id, name: name, size: size, isDirectory: isDir,
                                 parentID: parent, downloadURL: nil))
        }
        return out
    }

    func getDirectURL(for file: FileEntry, share: ShareInfo) async throws -> URL {
        return try await directDownloadURL(for: file, share: share).url
    }

    func directDownloadURL(for file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL {
        let result = try await resolveDownloadURL(file: file, share: share)
        downloadHeadersBox.write(result.headers)
        return result
    }

    private func resolveDownloadURL(file: FileEntry, share: ShareInfo) async throws -> ResolvedDirectURL {
        guard token != nil else {
            throw YxiOSError.message("迅雷：取分享文件直链需要登录（本版本仅支持游客解析分享列表）")
        }
        let passToken = passTokenCache.read()[share.shareID] ?? ""
        // 1. 转存到个人盘
        var req = URLRequest(url: URL(string: panBase + "/drive/v1/share/restore")!)
        req.httpMethod = "POST"
        applyCommonHeaders(&req, auth: true)
        let body: [String: Any] = [
            "share_id": share.shareID,
            "pass_code_token": passToken,
            "parent_id": "0",
            "ancestor_ids": [],
            "file_ids": [file.id],
            "specify_parent_id": true
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        let resp = try await HTTP.send(req)
        guard let json = JSON.parse(resp.data) else {
            throw YxiOSError.message("迅雷：转存响应解析失败")
        }
        // trace_file_ids 是 JSON 字符串 {"分享id":"转存后新id"}
        var newFileID: String?
        if let trace = json["params"]?["trace_file_ids"]?.string,
           let traceData = trace.data(using: .utf8),
           let traceObj = try? JSONSerialization.jsonObject(with: traceData) as? [String: Any] {
            newFileID = traceObj.values.first as? String
        }
        guard let fid = newFileID else {
            throw YxiOSError.message(serverMessage(json, fallback: "迅雷：转存失败，无法获取新文件ID"))
        }
        // 2. 文件详情取直链
        let fileURL = panBase + "/drive/v1/files/\(fid)?_magic=2021&usage=PLAY&thumbnail_size=SIZE_LARGE&with=hdr10&with=subtitle_files&with=task&with=public_share_tag"
        var freq = URLRequest(url: URL(string: fileURL)!)
        freq.httpMethod = "GET"
        applyCommonHeaders(&freq, auth: true)
        let fresp = try await HTTP.send(freq)
        guard let fjson = JSON.parse(fresp.data) else {
            throw YxiOSError.message("迅雷：文件详情解析失败")
        }
        let url = fjson["data"]?["links"]?["application/octet-stream"]?["url"]?.string
            ?? fjson["data"]?["web_content_link"]?.string
        guard let u = url, let finalURL = URL(string: u) else {
            throw YxiOSError.message(serverMessage(fjson, fallback: "迅雷：获取下载直链失败"))
        }
        let headers: [String: String] = [
            "User-Agent": webUA,
            "Referer": "https://pan.xunlei.com/"
        ]
        return ResolvedDirectURL(url: finalURL, headers: headers)
    }
}

// MARK: - 服务端错误信息透传

/// 从常见字段（message / err_msg / show_msg / error / msg）抽取中文错误描述。
func serverMessage(_ json: JSON?, fallback: String) -> String {
    guard let json = json else { return fallback }
    for key in ["message", "err_msg", "show_msg", "error", "msg", "errorDesc"] {
        if let s = json[key]?.string, !s.isEmpty {
            return s
        }
    }
    return fallback
}
