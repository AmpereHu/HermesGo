# HermesMobile — API 與行為規格 (SPEC)

> Version: 0.1.0
> Last updated: 2026-05-10
> Status: Draft
> 配合文件：`SRS.md`（需求）、`DESIGN.md`（架構）、`CLAUDE.md`（開發守則）

本文件補足 `SRS.md` 對 hermes-webui API 與 client 行為的約束，目的是讓實作者**可以照表逐條對齊**。請以本文件為準；與 SRS 衝突時採以較嚴格者。

---

## 1. 共通約定

### 1.1 Base URL

```
http://{tailscale-host}:8787
```

`tailscale-host` 可為 Tailscale IP（`100.x.x.x`）或 MagicDNS hostname（`mac-mini.tail-xxxx.ts.net`）。後者較佳。

### 1.2 通訊協定

- 一般 API：HTTP/1.1，Content-Type `application/json`，UTF-8。
- SSE 串流：HTTP/1.1，`Accept: text/event-stream`，`Cache-Control: no-cache`。
- 全部走 Tailscale tailnet；上層因此允許明文 HTTP（WireGuard 已加密）。

### 1.3 認證

- `POST /api/auth/login` 帶 JSON body `{"password": "..."}`。
- 成功回 `200 OK` 並 `Set-Cookie: hermes_auth=...; HttpOnly; SameSite=Strict; Path=/`。
- 後續請求由 `URLSession` 自動帶 cookie（透過 `HTTPCookieStorage.shared`）。
- Cookie 失效或缺漏時，server 回 `401 Unauthorized`；client 應引導回 Setup 流程或重新呼叫 login。

### 1.4 共通錯誤格式

- HTTP status 反映語意：`200/201` 成功、`400` request 錯、`401` 未認證、`403` 禁止、`404` 不存在、`5xx` server error。
- 失敗 body 為 JSON，至少含下列其一鍵名：

```json
{"detail": "...message..."}
{"error": "...message..."}
{"message": "...message..."}
```

Client 透過 `APIClient.extractServerMessage(from:)` 依序嘗試取出。

### 1.5 編碼風格

- Server 用 **snake_case**。
- Client（Swift）用 **camelCase**，透過顯式 `CodingKeys` 對應。
- **不**使用 `keyDecodingStrategy = .convertFromSnakeCase`（會誤處理 acronym）。

---

## 2. HTTP Endpoint 套約

每個 endpoint 給：method、path、auth、request、response、行為、邊界。

### 2.1 `GET /health`

| 屬性 | 值 |
|------|---|
| Auth | 不需要 |
| Request | — |
| Response 200 | `{"status": "ok", "sessions": <int>, "version": "<string?>"}` |
| Errors | 無預期錯誤；網路 timeout 視為 server 不可達 |

**Client 行為**
- Setup 頁的「測試連線」按鈕呼叫此端點，並先呼叫 `auth/login` 取得 cookie。
- `sessions` 數值用於顯示連線後的 server session 量，便於使用者確認連到正確環境。

### 2.2 `POST /api/auth/login`

| 屬性 | 值 |
|------|---|
| Auth | 不需要 |
| Request | `{"password": "<string>"}` |
| Response 200 | 任意 JSON（client 不依賴 body）；必有 `Set-Cookie: hermes_auth=...` |
| Errors | `401` 密碼錯誤 |

**Client 行為**
- Setup 完成、boot 時、收到 `401` 時呼叫。
- 不把密碼加在 query string 或 log 中。

### 2.3 `GET /api/sessions`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Request | — |
| Response 200 | `{"sessions": [SessionListItem, ...]}` |
| Errors | `401` |

`SessionListItem` 欄位：

| 欄位 | 型別 | 必選 | 說明 |
|------|------|------|------|
| `session_id` | string | ✓ | UUID 字串 |
| `title` | string | ✓ | 顯示名稱（可空字串） |
| `model` | string | ✓ | 當前 model 標籤 |
| `workspace` | string | ✓ | 路徑或標識 |
| `updated_at` | number | ✓ | Unix epoch (sec) |
| `pinned` | boolean | optional | default `false` |
| `archived` | boolean | optional | default `false` |

**Client 行為**
- 依 `updated_at` 倒序排列（在 client 端排，不仰賴 server 順序）。
- `pull-to-refresh` 重打此端點。

### 2.4 `GET /api/session?session_id=<id>`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Query | `session_id` |
| Response 200 | `{"session": Session}` |
| Errors | `401`、`404` 找不到 |

`Session` 欄位：見 §6.1。

### 2.5 `POST /api/session/new`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Request | `{"model": "<string?>", "workspace": "<string?>"}`（皆 optional） |
| Response 200 | `{"session": Session}` |
| Errors | `401`、`5xx` |

