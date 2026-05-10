# CLAUDE.md

> 本檔案是 Claude Code 在 **HermesMobile** iOS 專案中工作的指引。
> 開始任何任務前請完整閱讀。SRS 詳見 `SRS.md`。

---

## 1. 專案核心摘要

**HermesMobile** 是 [Hermes Agent](https://hermes-agent.nousresearch.com/) 的 iOS 原生客戶端，透過 [hermes-webui](https://github.com/nesquena/hermes-webui) 暴露的 HTTP/SSE API，經 Tailscale 連線至 Mac Mini M4 主機。

**單使用者** app（Anderson 個人使用），不上架 App Store（TestFlight / Ad-hoc 部署）。

**技術棧**：
- Swift 5.9+, iOS 17+
- SwiftUI（UI）、Swift Concurrency（async/await, AsyncStream）
- `@Observable` (Observation framework，**不用** `ObservableObject`)
- `URLSession` 處理 HTTP 與 SSE（**不用**第三方 networking library）
- Keychain 儲存敏感資訊
- 第三方依賴（Swift Package Manager）：`swift-markdown-ui`、`Splash`（語法高亮）

---

## 2. 絕對規則（NEVER violate）

這些規則對應 hermes-webui ARCHITECTURE.md Section 17 的 Critical Rules，已被多次破壞並修正。違反這些規則會造成不可預期的狀態錯亂。

### RULE-1: 刪除 session 絕不自動建立新 session

```swift
// ❌ 絕對不可以這樣寫
func deleteSession(_ id: String) async {
    try await api.deleteSession(id: id)
    await createNewSession()  // ❌ 違反 RULE-1
}

// ✅ 正確做法
func deleteSession(_ id: String) async {
    try await api.deleteSession(id: id)
    await refreshSessionList()
    if activeSessionId == id {
        activeSessionId = sessions.first?.id  // 切到最新一個，或 nil（顯示空狀態）
    }
}
```

### RULE-5: 任何 await 前必須捕獲 activeSessionId

```swift
// ✅ 正確
func send(_ text: String) async {
    let activeSid = self.currentSessionId  // 先捕獲！
    let result = try await api.startChat(...)

    // 使用者可能在 await 期間切換 session
    guard self.currentSessionId == activeSid else {
        // 不要更新當前 ViewModel 狀態，只更新背景資料
        return
    }
    self.messages.append(...)
}
```

### RULE-6: Boot 流程絕不自動建立 session

App 啟動時：
- 讀取 `lastSessionId` from `UserDefaults`
- 若存在且 server 上找得到 → 載入
- 若找不到 → **顯示空狀態，等使用者點「+」**
- **絕對不要** auto-create

### RULE-9: Approval 用 `pattern_keys`（複數）

```swift
// ❌ 錯誤
if let key = approval.patternKey { /* ... */ }

// ✅ 正確
for key in approval.patternKeys {
    // 對每個 key 做處理
}
```

### RULE-iOS-A: Keychain only for secrets

密碼、auth cookie、token 一律存 Keychain。**絕對不可** 存 `UserDefaults` / `@AppStorage`。

```swift
// ❌
@AppStorage("password") var password: String = ""

// ✅
KeychainStore.shared.save(password, for: .serverPassword)
```

### RULE-iOS-B: SSE 解析必須處理 heartbeat 與不完整 chunk

```swift
for try await line in bytes.lines {
    if line.hasPrefix(":") { continue }  // 心跳註解，忽略
    if line.isEmpty { /* event 邊界 */ }
    // ...
}
```

### RULE-iOS-C: 不引入第三方 HTTP / SSE library

URLSession 已足夠。引入 Alamofire、Moya、LDSwiftEventSource 等會增加維護成本與審查風險。

---

## 3. 架構守則

### 3.1 Feature-based 目錄結構

```
HermesMobile/
├── App/              # @main, entry point
├── Core/             # 跨功能共用（Network, Models, Storage, Utilities）
├── Features/         # 各功能獨立資料夾（Setup, SessionList, Chat, Settings）
│   └── Chat/
│       ├── ChatView.swift
│       ├── ChatViewModel.swift
│       └── Components/
└── DesignSystem/     # 共用 UI 元件、色票、字型
```

新功能 = 新增 `Features/{Name}/` 資料夾，內含 View + ViewModel。

### 3.2 ViewModel 模式

```swift
@Observable
final class ChatViewModel {
    // State
    var messages: [Message] = []
    var isStreaming: Bool = false
    var error: APIError?

    // Dependencies (constructor injection)
    private let api: APIClient
    private let sessionId: String

    init(api: APIClient, sessionId: String) {
        self.api = api
        self.sessionId = sessionId
    }

    // Actions
    func send(_ text: String) async { /* ... */ }
}
```

- View 不直接呼叫 APIClient
- ViewModel 不持有 SwiftUI 型別（`Color`, `View`...）
- 依賴透過 init 注入，不用 singleton

### 3.3 錯誤處理

定義 `APIError` enum，所有 throw 都用它：

```swift
enum APIError: Error, LocalizedError {
    case notConfigured
    case unauthorized
    case networkFailure(URLError)
    case decoding(DecodingError)
    case serverError(status: Int, message: String?)
    case streamFailed(Error)
    case sessionNotFound

    var errorDescription: String? { /* 中文友善訊息 */ }
}
```

View 透過 `.alert` 或 inline error banner 顯示。

---

## 4. API 對接守則

### 4.1 Endpoint 定義集中

所有 endpoint 路徑放在 `Core/Network/Endpoints.swift`：

```swift
enum Endpoint {
    case health
    case sessions
    case session(id: String)
    case newSession
    case chatStart
    case chatStream(streamId: String)
    case approvalRespond
    // ...

    var path: String {
        switch self {
        case .health: return "/health"
        case .sessions: return "/api/sessions"
        case .session(let id): return "/api/session?session_id=\(id)"
        // ...
        }
    }
}
```

### 4.2 Codable 命名

hermes-webui 用 snake_case。Swift 用 camelCase。透過 `CodingKeys` 顯式對應，**不要** 全域設定 `keyDecodingStrategy = .convertFromSnakeCase`（部分欄位是 acronym 如 `ID` 會壞）。

### 4.3 SSE 解析職責劃分

- `SSEClient`：純解析器，吐 `AsyncThrowingStream<SSEEvent, Error>`
- `ChatViewModel`：訂閱 stream，更新 UI state
- 重連邏輯放在 `ChatViewModel`（知道哪個 session）

---

## 5. 命名規範

| 種類 | 規範 | 範例 |
|------|------|------|
| Type（class/struct/enum） | UpperCamelCase | `ChatViewModel`, `SSEEvent` |
| 變數／函式 | lowerCamelCase | `currentSession`, `sendMessage()` |
| 常數 | lowerCamelCase | `let maxRetries = 5` |
| 縮寫 | 全大寫或全小寫 | `APIClient`, `urlString`（**不寫** `UrlString`） |
| Acronym 於開頭 | 全小寫 | `urlString`（**不寫** `URLString`） |
| 檔名 | 與主要 type 同名 | `ChatViewModel.swift` |
| Boolean | is/has/should 開頭 | `isStreaming`, `hasError` |

---

## 6. 工作流程

### 6.1 開始新功能

1. 確認 SRS.md 對應章節
2. 在 `Features/` 建立功能資料夾
3. 先寫 Model（如果有新的）→ 再寫 ViewModel → 最後 View
4. ViewModel 寫完先寫單元測試（mock APIClient）
5. View 用 `#Preview` 測試各種狀態

### 6.2 修改既有功能

1. 先讀對應 ViewModel 與 SRS 章節
2. 確認沒違反 RULE-1 ~ RULE-iOS-C
3. 修改後執行 `Cmd+U` 跑測試
4. 用 Preview 驗證 UI

### 6.3 Commit 訊息規範

```
<type>(<scope>): <subject>

<body>
```

type: `feat` / `fix` / `refactor` / `test` / `docs` / `chore`
scope: `chat` / `session` / `api` / `setup` / `ui` / ...

範例：
```
feat(chat): implement SSE token streaming

- Add SSEClient with AsyncThrowingStream parser
- Wire ChatViewModel.send() to subscribe events
- Handle heartbeat (`:` prefix) lines

Refs SRS F-03.3, F-03.4
```

---

## 7. 測試守則

### 7.1 單元測試覆蓋目標

- `APIClient`：所有 endpoint 序列化／反序列化（用 `MockURLProtocol`）
- `SSEClient`：手刻 SSE 字串測試各種 event 與邊界情況
- `ChatViewModel`：mock api 測試 send → done 完整流程
- `KeychainStore`：CRUD

### 7.2 不要測試的東西

- SwiftUI View 本身（用 Preview 視覺驗證即可）
- 第三方 library 行為（`swift-markdown-ui`）
- iOS 系統 API

### 7.3 測試檔案位置

`HermesMobileTests/{對應功能}/{Type}Tests.swift`

---

## 8. UI / UX 守則

### 8.1 跟隨系統

- 字級：`.font(.body)` 等系統字級，自動 Dynamic Type
- 顏色：`Color(.systemBackground)` 等 system color，自動 Light/Dark
- 強調色定義在 `DesignSystem/Colors.swift`

### 8.2 載入狀態

- 短任務（< 1s）：不顯示 loading
- 中等任務（1-3s）：用 `ProgressView` 取代內容
- 長任務（> 3s）：顯示進度資訊（如 SSE token 串流即視為長任務）

### 8.3 錯誤呈現

- 可重試的錯誤（網路）：inline banner + 重試按鈕
- 致命錯誤（auth 失敗）：`.alert` + 引導至 Setup
- 從不彈 raw error message 給使用者；用 `APIError.errorDescription` 中文化

### 8.4 隱私

App 切到背景時整個畫面要模糊化：

```swift
.scenePhaseProtected()  // 自製 modifier
```

---

## 9. 部署設定

### 9.1 Bundle Identifier

`com.anderson.hermesmobile`（可調整）

### 9.2 Signing

- TestFlight / Ad-hoc 部署，不上架 App Store
- 需 Apple Developer Program 帳號

### 9.3 Info.plist 必要設定

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>ts.net</key>
        <dict>
            <key>NSIncludesSubdomains</key><true/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
        </dict>
    </dict>
</dict>
```

⚠️ **禁止** 設 `NSAllowsArbitraryLoads = true`。例外網域只開 Tailscale MagicDNS 範圍。

---

## 10. 環境與工具

### 10.1 開發環境

- macOS 14+ / Xcode 15+
- Anderson 主要開發機：Mac Mini M4
- iOS Simulator 與實機（iPhone / iPad）

### 10.2 Hermes Server 端

Mac Mini M4 上應持續運行 hermes-webui，啟動指令：

```bash
export HERMES_WEBUI_HOST=0.0.0.0
export HERMES_WEBUI_PORT=8787
export HERMES_WEBUI_PASSWORD="<password>"
cd ~/path/to/hermes-webui
./start.sh
```

確認連線：
```bash
curl http://<tailscale-ip>:8787/health
```

### 10.3 SwiftLint（建議）

採用 Apple Swift API Design Guidelines。設定檔 `.swiftlint.yml` 包含：

```yaml
disabled_rules:
  - trailing_whitespace

opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - sorted_imports

line_length: 140
file_length: 400
type_body_length: 250
function_body_length: 50
```

---

## 11. 對接上游時的注意事項

### 11.1 必讀文件

開始實作 chat 或 SSE 前，必讀：
- 上游 `ARCHITECTURE.md` Section 4.3 (SSE Streaming Engine)
- 上游 `ARCHITECTURE.md` Section 4.5 (Approval System Integration)
- 上游 `ARCHITECTURE.md` Section 5.6 (Session Delete Rules)
- 上游 `ARCHITECTURE.md` Section 18 (Endpoint Reference)

### 11.2 Server 端可能 pending 的功能

| 功能 | 上游狀態 | iOS 端因應 |
|------|---------|-----------|
| `/api/auth/login` | Phase H pending | V1 先用其他方案（如 reverse proxy 加 basic auth），或先請 server 端補實作 |
| `/api/chat/cancel` | 不確定是否實作 | V1 先靠關閉 SSE 連線；確認後再加 explicit cancel button |
| Push notifications | 未實作 | V2 才會用到，需先評估 server 端可行性 |

### 11.3 與 server 端的協作

如果 hermes-webui 行為不符預期：
- 先用 `curl` 重現問題
- 看 server log（`/tmp/webui-mvp.log`，JSON 格式）
- 必要時 fork hermes-webui，修了之後 PR 回上游

---

## 12. 文件維護

### 12.1 必須同步更新

當以下事件發生時，**必須** 更新對應文件：

| 事件 | 更新檔案 |
|------|---------|
| 新增功能 | SRS.md（功能需求章節）、本檔（如有新規則） |
| 改變架構 | SRS.md（系統架構章節）、本檔 |
| 新增 endpoint 對接 | SRS.md（API 介面契約） |
| 發現新的 Critical Rule | 本檔（第 2 章） |
| 引入新依賴 | 本檔（第 1 章 技術棧） |

### 12.2 文件審查

每個 sprint 結束時，快速 review 一次 SRS.md 與 CLAUDE.md，確認沒有過期內容。

---

## 13. 常見坑（pre-emptive warnings）

### 13.1 SSE 連線在背景被切

iOS 進背景約 30 秒後系統會中斷網路。**不要** 假設 SSE 永遠連著。
- 進背景：記錄 `lastStreamId`
- 回前景：先 `GET /api/chat/stream/status` 確認，再決定重連或重新拉 session

### 13.2 `URLSession.bytes(for:)` 與背景

`bytes(for:)` 不適用 background URLSession。SSE 在背景**不會**繼續收。這是預期行為，依靠 RULE-iOS 中的回前景重連策略。

### 13.3 Cookie 共用

確保 SSE 與一般 API 用同一個 `URLSession.shared`（或 custom session 但共用 cookie storage），否則 auth cookie 不會帶到 SSE 請求。

### 13.4 Markdown 渲染與 streaming

Token 串流時每次都 re-render markdown 會很慢。建議：
- 串流期間只顯示純文字
- `done` event 後一次渲染完整 markdown

### 13.5 Tailscale IP 變動

`100.x.x.x` IP 在罕見情況下會變動。建議使用 MagicDNS 主機名（如 `mac-mini.tail-name.ts.net`）取代寫死 IP。

---

## 14. 參考文件

- `SRS.md` — 完整需求與規格
- 上游：[hermes-webui repo](https://github.com/nesquena/hermes-webui)
- 上游：`ARCHITECTURE.md` — 後端架構聖經
- [Apple Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [Tailscale iOS docs](https://tailscale.com/kb/1020/install-mac/)

---

**結束。開始任何任務前請確認讀過本檔的第 2 章 (絕對規則)。**
