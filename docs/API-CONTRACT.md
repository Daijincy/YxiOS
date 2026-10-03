# YxiOS Swift API 契约（冻结版 v1）

> 本文档是核心层(Subagent C)与界面层(Subagent D)的共同编程依据，双方必须严格按此签名实现/调用。
> 核心层只允许新增文件与内部实现细节；界面层只能调用本契约中声明的 API。禁止任何一方修改本契约。

## 0. 工程约定

- 目标平台 iOS 17.0+，纯 SwiftUI + Foundation + WebKit + UIKit(仅分享/文档预览需要)。**零第三方依赖**（无 SPM 外部包、无 CocoaPods）。
- 全部源码位于 `YxiOS/YxiOS/` 目录下，按目录划分：`Models/`、`Services/`、`Views/`、`Utils/`、`YxiOSApp.swift`、`Info.plist`。
- 所有网络请求用 `URLSession.shared`（或带自定义 User-Agent 的 `URLSessionConfiguration` 会话），并发线程安全由核心层负责。
- 持久化：下载任务用 JSON 文件存 `Documents/`（Codable），登录态用 `UserDefaults`。

## 1. Models（Models/SharedModels.swift，核心层实现，界面层只读）

```swift
public enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
    case quark, baidu, pan123, xunlei
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .quark: return "夸克网盘"
        case .baidu: return "百度网盘"
        case .pan123: return "123云盘"
        case .xunlei: return "迅雷云盘"
        }
    }
}

public struct ShareInfo: Codable, Equatable, Sendable {
    public let platform: Platform
    public let shareID: String      // 分享链接中的资源标识（pwd 之前的 key）
    public let password: String?    // 提取码，可能为 nil
    public let rawURL: String       // 用户粘贴的原始链接
    public init(platform: Platform, shareID: String, password: String?, rawURL: String)
}

public struct FileEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String          // 平台文件标识（目录/文件通用）
    public let name: String
    public let size: Int64         // 字节；目录为 0
    public let isDirectory: Bool
    public let parentID: String?   // 目录层级用；根层为 nil
    public let downloadURL: String? // 直链（可能为 nil，需 getDirectURL 获取）
    public init(id: String, name: String, size: Int64, isDirectory: Bool,
                parentID: String?, downloadURL: String?)
}

public enum TaskStatus: String, Codable, Sendable {
    case queued, downloading, paused, completed, failed
}

public struct DownloadTask: Identifiable, Codable, Sendable {
    public let id: UUID
    public let platform: Platform
    public let fileName: String
    public let fileID: String
    public var status: TaskStatus
    public var progress: Double          // 0.0...1.0
    public var downloadedBytes: Int64
    public var totalBytes: Int64
    public var errorMessage: String?
    public let createdAt: Date
    public var localPath: String?        // 完成后 Documents/Downloads/ 下的相对路径
    public init(id: UUID, platform: Platform, fileName: String, fileID: String,
                status: TaskStatus, progress: Double, downloadedBytes: Int64,
                totalBytes: Int64, errorMessage: String?, createdAt: Date, localPath: String?)
}
```

## 2. 分享链接解析（Services/ShareLinkParser.swift，核心层实现）

```swift
public enum ShareLinkParser {
    /// 输入任意文本，识别出第一个网盘分享链接并解析；识别失败返回 nil。
    /// 支持：夸克(quark.cn/s/xxx)、百度(pan.baidu.com/s/xxx 提取码)、123(www.123pan.com/s/xxx)、迅雷(pan.xunlei.com/s/xxx)。
    public static func parse(_ text: String) -> ShareInfo?
    public static func detectPlatform(from urlString: String) -> Platform?
}
```

## 3. 平台客户端（Services/PlatformClient.swift + Services/PlatformClients.swift，核心层实现）

```swift
public protocol PlatformClient: Sendable {
    var platform: Platform { get }
    /// 该平台是否必须登录才能解析/取直链
    var requiresLogin: Bool { get }
    /// 解析分享链接 → 返回根目录文件列表（尽量返回带直链的文件；目录项 downloadURL 为 nil）
    func resolveShare(_ info: ShareInfo) async throws -> [FileEntry]
    /// 目录展开：给定目录项 id，返回子文件列表
    func listChildren(_ dirID: String, of info: ShareInfo) async throws -> [FileEntry]
    /// 获取单个文件的直链（若 FileEntry.downloadURL 已有值可直接返回）
    func getDirectURL(for file: FileEntry, share: ShareInfo) async throws -> URL
    /// 平台标识（登录状态变更后用）
    func setAuth(_ auth: PlatformAuth?)
}

/// 各平台登录态（由界面层经 LoginSession 写入，核心层读取）
public struct PlatformAuth: Codable, Equatable, Sendable {
    public var cookie: String?          // quark/baidu 用（"k1=v1; k2=v2"）
    public var token: String?           // pan123 JWT / xunlei 用
    public var extra: [String: String]  // 其他字段（uid 等）
    public init(cookie: String?, token: String?, extra: [String: String])
}

public enum PlatformRegistry {
    public static func client(for platform: Platform) -> PlatformClient
}
```

## 4. 登录会话（Services/LoginSession.swift，核心层实现，界面层读写）

```swift
@MainActor
public final class LoginSession: ObservableObject {
    public static let shared: LoginSession
    /// 界面层 WebView 登录成功后调用，会持久化到 UserDefaults
    public func setAuth(_ auth: PlatformAuth, for platform: Platform)
    public func auth(for platform: Platform) -> PlatformAuth?
    public func clearAuth(for platform: Platform)
}
```