**Client 行為**
- 由 SessionList 「+」按鈕觸發。
- 成功後立即把 `activeSessionId` 切到新 session id。
- **絕不**在 boot 流程或 delete 後自動呼叫（RULE-1、RULE-6）。

### 2.6 `POST /api/session/update`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Request | `{"session_id": "...", "model": "<string?>", "workspace": "<string?>"}` |
| Response 200 | `{}` 或更新後 session |
| Errors | `401`、`404` |

V1 用於 model 切換（F-05.3，Should 優先級）。

### 2.7 `POST /api/session/rename`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Request | `{"session_id": "...", "title": "..."}` |
| Response 200 | `{}` |
| Errors | `401`、`404` |

`title` 在 client 端先 trim whitespace，空字串拒絕送出。

### 2.8 `POST /api/session/delete`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Request | `{"session_id": "..."}` |
| Response 200 | `{}` |
| Errors | `401`、`404` |

**Client 行為（嚴格）**
- 呼叫前先記住「被刪的是不是 active」。
- 呼叫成功後重抓 `/api/sessions`。
- 若被刪的是 active：`activeSessionId` 改成新列表中第一個（`updated_at` 最新）；列表為空則 `nil`（顯示空狀態）。
- **絕不**自動呼叫 `/api/session/new`（RULE-1）。

### 2.9 `POST /api/chat/start`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Request | `{"session_id": "...", "message": "...", "model": "<string?>", "workspace": "<string?>"}` |
| Response 200 | `{"stream_id": "<uuid>", "session_id": "<id>"}` |
| Errors | `401`、`404`、`409` busy、`5xx` |

**Client 行為**
- `ChatViewModel.send(_:)` 先在任何 `await` 前捕獲 `let activeSid = sessionId`（RULE-5）。
- 成功後立即開啟 SSE `GET /api/chat/stream?stream_id=<...>`。
- 若 `409 busy`：顯示「請等待目前訊息完成」，不重試。

### 2.10 `GET /api/chat/stream?stream_id=<id>`

| 屬性 | 值 |
|------|---|
| Auth | cookie（同一 URLSession 共用） |
| Headers | `Accept: text/event-stream` |
| Response 200 | SSE stream（見 §3） |
| Errors | `401`、`404`、`410` 已結束 |

Timeout 設 `.infinity`；連線健康靠 heartbeat。

### 2.11 `GET /api/chat/stream/status?stream_id=<id>`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Query | `stream_id` |
| Response 200 | `{"stream_id": "...", "active": <bool>, "finished": <bool?>}` |
| Errors | `401`、`404` |

**Client 行為**
- 重連前一定先呼叫此端點，以決定該重新訂閱還是改抓完整 session。
- 回前景時對 `lastStreamId` 也呼叫一次。

### 2.12 `POST /api/chat/cancel`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Request | `{"stream_id": "..."}` |
| Response 200 | `{}` |
| Errors | `401`、`404` |

⚠️ 上游可能尚未實作。Client 行為：呼叫但不阻擋；若 `404` 則 fallback 為單純關閉 SSE。

### 2.13 `GET /api/approval/pending?session_id=<id>?`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Query | `session_id` optional |
| Response 200 | `{"approval": Approval | null}` 或 `{"pending": Approval | null}` |
| Errors | `401` |

`Approval` 欄位：見 §6.3。

**Client 行為（F-04.5、F-04.6）**
- SSE 中斷或進入 error 後啟動 polling，每 1500ms 呼叫一次。
- App 從背景回前景立即呼叫一次。
- SSE 重新建立後停止 polling。

### 2.14 `POST /api/approval/respond`

| 屬性 | 值 |
|------|---|
| Auth | cookie |
| Request | `{"session_id": "...", "choice": "allow_once"\|"allow_session"\|"allow_always"\|"deny"}` |
| Response 200 | `{}` |
| Errors | `401`、`404`、`409` 無 pending |

`choice` 是固定字串列舉，client 用 `ApprovalChoice` enum 代表。

---

## 3. SSE Event 套約

### 3.1 框架格式

每個 event 最少由「`event:` 行」與「`data:` 行」組成，後接空白行作為 boundary。註解（heartbeat）行以 `:` 開頭。

```
event: token
data: {"text":"Hel"}

: heartbeat

event: done
data: {"session": { ... }}

```

### 3.2 解析規則（強制）

