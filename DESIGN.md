# HermesMobile — 架構與設計決策 (DESIGN)

> Version: 0.1.0
> Last updated: 2026-05-10
> Status: Draft
> 配合文件：`SRS.md`、`SPEC.md`、`CLAUDE.md`

本文件記錄 HermesMobile iOS app 的整體架構、模組分層、關鍵資料流，以及 V1 MVP 階段的設計決策（Architecture Decision Records, ADRs）。閱讀順序建議：§1（鳥瞰）→ §3（component map）→ §4（sequence 圖）→ §6（ADRs）。

---

## 1. 架構鳥瞰

```
┌────────────────────────────────────────────────────────────┐
│                          App Target                       │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  @main HermesMobileAppEntry  (thin wrapper)          │  │
│  │     └─ WindowGroup { HermesMobile.RootView() }       │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
                              │ depends on
                              ▼
┌────────────────────────────────────────────────────────────┐
│         HermesMobile (SwiftPM library, iOS 17+)            │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                       App                            │  │
│  │   AppState   RootView  (entry, screen 切換, sheet)   │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │ injects api / appState                   │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │                      Features                        │  │
│  │   Setup / SessionList / Chat / Settings              │  │
│  │   (View + ViewModel pair, 1:1)                       │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │ uses                                     │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │                       Core                           │  │
│  │   Network (APIClient / SSEClient / Endpoints)        │  │
│  │   Models (Session / Message / Approval / SSEEvent)   │  │
│  │   Storage (KeychainStore / Preferences)              │  │
│  │   Utilities (DateFormatters)                         │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │ uses                                     │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │                  DesignSystem                        │  │
│  │   Colors / Typography / PrivacyShield                │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
                              │ HTTP/SSE
                              ▼
                    hermes-webui :8787
```

### 1.1 依賴方向（嚴格單向）

```
App ──► Features ──► Core ──► Apple SDKs
        │                │
        └─► DesignSystem ◄┘
```

- `Core` 不可 import `SwiftUI`（純 model + 網路 + 儲存）。
- `Features` 可 import `Core` 與 `DesignSystem`。
- `DesignSystem` 只依賴 `SwiftUI` 與 Apple SDKs。
- `Core` 之間互相不能成環（Network 不知道 Models 以外的 Storage/Features）。

---

## 2. 模組分層原則

### 2.1 App 層

| Type | 職責 |
|------|------|
| `RootView` | 唯一 public entry View；處理 setup ↔ main 切換、隱私遮罩、persist active session |
| `AppState` | `@Observable` `@MainActor`；持有 APIClient、activeSessionId、per-session ChatViewModel cache；boot / signOut 流程 |

### 2.2 Features 層（每個功能 1 資料夾）

| Feature | View | ViewModel | 角色 |
|---------|------|-----------|------|
| Setup | `SetupView` | `SetupViewModel` | F-01 連線設定、test connection |
| SessionList | `SessionListView`, `SessionRowView` | `SessionListViewModel` | F-02 列表、CRUD、RULE-1 enforcement |
| Chat | `ChatView`, `MessageBubbleView`, `ComposerView`, `ApprovalCardView`, `ToolCallView` | `ChatViewModel` | F-03 對話、SSE、F-04 approval |
| Settings | `SettingsView` | `SettingsViewModel` | 顯示 / sign out |

### 2.3 Core 層

| 子模組 | 主要 type | 職責 |
|--------|-----------|------|
| Network | `APIClient`, `APIClientProtocol`, `SSEClient`, `Endpoint`, `APIError` | HTTP 與 SSE，protocol-based 以利測試 |
| Models | `Session`, `Message`, `Approval`, `ApprovalChoice`, `ToolCall`, `SSEEvent` | Codable，與 server snake_case 對應 |
| Storage | `KeychainStore`, `Preferences`, `SecretStoring`, `InMemorySecretStore` | 機密 vs 設定的明確分流 |
| Utilities | `DateFormatters` | 跨 view 重用 |

### 2.4 DesignSystem 層

