# HermesMobile

[Hermes Agent](https://hermes-agent.nousresearch.com/) 的 iOS 原生客戶端，透過 [hermes-webui](https://github.com/nesquena/hermes-webui) 暴露的 HTTP/SSE API，經 Tailscale 連線到 Mac Mini M4 主機。

| 項目 | 值 |
|------|---|
| 階段 | V1 MVP（F-01 ~ F-04 已 scaffold，待 Mac 端驗證） |
| 平台 | iOS 17+（iPhone / iPad），不支援 macOS Catalyst |
| 結構 | SwiftPM library + 開發者自建的 thin iOS App target |
| 依賴 | `swift-markdown-ui`（其餘用 URLSession 自幹） |
| 部署 | TestFlight / Ad-hoc，不上架 App Store |
| 使用者 | 單使用者（Anderson 個人用） |

> ⚠️ V1 MVP 的 source code 目前在 `claude/initial-project-setup-51stT` branch 上，main 受保護無法直接 push。請在 GitHub 開 PR 將該 branch 合併回 main，或在本機 `git merge --ff-only origin/claude/initial-project-setup-51stT`。

---

## 文件導覽

| 想知道什麼 | 看哪份 |
|------------|--------|
| 開發守則、絕對規則（RULE-1 ~ RULE-iOS-C）、命名規範、commit 格式 | [`CLAUDE.md`](./CLAUDE.md) |
| 功能需求（F-XX）、非功能需求、API endpoint 表、UI/UX 規範、路線圖 | [`SRS.md`](./SRS.md) |
| 在 Xcode 怎麼設定 / build / 上 TestFlight | [`SRS.md` 附錄 B](./SRS.md#附錄-bxcode-專案設定與建置指南) |
| 每個 endpoint 的 request/response schema、SSE event 解析規則、邊界情境 E-01 ~ E-14 | [`SPEC.md`](./SPEC.md) |
| 模組分層、sequence 圖、為何選 SwiftPM / 為何不用第三方 SSE library 等 ADR | [`DESIGN.md`](./DESIGN.md) |

任何貢獻者進入專案前，**至少**讀完 `CLAUDE.md` 第 2 章（絕對規則）。

---

## Repository 結構

```
HermesGo/
├── README.md              ← 本檔
├── CLAUDE.md              ← Claude Code 與貢獻者守則
├── SRS.md                 ← 需求 + Xcode setup 指南
├── SPEC.md                ← API 與行為套約
├── DESIGN.md              ← 架構與 ADR
├── Package.swift          ← SwiftPM 設定（iOS 17+）
├── Sources/HermesMobile/  ← Library 全部 source
│   ├── App/               ← RootView、AppState
│   ├── Core/              ← Network / Models / Storage / Utilities
│   ├── DesignSystem/      ← Colors / Typography / PrivacyShield
│   └── Features/          ← Setup / SessionList / Chat / Settings
└── Tests/HermesMobileTests/
    ├── App/               ← AppStateTests（RULE-6）
    ├── Core/              ← API / SSE / Keychain
    ├── Features/          ← Chat / SessionList（RULE-1、RULE-9）
    └── Mocks/             ← MockAPIClient
```

完整 type → file 索引請看 [`DESIGN.md` §3](./DESIGN.md#3-component-map)。

---

## Quick start

### 前置

- macOS 14+ 與 Xcode 15+
- Apple Developer 帳號（實機 / TestFlight 需要）
- Mac Mini M4 上跑著 hermes-webui（`HERMES_WEBUI_PASSWORD` 已設）
- iPhone / iPad 與 Mac Mini 在同一個 Tailscale tailnet

### 取得 source

```bash
git clone http://your-host/AmpereHu/HermesGo.git
cd HermesGo

# V1 MVP commit 在 feature branch（main 還未合併）
git fetch origin claude/initial-project-setup-51stT
git checkout -b mvp origin/claude/initial-project-setup-51stT
```

### 跑單元測試

```bash
xcodebuild test \
  -scheme HermesMobile \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

或在 Xcode 內 `⌘+U`。

### 跑成 iOS App

詳細步驟請看 [`SRS.md` 附錄 B](./SRS.md#附錄-bxcode-專案設定與建置指南)。摘要：

1. `open Package.swift` 用 Xcode 開啟
2. 另外建立 iOS App target，把這個 local package 加進去
3. App 的 `@main` 改寫成：
   ```swift
   import SwiftUI
   import HermesMobile

   @main
   struct HermesMobileAppEntry: App {
       var body: some Scene {
           WindowGroup { RootView() }
       }
   }
   ```
4. Info.plist 加 `NSAppTransportSecurity` 對 `ts.net` 的例外（SRS §9.3）
5. ⌘+R

---

## 絕對規則（必讀）

直接 copy 自 [`CLAUDE.md` §2](./CLAUDE.md#2-絕對規則never-violate)，避免遺漏：

- **RULE-1**: 刪除 session 絕不自動建立新 session
- **RULE-5**: 任何 `await` 前必須捕獲 `activeSessionId`
- **RULE-6**: Boot 流程絕不自動建立 session
- **RULE-9**: Approval 用 `pattern_keys`（複數）
- **RULE-iOS-A**: Keychain only for secrets（密碼絕不存 `UserDefaults`）
- **RULE-iOS-B**: SSE 解析必須處理 heartbeat 與不完整 chunk
- **RULE-iOS-C**: 不引入第三方 HTTP / SSE library

每條 RULE 在 [`SPEC.md` §4.5](./SPEC.md#45-rule-對應總表) 都有對應實作位置與測試。

---

## 開發節奏

| 時機 | 該做的事 |
|------|---------|
| 新功能 | 在 `Features/{Name}/` 開資料夾，View + ViewModel 配對；先寫 Model → ViewModel → View |
| 改 ViewModel | `⌘+U` 確認沒違反 RULE-1 ~ RULE-iOS-C |
| 改 SSE | 跑 `SSEClientTests` |
| 改 Setup / Session 流程 | 跑 `AppStateTests` + `SessionListViewModelTests` |
| 引入新依賴 | 加 ADR 到 `DESIGN.md`，更新 `CLAUDE.md` 第 1 章 |
| 對接新 endpoint | 更新 `SPEC.md` §2 + `Endpoints.swift` + `APIClient.swift` |
| 發現新 Critical Rule | 加到 `CLAUDE.md` §2 與 `SPEC.md` §4.5 |

Commit 訊息格式：`<type>(<scope>): <subject>`，例如 `feat(chat): implement SSE token streaming`（詳見 `CLAUDE.md` §6.3）。

---

## 隱私 / 安全

- 所有流量走 Tailscale tailnet，端到端 WireGuard 加密。
- 密碼與 cookie 存 Keychain（`afterFirstUnlockThisDeviceOnly`），絕不寫進 `UserDefaults` 或 log。
- App 進背景時整個畫面以 `PrivacyShield` modifier 模糊化。
- 無 telemetry、無第三方分析 SDK。
- ATS 例外只開 `*.ts.net`（Tailscale MagicDNS），**禁止** `NSAllowsArbitraryLoads = true`。

---

## License

私人專案，未公開授權；所有權利保留。