| 規則 | 說明 |
|------|------|
| 心跳忽略 | 任何以 `:` 開頭的行直接 `continue`（RULE-iOS-B） |
| 多行 data | 若同一 event 出現多個 `data:` 行，以 `\n` 串接 |
| Event boundary | 空白行（length == 0）視為 boundary，flush buffer |
| 不完整 chunk | 忽略以 `id:` / `retry:` 開頭的行（hermes-webui 不使用） |
| 串流中止 | 若連線中斷（`URLError` / EOF）但仍有 buffered event，flush 後再 yield error |
| 未知 event name | 仍 yield 為 `.unknown(name:raw:)`，不視為錯誤 |

### 3.3 Event 類型對應 payload

| `event:` | Payload schema | Yielded enum case |
|---------|----------------|-------------------|
| `token` | `{"text": "<string>"}` | `.token(String)` |
| `tool` | `{"name": "<string>", "preview": "<string?>"}` | `.tool(name: String, preview: String)` |
| `approval` | `Approval` 完整物件（含 `pattern_keys` 複數） | `.approval(Approval)` |
| `done` | `{"session": Session}`（也接受裸 `Session`） | `.done(Session)` |
| `error` | `{"message": "<string>", "trace": "<string?>"}` | `.error(message:trace:)` |
| 其他 | 任意 | `.unknown(name:raw:)` |

### 3.4 順序保證

Server 對單一 stream 在以下事件順序內發送，client 不需重排：

1. 任意數量的 `tool` / `approval` / `token`（可交錯）。
2. 最後一個必為 `done` **或** `error`。
3. `done` / `error` 之後 server 應關閉連線。

Client 若收到 `done` / `error` 後仍有 buffer，視為已結束，捨棄殘餘。

### 3.5 Approval 的特殊性

- `approval` event 出現後，stream **不一定**結束；server 等使用者透過 `/api/approval/respond` 回應後可能繼續推 `tool` / `token`，最後 `done`。
- Client 不可僅憑 `approval` event 把 `isStreaming` 設 `false`。

---

## 4. 行為 / State Machine

### 4.1 SSE Stream 生命週期

```
       ┌──────────┐  startChat success
idle ──┤          ├─────────────────────►  starting
       └──────────┘                              │
                                          open SSE
                                                 ▼
       ┌──────────────┐  token / tool /  ┌─────────────┐
       │  approval    │ ←───────────────►│  streaming  │
       │  pending     │  approval event  │             │
       └──────┬───────┘                  └──────┬──────┘
              │ respond                         │ done / error
              │                                 ▼
              └────────────────────────►  finished (idle)
```

| 轉換 | 條件 |
|------|------|
| `idle → starting` | `send()` 被呼叫 |
| `starting → streaming` | `chat/start` 200 + SSE 第一個 byte |
| `streaming → approval pending` | 收到 `approval` event |
| `approval pending → streaming` | `respond` 成功，後續 SSE 繼續 |
| `streaming → finished` | `done` 或 `error` |
| `* → reconnecting` | SSE 連線斷（network / EOF 非 done）|
| `reconnecting → streaming` | `stream/status.active == true` 重訂閱成功 |
| `reconnecting → idle` | `stream/status.active == false`，改抓 session |

### 4.2 重連策略（`ChatViewModel.handleStreamFailure`）

- 退避序列：`1s, 2s, 4s, 8s, 16s, 30s, 30s, ...`（第 5 次起 cap 30s）。
- 重連前必先呼叫 `stream/status`：
  - `active = true` → 重訂閱 `chat/stream`。
  - `active = false` → 不再重連，改 `getSession()` 取最新訊息。
- `Task.isCancelled` 為 true 時立即放棄。
- 非 retryable 錯誤（`unauthorized` / `forbidden` / `decoding`）直接報錯不重連。

### 4.3 Approval polling（fallback）

- 啟動條件：SSE 中斷後仍處於 `streaming` / `error` 狀態。
- 週期：1500 ms。
- 停止條件：SSE 重新建立、收到 `respondApproval`、ChatViewModel teardown、Task cancel。
- 失敗（網路錯）保持安靜，不顯示給使用者。

### 4.4 Background → Foreground 流程

```
background ─────────────────► foreground
   │                              │
   │ save lastStreamId            │
   │ save lastBackgroundDate      │ ChatViewModel.handleForeground()
   │                              │   1. if activeStreamId != nil:
   │                              │        streamStatus()
   │                              │        if active → reopen SSE
   │                              │        if not   → load() session
   │                              │   2. pollPendingApprovalOnce()
```

### 4.5 RULE 對應總表