| Type | 職責 |
|------|------|
| `AppColors` | 強調色 / 訊息氣泡 / approval / danger |
| `AppTypography` | 系統 dynamic type 包裝 |
| `PrivacyShield` modifier | App 進背景時的內容遮罩（SRS §5.3） |

---

## 3. Component Map

完整 type → file 索引，方便對照修改。

| Type | 檔案 | 公開？ | 備註 |
|------|------|--------|------|
| `RootView` | `Sources/HermesMobile/App/RootView.swift` | public | 唯一對 App target 公開的 entry |
| `AppState` | `Sources/HermesMobile/App/AppState.swift` | public | 共享狀態容器 |
| `Session`, `SessionListItem` | `Core/Models/Session.swift` | public | snake_case CodingKeys |
| `Message` | `Core/Models/Message.swift` | public | id 缺漏時 fallback UUID |
| `Approval`, `ApprovalChoice` | `Core/Models/Approval.swift` | public | RULE-9：pattern_keys |
| `ToolCall` | `Core/Models/ToolCall.swift` | public | UI 顯示用 |
| `SSEEvent` (+ payload structs) | `Core/Models/SSEEvent.swift` | public/internal | enum 表示 stream events |
| `APIError` | `Core/Network/APIError.swift` | public | 中文 errorDescription |
| `Endpoint` | `Core/Network/Endpoints.swift` | public | 集中所有路徑 |
| `APIClient`, `APIClientProtocol` | `Core/Network/APIClient.swift` | public | URLSession 包裝 |
| `SSEClient` | `Core/Network/SSEClient.swift` | public | 純解析器，吐 AsyncThrowingStream |
| `KeychainStore`, `SecretStoring`, `InMemorySecretStore` | `Core/Storage/KeychainStore.swift` | public/DEBUG | InMemory 僅 DEBUG |
| `Preferences` | `Core/Storage/Preferences.swift` | public | UserDefaults 包裝 |
| `DateFormatters` | `Core/Utilities/DateFormatters.swift` | public | 相對 / 絕對時間 |
| `AppColors`, `AppTypography` | `DesignSystem/Colors.swift`, `Typography.swift` | public | 統一視覺 |
| `PrivacyShield` modifier | `DesignSystem/PrivacyShield.swift` | public | scenePhase 模糊化 |
| `SetupView`, `SetupViewModel` | `Features/Setup/` | public | F-01 |
| `SessionListView`, `SessionRowView`, `SessionListViewModel` | `Features/SessionList/` | public | F-02、RULE-1 |
| `ChatView`, `MessageBubbleView`, `ComposerView`, `ApprovalCardView`, `ToolCallView`, `ChatViewModel` | `Features/Chat/` | public | F-03、F-04 |
| `SettingsView`, `SettingsViewModel` | `Features/Settings/` | public | sign out |

---

## 4. Sequence 圖

### 4.1 首次啟動 / 已設定啟動

```
User             RootView         AppState         Preferences   Keychain   APIClient
  │ launch app       │               │                 │             │           │
  │─────────────────►│               │                 │             │           │
  │                  │ .task         │                 │             │           │
  │                  │──── boot() ──►│                 │             │           │
  │                  │               │── serverURL ───►│             │           │
  │                  │               │◄── URL? ────────│             │           │
  │                  │               │── load(.serverPassword) ────►│           │
  │                  │               │◄── pwd? ────────────────────────│         │
  │                  │               │                                          │
  │      [credentials missing]                                                  │
  │                  │               │  screen = .setup                          │
  │      ──────────────────────────────────────────                             │
  │      [credentials present]                                                  │
  │                  │               │  build APIClient(baseURL)─►              │
  │                  │               │  Task { login(pwd) }   ───────────────►  │
  │                  │               │  screen = .main                          │
  │                  │               │  activeSessionId = lastSessionId (or nil)│
  │                  │               │            ▲                              │
  │                  │               │            │ RULE-6: never auto-create   │
```

### 4.2 Send message → SSE → done