## 5. 下载管理器（Services/DownloadManager.swift，核心层实现）

```swift
@MainActor
public final class DownloadManager: ObservableObject {
    public static let shared: DownloadManager
    @Published public private(set) var tasks: [DownloadTask]

    /// 新增下载任务（file 的 downloadURL 为 nil 时，内部用 platform client 取直链）
    public func addDownload(platform: Platform, share: ShareInfo, file: FileEntry) async
    /// 全部任务（含历史完成/失败）持久化到 Documents/Downloads/tasks.json，每次变更自动保存
    public func pause(_ id: UUID)
    public func resume(_ id: UUID)
    public func remove(_ id: UUID)            // 删除任务并清理未完成的分片
    public func retry(_ id: UUID)
    public func task(with id: UUID) -> DownloadTask?
    public func fileURL(for task: DownloadTask) -> URL?  // 完成后文件位置
}
```

### 下载引擎规格（核心层必须实现，界面层不关心细节）
- 使用 `URLSession`，对每个任务发起 `HEAD`（或首个分片 `GET` 的响应头）取 `Content-Length` 与 `Accept-Ranges`；支持 Range 则分片并发下载，**每任务分片数 = min(4, 总大小/8MB 向上取整)，最小 1 片**。
- 分片文件：`Documents/Downloads/<uuid>/part.<i>`；全部完成后按偏移拼接为 `Documents/Downloads/<fileName>`，删除分片。断点续传：启动/恢复时检查已存在分片大小，剩余部分以 `Range: bytes=<offset>-<end>` 继续请求。
- 暂停：cancel 未完成分片的 dataTask（保留分片文件）；恢复：重新发起剩余 Range；删除：删除整个任务目录。
- 进度：`downloadedBytes = Σ 已写分片字节`，`progress = downloadedBytes / totalBytes`。
- 线程安全：DownloadManager 是 `@MainActor`，内部写文件/网络回调用 `Task`/`await`，避免数据竞争。
- 直链可能要求相同 User-Agent/Referer，核心层在取直链时记录 UA 与 Referer 并在下载请求头中携带。

## 6. 存储（Services/Storage.swift，核心层实现）

```swift
public enum Storage {
    public static var documentsDirectory: URL
    public static var downloadsDirectory: URL      // Documents/Downloads/
    public static func saveTasks(_ tasks: [DownloadTask])
    public static func loadTasks() -> [DownloadTask]
    public static func taskDirectory(for task: DownloadTask) -> URL
}
```

## 7. 界面层（Subagent D）必须实现

- `YxiOSApp.swift`：`@main` 结构体，`WindowGroup { RootView() }`，环境注入 `DownloadManager.shared`、`LoginSession.shared`。
- `Views/RootView.swift`：`TabView` 三页：解析(link)、下载(arrow.down.circle)、设置(gear)。
- `Views/ResolveView.swift`：输入框粘贴分享链接+提取码 → `ShareLinkParser.parse` → 平台识别 → 调 client 解析文件列表 → 展示文件树（可展开目录）→ 勾选/选择文件加入下载。未登录且需要登录的平台显示「去登录」入口。
- `Views/LoginView.swift`：夸克/百度用 `WKWebView`（用户手动登录后从 `HTTPCookieStorage` 抓取 Cookie 写入 `LoginSession`）；123 用账号密码表单换取 token（调 PlatformClient 相关接口，界面层可调用 core 提供的 `Pan123Auth` 登录方法）；迅雷显示「仅解析直链」提示。
- `Views/FileListView.swift`：文件列表/目录展开。
- `Views/DownloadsView.swift`：`DownloadManager.tasks` 列表：文件名、平台、进度条、速度/大小文案、状态；暂停/继续/删除/重试按钮；完成后点击调起分享面板（`UIActivityViewController`，通过 UIViewControllerRepresentable 包装）。
- `Views/SettingsView.swift`：关于（版本、AGPL-3.0 声明、原项目 YunX 链接 https://github.com/CYQawa/YunX 、本项目 GitHub 仓库链接、免责声明）。
- `Views/Components/LiquidGlass.swift`：液态玻璃观感组件：`.ultraThinMaterial` 圆角卡片容器 `GlassCard`、`GlassButton`、列表分隔样式；iOS 26+ 可用 `glassEffect`，低版本用 `Material` 近似（`if #available(iOS 26.0, *)`）。全局配色克制（深色为主、高光描边、细腻 spring 动效）。
- 所有界面文案中文。

## 8. 硬性约束（双方都遵守）

1. 不使用任何第三方库；不使用 SwiftData/CoreData（用 JSON 持久化）。
2. 代码必须**一次编译通过**的保守写法：不用未声明的 API、不用 Swift 6 并发严格模式特性（保持 SWIFT_VERSION 5.0 兼容）、避免 `@preconcurrency` 等易错写法；尽量用显式 `public`/`private`。
3. 文件写入目录统一走 `Storage`。
4. 所有错误以中文 `errorMessage` 呈现，核心层抛 `YxiOSError`（`LocalizedError`）。
5. 目录 `YxiOS/YxiOS/Services/` 下文件由核心层独占；`YxiOS/YxiOS/Views/` 与 `YxiOSApp.swift` 由界面层独占；`Models/` 以契约文件为准（核心层写）。**双方不得修改对方文件**。