| RULE | 觸發點 | 行為 |
|------|--------|------|
| RULE-1 | `SessionListViewModel.delete` | 刪除後絕不 `newSession`；切換到下一個或 nil |
| RULE-5 | `ChatViewModel.send` | 第一行捕獲 `let activeSid = sessionId`；後續 await 之後比對 |
| RULE-6 | `AppState.boot` | 不論 lastSessionId 有無，都不呼叫 `newSession` |
| RULE-9 | `Approval.patternKeys`、`ApprovalCardView` | 解析與渲染複數 keys |
| RULE-iOS-A | Setup / Settings | 密碼存 Keychain；UserDefaults 只存非機密 |
| RULE-iOS-B | `SSEClient` | `:` 行忽略；空白 boundary；多 data 行串接 |
| RULE-iOS-C | 全專案 | 只用 URLSession |

---

## 5. 邊界 / 錯誤情境清單

每一條都對應到 acceptance criteria。

| ID | 情境 | 預期行為 |
|----|------|----------|
| E-01 | Cookie 失效（`401`） | UI 顯示 `APIError.unauthorized` 訊息，回到 Setup（手動），不無限重試 |
| E-02 | Server 5xx | 一般 API：顯示錯誤、可重試；SSE：進重連流程 |
| E-03 | `chat/start` 在另一個 session 仍 busy | 顯示「請等待當前訊息完成」，本地 `isStreaming` 不變 |
| E-04 | `approval` 還沒回，但使用者按 Send | Composer 在 `isStreaming = true` 期間 disabled，禁送出 |
| E-05 | 連線中切換 session | 原 session ChatViewModel 繼續跑（仍在 AppState 字典中），新 session 顯示自己的 VM 狀態 |
| E-06 | 切回原 session | 看到原本進行中的 streaming / pending approval |
| E-07 | 刪除當前 active session | RULE-1：列表第一個或 nil；不自動建立新的 |
| E-08 | Boot 時 lastSessionId 不存在於 server | 設 `activeSessionId = nil`，顯示空狀態（不 auto-create） |
| E-09 | App 進背景 30s+ 回前景 | `streamStatus` → 重連或重抓 session；同時 poll `approval/pending` |
| E-10 | SSE 收到 `error` event | `errorMessage` 顯示，`isStreaming = false`，啟動 approval polling |
| E-11 | `done` 後又收到 token（錯誤 server 行為） | 已結束的 stream 忽略後續 |
| E-12 | 使用者快速連按 Send | 第二次點擊在 `isStreaming = true` 時 disabled，無事發生 |
| E-13 | `pattern_keys` 為空陣列 | ApprovalCard 不顯示 chip 列，但其他內容正常 |
| E-14 | Markdown 含未閉合 code block | streaming 期間用純文字顯示；`done` 後用 MarkdownUI 渲染（容錯交給 library） |

---

## 6. Codable 型別 reference

### 6.1 `Session`

```json
{
  "session_id": "uuid",
  "title": "string",
  "workspace": "string",
  "model": "string",
  "messages": [ { ...Message } ],
  "created_at": 1700000000.0,
  "updated_at": 1700000050.0,
  "pinned": false,
  "archived": false
}
```

Swift CodingKeys 顯式對應；`title` / `workspace` / `model` 缺漏時 client decode 為空字串。

### 6.2 `Message`

```json
{
  "id": "string?",
  "role": "user" | "assistant" | "system" | "tool",
  "content": "string",
  "attachments": ["string", ...] | null,
  "created_at": 1700000000.0
}
```

`id` 缺漏時 client 自填 `UUID().uuidString`，僅供 SwiftUI `Identifiable`，不回傳給 server。

### 6.3 `Approval`

```json
{
  "id": "string?",
  "command": "string",
  "description": "string?",
  "pattern_keys": ["rm_rf", "sudo", ...],
  "session_id": "string?"
}
```

⚠️ `pattern_keys` 必為複數陣列，client 不接受單數 `pattern_key`（RULE-9）。

### 6.4 `ChatStartResponse`

```json
{ "stream_id": "uuid", "session_id": "uuid?" }
```

### 6.5 `StreamStatus`

```json
{ "stream_id": "uuid", "active": true, "finished": false }
```

### 6.6 `HealthResponse`

```json
{ "status": "ok", "sessions": 3, "version": "0.5.2" }
```

`sessions` 與 `version` 欄位 optional；client 顯示時要 fallback。

---

## 7. 版本與相容性

- 本文件版本綁定 hermes-webui Phase H 階段對外契約。
- 任何 endpoint 改動需同步更新本文件（CLAUDE.md §12.1）。
- Server 引入新 SSE event 類型時，client 仍以 `.unknown` 收下，不視為錯誤；UI 不顯示。
- Server 改 endpoint 路徑必須提供 deprecation window（V2 引入 `Accept-Version` header 機制再議）。

---

**文件結束**