```
User    ChatView   ChatViewModel        APIClient            SSEClient    Server
  │ tap Send   │           │                  │                   │           │
  │───────────►│ send(text)│                  │                   │           │
  │            │──────────►│ activeSid = sessionId   ◄── RULE-5  │           │
  │            │           │ append optimistic user message      │           │
  │            │           │ isStreaming = true                  │           │
  │            │           │── startChat ────►│                  │           │
  │            │           │                  │── POST /chat/start ─────────►│
  │            │           │                  │◄── stream_id ────────────────│
  │            │           │◄ ChatStartResponse│                  │           │
  │            │           │── streamChat ───►│                  │           │
  │            │           │                  │── stream(req) ───►           │
  │            │           │                  │                   │── GET ──►│
  │            │           │                  │                   │◄ SSE ────│
  │            │           │◄ token "Hel" ────│◄ .token("Hel") ──│           │
  │            │ rebuild   │                  │                   │           │
  │            │ streaming │                  │                   │           │
  │            │ message   │                  │                   │           │
  │            │           │◄ token "lo" ─────│                   │           │
  │            │           │◄ done(session) ──│                   │           │
  │            │           │ apply(session) → messages = session.messages    │
  │            │           │ streamingMessage = ""                           │
  │            │           │ isStreaming = false                             │
```

### 4.3 切 session 不破壞 in-flight（F-03.12 + RULE-5）

```
ChatVM(A) streaming           AppState                   ChatVM(B)
   │  isStreaming=true            │                         │
   │  Task: SSE active            │                         │
   │                              │  user taps session B    │
   │                              │  activeSessionId = "B"  │
   │                              │── chatViewModel("B") ─►│ create new VM
   │                              │                         │ load session B
   │  (continues running)         │                         │
   │  receives token              │                         │ shows session B UI
   │  appends to own state        │                         │
   │  ...                         │                         │
   │  user taps session A back    │                         │
   │  activeSessionId = "A"       │                         │
   │  RootView.detail rebuilds    │                         │
   │  → reuses ChatVM(A) (cached) │                         │
   │  shows full state w/ pending tokens / approval        │
```

每個 ChatViewModel 綁死自己的 `sessionId`（`let`），不會被切換污染；AppState 用字典快取以保留 in-flight。

### 4.4 Approval flow（含 polling fallback）

```
Server          SSE stream        ChatViewModel       View      User
   │                │                  │                │         │
   │── approval ────►                  │                │         │
   │                │── .approval(a) ──►                │         │
   │                │                  │ pendingApproval = a      │
   │                │                  │── render ─────►│         │
   │                │                                   │ shown   │
   │                │ [SSE 中斷] ─x                                │
   │                                   │ startApprovalPolling()   │
   │                                   │── pendingApproval(sid) ──►
   │                                   ◄── still pending ──────────
   │                                   │ (1500ms loop)            │
   │                                   │                          │
   │                                   │                tap Allow │
   │                                   ◄── respondApproval(.allowOnce)
   │── 200 ────────────────────────────►                          │
   │                                   │ pendingApproval = nil    │
   │                                   │ stopApprovalPolling()    │
```

### 4.5 Delete active session（RULE-1）

```
User      SessionListView    SessionListViewModel    AppState     APIClient
  │ swipe delete    │                │                  │              │
  │────────────────►│ delete(id)     │                  │              │
  │                 │───────────────►│ wasActive = (id == active)      │
  │                 │                │── deleteSession(id) ─────────► │
  │                 │                │◄ 200 ──────────────────────────│
  │                 │                │── load() (refetch list) ───────►
  │                 │                │◄ remaining sessions ──────────│
  │                 │                │ if wasActive:                   │
  │                 │                │   activeSessionId = sessions.first?.id ── may be nil
  │                 │                │ ── NEVER calls newSession ──    │
  │                 │                │      ▲                          │
  │                 │                │      │ RULE-1                  │
```

### 4.6 Background → Foreground

