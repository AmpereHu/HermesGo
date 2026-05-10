import Foundation

public enum APIError: Error, LocalizedError, Sendable {
    case notConfigured
    case invalidURL(String)
    case unauthorized
    case forbidden
    case networkFailure(URLError)
    case decoding(String)
    case serverError(status: Int, message: String?)
    case streamFailed(String)
    case sessionNotFound
    case streamClosed
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未設定 server，請先到設定頁完成連線。"
        case .invalidURL(let raw):
            return "Server URL 格式錯誤：\(raw)"
        case .unauthorized:
            return "認證失敗，請確認密碼是否正確。"
        case .forbidden:
            return "沒有權限存取此資源。"
        case .networkFailure(let urlError):
            return "網路錯誤：\(urlError.localizedDescription)"
        case .decoding(let detail):
            return "回應格式無法解析：\(detail)"
        case .serverError(let status, let message):
            if let message {
                return "伺服器錯誤 (\(status))：\(message)"
            }
            return "伺服器錯誤 (\(status))"
        case .streamFailed(let detail):
            return "串流中斷：\(detail)"
        case .sessionNotFound:
            return "找不到指定的 session。"
        case .streamClosed:
            return "串流已關閉。"
        case .unknown(let detail):
            return "未知錯誤：\(detail)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .networkFailure, .streamFailed, .streamClosed, .serverError:
            return true
        default:
            return false
        }
    }
}
