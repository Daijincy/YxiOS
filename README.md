# YxiOS

YxiOS 是 [YunX](https://github.com/CYQawa/YunX) 的 iOS 移植版，以 **AGPL-3.0** 协议开源。

## 功能范围

- 网盘分享链接解析：夸克 / 百度网盘 / 123 网盘 / 迅雷等
- 解析结果的下载与下载管理

> 本工程当前为骨架阶段，尚未包含 Swift 业务源码；接口约定见 [`docs/API-CONTRACT.md`](docs/API-CONTRACT.md)（冻结契约）。

## 本地构建

依赖 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate          # 根据 project.yml 生成 YxiOS.xcodeproj
open YxiOS.xcodeproj       # 或直接 xcodebuild
```

命令行构建（模拟器 / 设备）：

```bash
xcodebuild -project YxiOS.xcodeproj -scheme YxiOS -configuration Debug build
```

## GitHub Actions 云构建

推送 `main` 分支（或打 `v*` 标签、手动触发）即触发 [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)：

- Runner：`macos-15`，自动选择 Xcode、安装 XcodeGen 并 `xcodegen generate`。
- **已配置签名 secrets**（`DEVELOPER_CERTIFICATE` 等）时：执行 `archive` + `exportArchive`，产出签名 IPA。
- **未配置签名 secrets** 时：以 `CODE_SIGNING_ALLOWED=NO` 构建，打包为未签名 IPA（artifact 名 `YxiOS-IPA`，文件 `YxiOS-unsigned.ipa`）。
  该未签名包需越狱环境或自行重签名（如 AltStore / 自签证书）后才能安装。

## 免责声明

本项目仅供学习与技术研究使用。分享链接的解析、下载行为请遵守对应网盘服务条款与当地法律法规；由此产生的任何责任由使用者自行承担，与本项目作者无关。