```
scenePhase   ChatView   ChatViewModel        APIClient
   │            │             │                  │
.inactive/.background          │                  │
   │───────────►│              │                  │
   │            │ handleBackground()              │
   │            │              │ preferences.lastBackgroundDate = now
   │            │              │ (DO NOT cancel SSE task; let iOS suspend)
   │            │
.active        │
   │───────────►│              │                  │
   │            │ Task { handleForeground() }     │
   │            │             │── streamStatus(streamId) ──────────►│
   │            │             │◄ active=true  → startStream()       │
   │            │             │   active=false → load()             │
   │            │             │── pendingApproval(sessionId) ───────►│
```

---

## 5. 並行模型

### 5.1 Actor isolation

- `APIClient`、`SSEClient`：`final class`，`@unchecked Sendable`，只觸碰 immutable / thread-safe state（URLSession）。
- 所有 ViewModel：`@Observable @MainActor`，狀態變更與 UI 同 actor，無需鎖。
- `AppState`：`@Observable @MainActor`，內部字典 `chatViewModels` 標 `@ObservationIgnored` 避免 SwiftUI 重渲染迴圈。

### 5.2 Task 生命週期

| Task | 啟動點 | 取消點 |
|------|--------|--------|
| Stream consumer | `ChatViewModel.startStream` | `cancel()`、`teardown()`、新 stream 啟動、新 message |
| Approval poll | `ChatViewModel.startApprovalPolling` | SSE 重連、收到 respond、teardown |
| Boot login | `AppState.boot` | (fire-and-forget) |
| SwiftUI `.task` | View 生命週期 | View 消失 |

每個 `Task` 必檢查 `Task.isCancelled` 或回應 `CancellationError`。

### 5.3 AsyncThrowingStream 約定

`SSEClient.stream(request:)` 的 stream 由內部 Task 推送 events，`continuation.onTermination` 取消上游 Task。因此 ChatViewModel 取消 streamTask 即可釋放整條鏈。

---

## 6. ADR — 設計決策記錄

每條決策記：context（為何要決定）／decision（決定了什麼）／consequences（後果）／alternatives（被否決的選項）。

### ADR-001: 用 SwiftPM library + thin App target

**Context**: 需要結構化的 source code，方便未來拆出 share extension / widget；同時要能在 Mac/Linux 環境管理檔案、跑 unit test。

**Decision**: 把所有功能寫在 `HermesMobile` SwiftPM library（`Package.swift`），iOS App target 由開發者在 Xcode 端建立並 `import HermesMobile`。

**Consequences**:
- 可在純文字環境管理整個 app 邏輯。
- 單元測試可由 `xcodebuild test -scheme HermesMobile` 跑。
- 缺點：第一次設定多一步建 App target（見 SRS §B）。

**Alternatives**:
- `.xcodeproj` from scratch：難在文字環境管理。
- XcodeGen `project.yml`：可生成 .xcodeproj，但仍需 Mac 工具產生。為單使用者 app 太重。

### ADR-002: 不引入第三方 HTTP / SSE library

**Context**: Alamofire / Moya / LDSwiftEventSource 都能做網路與 SSE，但會增加 supply chain 風險與維護成本。

**Decision**: 全部用 `URLSession` + `URLSession.bytes(for:).lines` 自幹（CLAUDE.md RULE-iOS-C）。

**Consequences**:
- 套件樹乾淨（只剩 swift-markdown-ui）。
- SSE 解析自寫（70 行），需要自己處理 heartbeat / 不完整 chunk。
- 沒有 library 升級導致的 breaking change 風險。

**Alternatives**:
- LDSwiftEventSource：成熟但拖一個額外依賴。
- Alamofire：完全沒必要，為了單一 app 過度。

### ADR-003: Per-session ChatViewModel 存於 AppState 字典

**Context**: F-03.12 要求切換 session 後回來仍能看到 in-flight 狀態（streaming token、pending approval）。若用單一 ChatViewModel 切換 session，原 SSE task 要嘛被中斷、要嘛狀態被覆蓋。

**Decision**: `AppState.chatViewModels: [String: ChatViewModel]` 快取每個 session 的 VM。`RootView` 透過 `appState.chatViewModel(for: sessionId)` 取出，不存在則建立。`ChatView` 用 `.id(sessionId)` 確保切換時換上正確 VM。`@ObservationIgnored` 避免字典變動觸發整顆 RootView 重渲染。

