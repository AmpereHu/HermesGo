# HermesMobile — 需求與規格文件 (SRS)

> Version: 0.1.0
> Last updated: 2026-05-10
> Author: Anderson
> Status: Draft

---

## 1. 文件目的與範圍

本文件定義 **HermesMobile** iOS 原生應用程式的需求、架構與技術規格。HermesMobile 是 [Hermes Agent](https://hermes-agent.nousresearch.com/) 的行動裝置客戶端，透過 [hermes-webui](https://github.com/nesquena/hermes-webui) 暴露的 HTTP/SSE API，經由 Tailscale 私有網路連線至使用者主機（Mac Mini M4）執行的 Hermes 代理程式。

本文件涵蓋：
- 功能需求（Functional Requirements）
- 非功能需求（Non-Functional Requirements）
- 系統架構與技術選型
- API 介面契約（Contract）
- 安全性、網路、背景處理策略
- MVP 與後續版本路線圖

本文件**不涵蓋**：
- Hermes Agent 本身的安裝與設定（參見上游文件）
- hermes-webui 後端的開發（直接消費其既有 API）
- Tailscale 帳號與 ACL 管理（屬於部署面）

---

## 2. 系統概觀

### 2.1 高層架構

```
┌─────────────────┐                ┌──────────────────────────┐
│   iPhone /      │                │   Mac Mini M4 (Server)   │
│   iPad          │                │                          │
│                 │                │  ┌────────────────────┐  │
│  HermesMobile   │   HTTPS/SSE    │  │  hermes-webui      │  │
│  (SwiftUI)      │ ◄─────────────►│  │  (Python, :8787)   │  │
│                 │                │  └─────────┬──────────┘  │
│  Tailscale      │                │            │             │
│  iOS Client     │                │  ┌─────────▼──────────┐  │
└────────┬────────┘                │  │  Hermes Agent      │  │
         │                         │  │  (run_agent)       │  │
         │  Tailnet (WireGuard)    │  └────────────────────┘  │
         └────────────────────────►│                          │
                                   │  Tailscale Daemon        │
                                   └──────────────────────────┘
```

### 2.2 關鍵設計決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| 連線方式 | Tailscale tailnet | 已有的 Mac Mini M4 server 可直接加入 tailnet；比 SSH tunnel 更穩定，行動網路友善；端到端加密由 WireGuard 保證 |
| 串流協定 | Server-Sent Events (SSE) | hermes-webui 原生支援；iOS `URLSession.bytes(for:)` 可直接消費；單向夠用 |
| UI 框架 | SwiftUI | iOS 17+ 原生最佳體驗；`NavigationSplitView` 對應上游三欄式佈局；iPad 自動適配 |
| 並行模型 | Swift Concurrency (`async/await`, `AsyncStream`) | 處理 SSE 與 API 呼叫的最佳實踐；無第三方依賴 |
| 狀態管理 | `@Observable` (Observation framework) | iOS 17+ 取代 `ObservableObject`，效能與語法更佳 |
| 持久化 | SwiftData（V2） / `UserDefaults`（V1） | V1 僅儲存連線設定與最後 session id；V2 加入本地離線快取 |
| 認證 | hermes-webui 內建密碼 + cookie | 使用上游 `HERMES_WEBUI_PASSWORD` 機制，避免重複造輪 |

### 2.3 不在範圍內

- 直接呼叫 Hermes Agent Python 模組（一律透過 hermes-webui 中介）
- 在 iOS 端執行 LLM（純客戶端，所有運算在 server）
- 多使用者協作（單使用者、單裝置假設）
- Apple Watch / macOS Catalyst 版本

---

## 3. 利害關係人與使用情境

### 3.1 主要使用者

**Anderson**（單一使用者）：BenQ AB DentCare 產品經理，需要在外出、會議、通勤時延續主機上的 Hermes 工作流（regulatory translation, supplier emails, 程式碼諮詢）。

### 3.2 核心使用情境

**US-01**: 通勤時延續對話
> 我在 Mac 上開了一個 session 處理 Meisinger 信件草稿，下班搭捷運時想用 iPhone 繼續修，希望看到完整對話歷史並能直接接著傳訊息。

**US-02**: 會議中快速查詢
> 會議中突然需要一段中翻英，打開 app 開新 session、貼中文、5 秒內看到串流回應。

**US-03**: 監看背景任務
> 主機上跑了 cron job 自動生成週報，我想在 iPad 上即時看到完成通知與輸出（V2）。

**US-04**: 危險指令確認
> Agent 要執行 `rm -rf` 類指令時，要在手機跳出 approval card，我能選 once / session / always / deny。

---

## 4. 功能需求

### 4.1 V1（MVP）功能清單

#### F-01 連線設定 (Setup)

| ID | 需求 | 優先級 |
|----|------|--------|
| F-01.1 | 首次啟動顯示連線設定頁，輸入 Server URL（如 `http://100.x.x.x:8787`） | Must |
| F-01.2 | 輸入認證密碼（對應 `HERMES_WEBUI_PASSWORD`） | Must |
| F-01.3 | 「測試連線」按鈕：呼叫 `GET /health` 並顯示 `status` 與 `sessions` 計數 | Must |
| F-01.4 | 連線資訊存入 Keychain，密碼絕不存 `UserDefaults` | Must |
| F-01.5 | 設定頁可從 app 內的 Settings 重新進入修改 | Must |

#### F-02 Session 管理

| ID | 需求 | 優先級 |
|----|------|--------|
| F-02.1 | 啟動後呼叫 `GET /api/sessions` 取得 session 列表，依 `updated_at` 倒序顯示 | Must |
| F-02.2 | Session list cell 顯示：title、最後更新時間（相對時間格式如「2 hours ago」）、model 標籤 | Must |
| F-02.3 | 「+」按鈕新建 session：`POST /api/session/new` | Must |
| F-02.4 | 點擊 session：`GET /api/session?session_id=X` 載入完整訊息歷史 | Must |
| F-02.5 | 長按或 swipe action：刪除 session（`POST /api/session/delete`） | Must |
| F-02.6 | 刪除規則嚴格遵循上游 RULE-1：刪除 active session 後若還有其他 session 則切換至最新一個，否則顯示空狀態，**絕不**自動建立新 session | Must |
| F-02.7 | Pull-to-refresh 重新整理 session list | Should |
| F-02.8 | Session 重新命名（inline edit 或 detail page）：`POST /api/session/rename` | Should |
| F-02.9 | 搜尋 session：`GET /api/sessions/search?q=...` | Could |

#### F-03 Chat 對話

| ID | 需求 | 優先級 |
|----|------|--------|
| F-03.1 | Chat 畫面顯示 session.messages，user / assistant 訊息以氣泡區分 | Must |
| F-03.2 | 底部 composer：textarea（自動高度調整）、Send 按鈕 | Must |
| F-03.3 | Send 流程：`POST /api/chat/start` 取得 `stream_id`，立刻開啟 SSE `GET /api/chat/stream?stream_id=X` | Must |
| F-03.4 | SSE token event：累積 assistant 訊息文字，逐字顯示（streaming） | Must |
| F-03.5 | SSE tool event：在訊息流中顯示「Running {tool_name}...」狀態列 | Must |
| F-03.6 | SSE done event：以 server 回傳的 messages 為準，完整覆蓋本地狀態 | Must |
| F-03.7 | SSE error event：顯示錯誤訊息，解除 busy 狀態 | Must |
| F-03.8 | Markdown 渲染：標題、粗體、斜體、code block、inline code、清單 | Must |
| F-03.9 | Code block 顯示語法高亮（使用 `Splash` 或 `Highlightr`） | Should |
| F-03.10 | 訊息時間戳（hover/long-press 顯示完整日期） | Should |
| F-03.11 | 複製訊息（long-press menu） | Should |
| F-03.12 | 訊息送出後，若使用者切換 session，回到原 session 仍能看到 in-flight 狀態（對應上游 INFLIGHT 機制） | Must |
| F-03.13 | Send 按鈕在 busy 期間 disabled | Must |
| F-03.14 | Cancel 按鈕：呼叫 `POST /api/chat/cancel`（若上游有支援；否則僅關閉 SSE 連線） | Should |

#### F-04 Approval Card（危險指令確認）

| ID | 需求 | 優先級 |
|----|------|--------|
| F-04.1 | SSE approval event 觸發時，在 chat 上方顯示 approval card | Must |
| F-04.2 | Card 內容：command 文字、description、pattern_keys 列表 | Must |
| F-04.3 | 四個選項按鈕：Allow Once / Session / Always / Deny | Must |
| F-04.4 | 點擊後 `POST /api/approval/respond` 並隱藏 card | Must |
| F-04.5 | 若 SSE 連線中斷，啟動 polling fallback：每 1500ms `GET /api/approval/pending` | Must |
| F-04.6 | App 從背景回前景時，立即檢查 `GET /api/approval/pending` | Must |

#### F-05 模型選擇

| ID | 需求 | 優先級 |
|----|------|--------|
| F-05.1 | 從 `GET /api/sessions` 或 session detail 取得當前 model | Must |
| F-05.2 | Model picker：列出 hermes-webui 配置的可用 models | Should |
| F-05.3 | 切換 model：`POST /api/session/update {model: ...}` | Should |

### 4.2 V2 規劃功能（不在 MVP 內）

- F-06 Workspace 檔案瀏覽（list、preview text/markdown/image）
- F-07 Tasks 面板（cron 列表、執行歷史、完成通知）
- F-08 Skills 面板
- F-09 Memory 面板（讀取 MEMORY.md / USER.md）
- F-10 檔案上傳（從 Photos / Files app）
- F-11 Push 通知（Tasks 完成時，需 server 端額外實作）
- F-12 離線快取（SwiftData 儲存 sessions，無連線時可瀏覽歷史）
- F-13 訊息編輯重新生成（`POST /api/session/truncate`）
- F-14 訊息佇列（busy 時 send 自動排隊）

---

## 5. 非功能需求

### 5.1 效能

| 指標 | 目標 |
|------|------|
| 冷啟動到 session list 顯示 | < 1.5s（已有快取連線資訊時） |
| Send 訊息到第一個 token 顯示 | < 800ms（tailnet 內網延遲 + LLM TTFT） |
| Session 切換 | < 200ms（已快取訊息歷史時） |
| 訊息列表滾動 | 60fps，1000+ 訊息流暢 |

### 5.2 可靠性

- SSE 連線中斷時自動重連（exponential backoff: 1s → 2s → 4s → 8s，上限 30s）
- 重連時呼叫 `GET /api/chat/stream/status?stream_id=X` 確認 stream 狀態
- App 進背景超過 30 秒後回前景，視為 SSE 已斷，主動重連
- 所有網路請求 timeout 設定：一般 API 15s，SSE 不設 timeout（依賴 heartbeat）

### 5.3 安全性

- **Keychain only**：密碼、auth cookie 一律存 Keychain，accessibility 設為 `.afterFirstUnlockThisDeviceOnly`
- **App Transport Security**：預設僅允許 HTTPS；針對 Tailscale 內網 IP（`100.x.x.x`）需在 `Info.plist` 加入 `NSAppTransportSecurity` 例外（因 hermes-webui 預設 HTTP）
- **Cookie 處理**：SSE 與一般 API 共用 `URLSession`，自動帶 cookie
- **無分析、無 telemetry**：不接 Firebase / Crashlytics 等第三方 SDK
- **Background fetch 不洩漏**：app 切到背景時模糊化內容（`.privacySensitive()` modifier）

### 5.4 可用性

- 支援 Dynamic Type（使用者調整系統字級時 UI 自動適應）
- 支援 Dark Mode（與上游 dark theme 一致）
- 支援 VoiceOver（訊息、按鈕皆有 accessibility label）
- 支援橫向／直向、iPad 多工 split view

### 5.5 相容性

| 項目 | 規格 |
|------|------|
| 最低 iOS 版本 | iOS 17.0 |
| 目標裝置 | iPhone（必須）、iPad（必須）、Mac Catalyst（不支援） |
| Xcode 版本 | 15.0+ |
| Swift 版本 | 5.9+ |

---

## 6. 系統架構

### 6.1 模組結構

```
HermesMobile/
├── App/
│   └── HermesMobileApp.swift          # @main, 環境注入
├── Core/
│   ├── Network/
│   │   ├── APIClient.swift            # URLSession 包裝，cookie 處理
│   │   ├── SSEClient.swift            # SSE 解析器
│   │   ├── Endpoints.swift            # API 路徑定義
│   │   └── APIError.swift             # 錯誤型別
│   ├── Models/
│   │   ├── Session.swift              # Codable 對應 hermes-webui Session
│   │   ├── Message.swift              # role, content, timestamps
│   │   ├── ToolCall.swift             # 工具呼叫紀錄
│   │   ├── Approval.swift             # pending approval 結構
│   │   └── SSEEvent.swift             # token/tool/approval/done/error
│   ├── Storage/
│   │   ├── KeychainStore.swift        # 密碼 / cookie 持久化
│   │   └── Preferences.swift          # UserDefaults 包裝（server URL, last session）
│   └── Utilities/
│       ├── MarkdownRenderer.swift     # swift-markdown-ui 包裝
│       └── DateFormatters.swift
├── Features/
│   ├── Setup/
│   │   ├── SetupView.swift            # 首次連線設定頁
│   │   └── SetupViewModel.swift
│   ├── SessionList/
│   │   ├── SessionListView.swift
│   │   ├── SessionListViewModel.swift
│   │   └── SessionRowView.swift
│   ├── Chat/
│   │   ├── ChatView.swift
│   │   ├── ChatViewModel.swift        # 核心：SSE 訂閱、狀態管理
│   │   ├── MessageBubbleView.swift
│   │   ├── ComposerView.swift
│   │   ├── ApprovalCardView.swift
│   │   └── ToolCallView.swift
│   └── Settings/
│       ├── SettingsView.swift
│       └── SettingsViewModel.swift
├── DesignSystem/
│   ├── Colors.swift                   # 對應上游 dark theme
│   ├── Typography.swift
│   └── Components/                    # 可重用 UI 元件
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

### 6.2 狀態管理

使用 iOS 17 `@Observable` macro：

```swift
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var isStreaming: Bool = false
    var pendingApproval: Approval?
    var currentToolCall: ToolCall?
    var error: APIError?

    private var sseTask: Task<Void, Never>?
    private let api: APIClient
    // ...
}
```

ViewModel 注入方式：使用 `@Environment` 與 SwiftUI 的環境物件機制，避免 singleton。

### 6.3 SSE 處理流程

```swift
// SSEClient.swift 偽碼
func stream(streamId: String) -> AsyncThrowingStream<SSEEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            let (bytes, _) = try await urlSession.bytes(for: request)
            var buffer = ""
            for try await line in bytes.lines {
                if line.isEmpty {
                    // 空行 = event 結束
                    if let event = parseSSEBlock(buffer) {
                        continuation.yield(event)
                    }
                    buffer = ""
                } else {
                    buffer += line + "\n"
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

ChatViewModel 訂閱：

```swift
func send(_ text: String) async {
    let resp = try await api.startChat(sessionId: id, message: text)
    isStreaming = true

    sseTask = Task {
        do {
            for try await event in api.streamChat(streamId: resp.streamId) {
                await handle(event)
            }
        } catch {
            self.error = .streamFailed(error)
        }
        isStreaming = false
    }
}
```

### 6.4 背景處理策略

iOS 在 app 進入背景後會在約 30 秒內暫停網路活動。HermesMobile 採取以下策略：

1. 進入背景時：記錄 `lastStreamId` 與 `lastMessageTimestamp` 至 `UserDefaults`
2. SSE Task 不主動取消，讓系統自然結束
3. 回前景時：
   - 呼叫 `GET /api/chat/stream/status?stream_id=lastStreamId`
   - 若 `active: true`：重新開啟 SSE 連線
   - 若 `active: false`：呼叫 `GET /api/session?session_id=X` 取得完整最新訊息
4. 同時呼叫 `GET /api/approval/pending` 檢查是否有待處理 approval

不使用 Background Modes 中的 `fetch` 或 `processing`，因為：
- 不需要無使用者互動下的更新
- 避免 App Store 審查理由不充分被拒
- V2 若需 push 通知，由 server 端透過 APNs 推送

---

## 7. API 介面契約

### 7.1 Base URL

```
http://{tailscale-ip}:8787
```

例：`http://100.64.0.5:8787`

### 7.2 認證

若 server 啟用 `HERMES_WEBUI_PASSWORD`：

```
POST /api/auth/login
Content-Type: application/json

{ "password": "..." }

→ 200 OK, Set-Cookie: hermes_auth=...; HttpOnly; SameSite=Strict
```

後續所有請求自動帶 cookie（`URLSession` 預設行為）。

### 7.3 V1 使用的 Endpoints

| Method | Path | 用途 | Body / Query |
|--------|------|------|--------------|
| GET | `/health` | 連線健康檢查 | — |
| GET | `/api/sessions` | Session 列表 | — |
| GET | `/api/session` | 單一 session 完整內容 | `?session_id=X` |
| POST | `/api/session/new` | 新建 session | `{model?, workspace?}` |
| POST | `/api/session/update` | 更新 model / workspace | `{session_id, model?, workspace?}` |
| POST | `/api/session/rename` | 重新命名 | `{session_id, title}` |
| POST | `/api/session/delete` | 刪除 | `{session_id}` |
| POST | `/api/chat/start` | 開始對話（取 stream_id） | `{session_id, message, model?, workspace?}` |
| GET | `/api/chat/stream` | SSE 串流 | `?stream_id=X` |
| GET | `/api/chat/stream/status` | 串流狀態查詢（重連用） | `?stream_id=X` |
| GET | `/api/approval/pending` | 待處理 approval | `?session_id=X` |
| POST | `/api/approval/respond` | 回應 approval | `{session_id, choice}` |

### 7.4 SSE Event 格式

每個 event 以下列格式發送：

```
event: token
data: {"text": "Hello"}

event: tool
data: {"name": "terminal", "preview": "ls -la"}

event: approval
data: {"command": "rm -rf /tmp/x", "description": "...", "pattern_keys": ["rm_rf"]}

event: done
data: {"session": { ... full session compact ... }}

event: error
data: {"message": "...", "trace": "..."}

: heartbeat
```

注意：每 30 秒會收到 `: heartbeat` 註解行，用於保持連線；解析器需忽略 `:` 開頭行。

### 7.5 模型定義（Swift Codable）

```swift
struct Session: Codable, Identifiable {
    let sessionId: String
    var title: String
    var workspace: String
    var model: String
    var messages: [Message]
    let createdAt: Double
    var updatedAt: Double
    var pinned: Bool
    var archived: Bool

    var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case title, workspace, model, messages, pinned, archived
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct Message: Codable, Identifiable {
    let id = UUID()
    let role: Role  // .user, .assistant, .system, .tool
    let content: String
    let attachments: [String]?

    enum Role: String, Codable {
        case user, assistant, system, tool
    }
}

enum SSEEvent {
    case token(String)
    case tool(name: String, preview: String)
    case approval(Approval)
    case done(Session)
    case error(message: String, trace: String?)
}
```

---

## 8. UI 設計規範

### 8.1 三欄式佈局映射

| 上游 (web) | iPhone | iPad |
|-----------|--------|------|
| 左 sidebar (sessions) | 第一層導航 | NavigationSplitView 第一欄 |
| 中央 chat | Push 進入 | NavigationSplitView 第二欄 |
| 右 panel (workspace) | V2 modal sheet | NavigationSplitView 第三欄（V2） |

### 8.2 主題

- 預設跟隨系統（Light / Dark）
- 深色模式色票對應上游 hermes-webui dark theme
- 強調色：暗藍綠（`#5FB39F` 或類似），與上游 model chip 一致

### 8.3 關鍵互動

- Send：Cmd+Enter（外接鍵盤）/ 螢幕 Send 按鈕
- New chat：右上「+」/ Cmd+K
- 切換 session：左滑 / 點擊 list cell

---

## 9. 部署與設定

### 9.1 Server 端必要設定（已在 Mac Mini M4）

```bash
# hermes-webui 啟動環境變數
export HERMES_WEBUI_HOST=0.0.0.0          # 或 Tailscale IP
export HERMES_WEBUI_PORT=8787
export HERMES_WEBUI_PASSWORD="<strong-password>"
./start.sh
```

加入 LaunchAgent 確保開機自動啟動（已配合既有 `caffeinate` + LaunchAgent 設定）。

### 9.2 Tailscale 設定建議

- Mac Mini M4 與 iPhone / iPad 加入同一 tailnet
- 在 Tailscale Admin Console 設定 ACL，限制只有 Anderson 的裝置可存取主機 8787 port
- 啟用 MagicDNS：可用主機名（如 `mac-mini.tailnet-name.ts.net`）替代 IP

### 9.3 iOS App 配置

**Info.plist** 新增：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>ts.net</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

⚠️ 僅針對 Tailscale MagicDNS 網域開例外；不要使用 `NSAllowsArbitraryLoads = true`。

---

## 10. 測試策略

### 10.1 單元測試

- `APIClient`：mock URLProtocol 測試所有 endpoint 序列化／反序列化
- `SSEClient`：餵入手刻 SSE 字串測試 event 解析（含 heartbeat、不完整 chunk）
- `ChatViewModel`：mock APIClient 測試 send → token → done 完整流程
- `KeychainStore`：寫入／讀取／刪除

### 10.2 UI 測試

- Setup 流程（輸入 URL、密碼、測試連線、進入 main）
- Session CRUD（新建、刪除、重新命名）
- Chat 送訊息、收 streaming response
- Approval 四個選項

### 10.3 手動測試 checklist

- 飛航模式切換中送訊息（驗證重連）
- App 進背景 1 分鐘後回前景（驗證 stream status 檢查）
- 輸入超長訊息（10K+ 字元）
- 大量訊息（500+）滾動效能

---

## 11. 風險與緩解

| 風險 | 影響 | 緩解 |
|------|------|------|
| iOS SSE 在背景被切斷 | 訊息流中斷 | 回前景檢查 stream status，必要時重新拉完整 session |
| Tailscale daemon 在 iOS 沒啟用 | 完全無法連線 | Setup 頁加診斷工具，明確提示開啟 Tailscale |
| hermes-webui API 改版 | API 不相容 | 定義 OpenAPI/Swagger spec（V2），加版本檢查 |
| HTTP 而非 HTTPS | ATS 警告 / 中間人風險 | 僅在 tailnet 內，WireGuard 已加密；ATS 例外限定 `*.ts.net` |
| 上游 RULE 違反（如 deleteSession 自動建新） | 邏輯錯誤 | 在 ViewModel 加 unit test 對應上游 Critical Rules |

---

## 12. 路線圖

### V0.1（MVP, 預計 4 週）
- F-01 連線設定
- F-02 Session 管理（list, new, delete, load）
- F-03 Chat 核心（送訊息、SSE token、Markdown）
- F-04 Approval card

### V0.2（+2 週）
- F-03.9 程式碼語法高亮
- F-03.11 訊息複製
- F-03.12 In-flight 狀態保存
- F-05 Model 切換
- 錯誤處理打磨、Setup 流程診斷

### V0.3（V2 起步）
- F-06 Workspace 檔案瀏覽
- F-10 檔案上傳
- F-12 離線快取（SwiftData）

### V0.4+
- F-07 Tasks panel + APNs push
- F-08 Skills, F-09 Memory
- F-13 訊息編輯重新生成

---

## 13. 開放議題

- [ ] hermes-webui 是否已實作 `/api/auth/login`？（ARCHITECTURE.md 顯示為 Phase H pending）若無，需先請 server 端補上或評估其他認證方案
- [ ] 是否需要支援多 server 切換（家裡 Mac + 公司 server）？V1 暫定單 server
- [ ] iPad 三欄式 vs 雙欄式：實機測試後決定
- [ ] App 圖示與 launch screen 設計：待定
- [ ] 是否上架 App Store 或僅 Ad-hoc / TestFlight？影響憑證與隱私聲明準備

---

## 14. 詞彙表

| 術語 | 說明 |
|------|------|
| Hermes Agent | Nous Research 開發的 autonomous agent，本 app 的後端核心 |
| hermes-webui | Hermes Agent 的 web 介面，本 app 直接消費其 API |
| SSE | Server-Sent Events，HTTP 長連線單向推送協定 |
| Tailnet | Tailscale 的私有 mesh 網路 |
| Approval | 危險指令（如 `rm`）執行前的人工確認機制 |
| Stream ID | 一次 chat 請求對應的 SSE 串流識別碼 |
| Session | 一個對話容器，包含 messages、workspace、model 等 |

---

## 附錄 A：上游關鍵 RULES（必須遵守）

引用自 hermes-webui ARCHITECTURE.md Section 17：

- **RULE-1**: 刪除 session 絕不自動建立新 session
- **RULE-5**: send() 必須在任何 await 前捕獲 activeSid，避免使用者切換 session 時狀態錯亂
- **RULE-6**: Boot 流程不自動建立 session
- **RULE-9**: 處理 approval 用 `pattern_keys`（複數）而非 `pattern_key`

iOS 端對應實作位置：
- RULE-1 → `SessionListViewModel.delete(_:)`
- RULE-5 → `ChatViewModel.send(_:)` 開頭捕獲 `activeSessionId`
- RULE-6 → `HermesMobileApp` 啟動流程
- RULE-9 → `ApprovalCardView` 與 `Approval` model

---

## 附錄 B：Xcode 專案設定與建置指南

本 repo 採 **Swift Package (SwiftPM)** 結構，library 名稱 `HermesMobile`。SwiftPM library 本身**無法**直接做為 iOS app（沒有 `@main` + Info.plist + signing），需在 Xcode 建一個 thin App target 包一層。完整步驟如下。

### B.1 取得 source

V1 MVP 的初始 commit 推到 feature branch `claude/initial-project-setup-51stT`（main 受保護擋下直接 push）。在本機合併：

```bash
git checkout main
git pull
git merge --ff-only origin/claude/initial-project-setup-51stT
# 或在 GitHub 上開 PR：claude/initial-project-setup-51stT → main，merge 後再 pull
```

驗證 `Package.swift`、`Sources/HermesMobile/`、`Tests/HermesMobileTests/` 都在 root。

### B.2 用 Xcode 開 Package.swift

需要 **Xcode 15+**（含 Swift 5.9 與 iOS 17 SDK）。

```bash
open Package.swift
```

Xcode 會把整個目錄當作 Swift Package workspace 開啟。第一次開啟時會自動 resolve dependencies（`swift-markdown-ui`），需要網路。

此時可以直接 build library target：
- Scheme 選 `HermesMobile`
- Destination 選任何 iOS Simulator
- ⌘+B

也可以跑單元測試：
- ⌘+U

或從 CLI：

```bash
xcodebuild test \
  -scheme HermesMobile \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### B.3 建立 iOS App target

Library 只能跑測試、不能裝到手機。建一個 App target：

1. Xcode 選單 `File → New → Project…`
2. 選 `iOS → App`
3. 設定：
   - Product Name: `HermesMobile`
   - Team: 你的 Apple Developer team
   - Organization Identifier: `com.anderson`（或自選）
   - Bundle Identifier 將自動成為 `com.anderson.hermesmobile`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - 取消勾選 Include Tests（測試已在 SwiftPM 提供）
4. 存到一個**獨立目錄**（例如 `~/code/HermesMobileApp`），**不要**存進本 repo（否則會跟 SwiftPM 結構衝突）

### B.4 把本 repo 的 Package 加進 App target

在新建的 App project：

1. 選 project（藍色頂層 icon）→ 右側 `Package Dependencies` tab → `+`
2. 點 `Add Local…` → 選擇本 repo 的根目錄（包含 `Package.swift` 那層）
3. Add Package
4. 選 `HermesMobile` library，加到 `HermesMobile` app target

### B.5 改寫 App entry point

打開 App target 自動產生的 `HermesMobileApp.swift`（或類似名稱），整檔覆蓋成：

```swift
import SwiftUI
import HermesMobile

@main
struct HermesMobileAppEntry: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

刪除自動生成的 `ContentView.swift`（不需要）。

### B.6 設定 Info.plist 與 ATS 例外

App target 的 `Info.plist`（或 `Project → Info → Custom iOS Target Properties`）加入 SRS §9.3 列出的 ATS 例外：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>ts.net</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

⚠️ **絕不**設 `NSAllowsArbitraryLoads = true`。例外網域只開 Tailscale MagicDNS。

如果 Tailscale IP 寫死（如 `100.x.x.x`）而非用 MagicDNS hostname，需另外加 IP 例外（不建議；改用 MagicDNS）。

### B.7 簽署設定

App target → `Signing & Capabilities`：

- ✅ Automatically manage signing
- Team: 你的 Apple Developer team
- Bundle Identifier: `com.anderson.hermesmobile`

如果用 Personal Team（免付費）只能 7 天為限部署到實機；TestFlight / Ad-hoc 需付費 Apple Developer Program ($99/年)。

Capabilities 不需要任何特殊權限（Keychain 預設可用、Network 預設可用）。

### B.8 在 Simulator 跑

1. Scheme 選新建立的 App
2. Destination 選 iPhone 15 (iOS 17.x) Simulator
3. ⌘+R

第一次啟動會看到 Setup 頁，輸入：
- Server URL: `http://<tailscale-ip>:8787`（Mac mini 上 hermes-webui 的位置）
- 密碼: `HERMES_WEBUI_PASSWORD` 對應的值

⚠️ Simulator **沒有** Tailscale，所以連 Tailscale IP 會失敗。Simulator 測試請改：
- 在 Mac 同網段啟用 hermes-webui，用 Mac 的 LAN IP（如 `http://192.168.x.x:8787`）
- 或先用 `ssh -L 8787:localhost:8787 mac-mini` 把 server 轉發到 localhost，Simulator 連 `http://localhost:8787`

### B.9 在實機跑

實機需要：
1. iPhone / iPad 已加入同一個 Tailscale tailnet（裝 Tailscale iOS app 並登入）
2. ACL 允許該裝置存取 Mac mini 的 8787 port
3. Xcode → 連接 iPhone → Trust this computer
4. Destination 選實機 → ⌘+R
5. iPhone 設定 → General → VPN & Device Management → 信任你的 developer 憑證
6. 啟動 app，輸入 Tailscale MagicDNS hostname（如 `http://mac-mini.tail-xxxx.ts.net:8787`）

### B.10 TestFlight 部署

V1 走 TestFlight 內部測試（單使用者用，不上架 App Store）：

1. Bundle Identifier 在 App Store Connect 註冊
2. Xcode → `Product → Archive`（Destination 必須是 `Any iOS Device`，不能是 Simulator）
3. Archive 完成後 Organizer 開啟 → 選 `Distribute App → App Store Connect → Upload`
4. App Store Connect → TestFlight tab → 加入自己為 internal tester
5. iPhone 裝 TestFlight app，接受邀請後安裝

每次改 code 想更新，bump `CFBundleVersion`（build number）後再 Archive + Upload。

### B.11 跑測試

```bash
xcodebuild test \
  -scheme HermesMobile \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

或在 Xcode 內 `⌘+U`。

預期通過的測試：
- `APIClientTests`：Endpoint 路徑、Codable snake_case、status 碼映射
- `SSEClientTests`：所有 event 解析（含 RULE-9 pattern_keys）
- `InMemorySecretStoreTests`：CRUD
- `KeychainStoreTests`：實機/簽署 simulator 上會跑、未簽署會 skip
- `ChatViewModelTests`：send → token → done 流程、error、approval
- `SessionListViewModelTests`：RULE-1 三種 case
- `AppStateTests`：RULE-6（boot 不 auto-create）

### B.12 常見坑速查

| 症狀 | 可能原因 | 解法 |
|------|---------|------|
| `import HermesMobile` 找不到 | App target 沒加 package dependency | 重做 B.4 |
| 連 Simulator 跑開 app 但 Setup 連線一直失敗 | Simulator 不在 tailnet | 用 LAN IP 或 SSH tunnel（B.8） |
| `MarkdownUI` resolve 失敗 | 網路 / 版本相依問題 | Xcode → File → Packages → Reset Package Caches |
| Keychain 寫入失敗 | Simulator 未簽署 | 設定 Signing Team；或用 InMemorySecretStore（DEBUG only） |
| SSE 在 30 秒後斷掉 | iOS 進背景時 URLSession 會暫停 | 預期行為；回前景時 ChatViewModel.handleForeground 自動處理 |
| Build fail: `Observable` macro | Xcode 版本太舊 | 升級到 Xcode 15+ |
| `@MainActor` 隔離錯誤 | Swift concurrency strict mode 開了 | Build Settings → Strict Concurrency Checking 設 `Minimal` 或 `Targeted` |

### B.13 後續開發節奏

- 每次改 ViewModel：先確認沒違反 RULE-1 ~ RULE-iOS-C（CLAUDE.md §2）
- 每次改 SSE：跑 `SSEClientTests`
- 每次改 Setup / Session 流程：跑 `AppStateTests` + `SessionListViewModelTests` 確認 RULE-6 / RULE-1 不被破壞
- 新功能：在 `Features/{Name}/` 開新資料夾，View + ViewModel 配對
- Library 可以獨立 build / 跑 test，App target 只是 entry point；改 library 不需要動 App project

---

**文件結束**