**Consequences**:
- RULE-5 自動成立：每個 VM 鎖死自己的 `let sessionId`，不可能跨 session 污染。
- 記憶體：N 個 sessions × VM 大小（約幾 KB），可接受。
- VM 不會自動 teardown，需在 sign out 統一清。

**Alternatives**:
- 單一 ChatViewModel + state 切換：違反 RULE-5 風險高，已被上游驗證會造成錯亂。
- View 持有 VM：切換時 VM 被釋放，無法保 in-flight。

### ADR-004: `@Observable` + `@MainActor`（捨棄 `ObservableObject`）

**Context**: iOS 17 推出 Observation framework，效能與語法皆優於 `ObservableObject`。CLAUDE.md 明列要用 `@Observable`。

**Decision**: 所有 ViewModel 與 `AppState` 用 `@Observable @MainActor`。SwiftUI View 用 `@Bindable` 取得雙向綁定。

**Consequences**:
- 無需 `@Published` annotation。
- 細粒度更新（只重繪實際讀過的屬性）。
- 最低 iOS 17，不可降。

**Alternatives**:
- `ObservableObject` + `@Published`：iOS 13+ 但已是舊 API。
- `@StateObject`：搭配 `ObservableObject`，同上。

### ADR-005: Keychain 直接用 `SecItem*`，不引 KeychainAccess

**Context**: 只存 password 與 cookie 兩個 key，需求極小。

**Decision**: 自寫 `KeychainStore` 用 `SecItemAdd` / `SecItemUpdate` / `SecItemCopyMatching` / `SecItemDelete`，accessibility 設 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（SRS §5.3）。

**Consequences**:
- 程式碼短、依賴零。
- DEBUG 提供 `InMemorySecretStore` 供測試與 #Preview 使用。

**Alternatives**:
- KeychainAccess（Swift 包裝）：再引一個依賴只為了兩個欄位不划算。

### ADR-006: SSE 用 `URLSession.bytes(for:).lines`

**Context**: 需要從 byte stream 抽出 line-delimited SSE events。

**Decision**: 用 Apple SDK 內建的 `URLSession.AsyncBytes.lines` async sequence 取行；自寫 SSE state machine（event/data buffer + boundary detection）。

**Consequences**:
- 無需自己處理 chunk 邊界（OS 處理）。
- 與 cookie / TLS / proxy 行為一致。
- 缺點：iOS 進背景時 `bytes(for:)` 會被 OS 暫停（已知；ADR-010 處理）。

**Alternatives**:
- 自寫 byte → line splitter：冗餘、易錯。
- WebSocket：server 用 SSE，改寫上下游成本太高。

### ADR-007: 共用 `HTTPCookieStorage.shared`

**Context**: `/api/auth/login` 拿到的 cookie 必須在 SSE 連線中也帶上。

**Decision**: 一個 `URLSession` 同時用於 HTTP API 與 SSE，`URLSessionConfiguration.httpCookieStorage = .shared`，`httpCookieAcceptPolicy = .always`。

**Consequences**:
- 開發者不需要手動帶 cookie header。
- iOS 系統管 cookie persistence。

**Alternatives**:
- 各自的 session：`Set-Cookie` 不會在 SSE session 生效，必須手動同步。

### ADR-008: 重連用指數退避 (1s → 2s → 4s → 8s → 16s, cap 30s)

**Context**: SRS §5.2 要求自動重連，但要避免 server 過載。

**Decision**: `ChatViewModel.handleStreamFailure` 採 `1s × 2^n` 退避，第 5 次起 cap `30s`，總嘗試無上限（直到 ChatViewModel teardown）。重連前必先 `streamStatus`，避開無效訂閱。

**Consequences**:
- 暫時網路抖動可自動恢復。
- 持續斷線會吃電；交給使用者手動關 app 或 cancel。

**Alternatives**:
- 固定 5 秒重連：早期不夠快，後期太頻繁。
- 限制嘗試次數：使用者經驗較差，Anderson 偏好「能連就連」。

### ADR-009: Approval polling 1500ms

**Context**: SSE 中斷時若仍有待 approval 卡住，使用者可能無感；需要有 fallback 機制（F-04.5）。

**Decision**: SSE 進入錯誤 / 結束狀態後啟動 polling，每 `1500ms` 呼叫 `/api/approval/pending`；SSE 重連成功後立即停止。

**Consequences**:
- 在不可靠網路下仍能呈現 approval。
- 流量極小（一次 < 1KB）。

**Alternatives**:
- 等使用者手動 refresh：易錯過 approval 視窗。
- 短於 500ms：對 server 不友善。

### ADR-010: 不啟用 Background Modes (fetch / processing)

**Context**: iOS 預設 app 進背景 30 秒後暫停網路；要在背景持續收 SSE 需開 Background Modes 並通過 App Store 審查。

**Decision**: V1 不開任何 Background Modes。改用「進背景時記錄 lastStreamId、回前景時重連 / 重抓 session」的策略（SRS §6.4）。

**Consequences**:
- 不需 App Store 額外理由。
- 背景時通知靠 V2 server-side APNs（未實作）。
- 對 V1（單使用者主動使用）已足夠。

**Alternatives**:
- Background Modes `fetch`：對單使用者單裝置 app 過度；審查不易過。
- Silent push 喚醒：要 server 支援，目前 hermes-webui 無此功能。

### ADR-011: 訊息 streaming 期間用純文字、`done` 後渲染 markdown

**Context**: Markdown library 每次 token 進來重新解析整段成本高，會掉 fps（CLAUDE.md §13.4）。

**Decision**: `MessageBubbleView` 收到 `isStreaming = true` 時用 `Text(content)`；`done` 後切換到 `Markdown(content)`。

**Consequences**:
- streaming 視覺較單調，但流暢度優先。
- 切換瞬間使用者會看到「樣式跳變」一次（可接受）。

**Alternatives**:
- 全程 markdown：性能差。
- 全程純文字：F-03.8 不滿足。

### ADR-012: 訊息 model 的 id 由 client 補

**Context**: hermes-webui 對 Message 不一定提供穩定 id；SwiftUI `Identifiable` / `ForEach` 需要穩定 id。

**Decision**: `Message.init(from: Decoder)` 在 `id` 缺漏時自填 `UUID().uuidString`；encode 時若曾自填則送回 server（無害）。

**Consequences**:
- Local-only 變動不會被 server 接管。
- 缺點：同一條訊息經過 round-trip 後 id 可能變（在 stream 結束 server 用真實 id 覆蓋時）。

**Alternatives**:
- 用 `index` 當 id：`ForEach` 移除中間元素時動畫錯亂。
- 強制 server 提供：超出本 app 範圍。

---

## 7. 不在 V1 範圍內（已知為何延後）

| 功能 | 延後到 | 原因 |
|------|--------|------|
| F-12 SwiftData 離線快取 | V0.3 | 增加 schema migration 風險；單使用者用主動連線足夠 |
| F-11 Push 通知 | V0.4+ | 需 server 端 APNs；屬於 cron / Tasks 配套 |
| F-10 檔案上傳 | V0.3 | 需要設計多模態 message；MVP 先做純文字 |
| F-03.9 Code 語法高亮（Splash） | V0.2 | 增加依賴；V1 用 monospace 即可 |
| Multi-server 切換 | V0.2 | Anderson 目前單 server；多 server 涉及 Keychain 多 entry 設計 |
| Cmd+Enter / Cmd+K 快捷鍵 | V0.2 | 鍵盤事件處理不在 MVP 焦點 |

每延後一項都對應 SRS §4.2 / 路線圖 §12 的條目，避免重複定義。

---

## 8. 修改本文件的時機

- 引入新的依賴 → 加 ADR。
- 改變 module 分層 / 依賴方向 → 更新 §1.1 與 §3。
- 新功能加入 Features 層 → 更新 §2.2、§3。
- 對既有 ADR 的決策反悔 → 不刪舊 ADR，新增一條 ADR 標 `Supersedes ADR-NNN`。

---

**文件結束**
