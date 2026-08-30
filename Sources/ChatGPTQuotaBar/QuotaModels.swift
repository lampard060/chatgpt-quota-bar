import Foundation

struct QuotaWindow: Equatable {
    let remainingPercent: Int
    let resetsAt: Date?
    let durationMinutes: Int?

    init?(dictionary: [String: Any]?) {
        guard let dictionary,
              let usedPercent = dictionary["usedPercent"] as? Int else {
            return nil
        }

        remainingPercent = max(0, min(100, 100 - usedPercent))
        if let timestamp = dictionary["resetsAt"] as? TimeInterval {
            resetsAt = Date(timeIntervalSince1970: timestamp)
        } else if let timestamp = dictionary["resetsAt"] as? Int {
            resetsAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
        } else {
            resetsAt = nil
        }
        durationMinutes = dictionary["windowDurationMins"] as? Int
    }
}

struct CreditsSnapshot: Equatable {
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool

    init?(dictionary: [String: Any]?) {
        guard let dictionary,
              let hasCredits = dictionary["hasCredits"] as? Bool,
              let unlimited = dictionary["unlimited"] as? Bool else {
            return nil
        }

        if let balance = dictionary["balance"] as? String {
            self.balance = balance
        } else if let balance = dictionary["balance"] as? NSNumber {
            // The desktop client has returned both JSON strings and numbers here.
            self.balance = balance.stringValue
        } else {
            self.balance = nil
        }
        self.hasCredits = hasCredits
        self.unlimited = unlimited
    }
}

struct ResetCredit: Equatable {
    let title: String?
    let status: String?
    let expiresAt: Date?

    init?(dictionary: [String: Any]) {
        guard let status = dictionary["status"] as? String else { return nil }

        title = dictionary["title"] as? String
        self.status = status
        if let timestamp = dictionary["expiresAt"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: timestamp)
        } else if let timestamp = dictionary["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
        } else {
            expiresAt = nil
        }
    }
}

struct QuotaSnapshot: Equatable {
    let planType: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let credits: CreditsSnapshot?
    let resetCreditCount: Int?
    let resetCredits: [ResetCredit]

    static func parseRPCResponse(_ object: Any) throws -> QuotaSnapshot {
        guard let envelope = object as? [String: Any] else {
            throw QuotaError.invalidResponse("响应不是 JSON 对象")
        }
        if let error = envelope["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "额度接口返回错误"
            throw QuotaError.rpc(message)
        }
        guard let result = envelope["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            throw QuotaError.invalidResponse("响应缺少 rateLimits")
        }

        let resetSummary = result["rateLimitResetCredits"] as? [String: Any]
        let resetCredits = (resetSummary?["credits"] as? [[String: Any]] ?? []).compactMap(ResetCredit.init)
        return QuotaSnapshot(
            planType: limits["planType"] as? String,
            primary: QuotaWindow(dictionary: limits["primary"] as? [String: Any]),
            secondary: QuotaWindow(dictionary: limits["secondary"] as? [String: Any]),
            credits: CreditsSnapshot(dictionary: limits["credits"] as? [String: Any]),
            resetCreditCount: (resetSummary?["availableCount"] as? NSNumber)?.intValue,
            resetCredits: resetCredits
        )
    }
}

struct QuotaStatusFormatter {
    let timeZone: TimeZone

    init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    func title(for snapshot: QuotaSnapshot) -> String? {
        guard let primary = snapshot.primary,
              let secondary = snapshot.secondary else {
            return nil
        }

        let primaryReset = primary.resetsAt.map { timeFormatter.string(from: $0) } ?? "--:--"
        let secondaryReset = secondary.resetsAt.map { dateFormatter.string(from: $0) } ?? "--/--"
        return "5h \(primary.remainingPercent)% ↻\(primaryReset) · 周 \(secondary.remainingPercent)% ↻\(secondaryReset)"
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d"
        return formatter
    }
}

enum QuotaError: LocalizedError {
    case executableMissing
    case launch(String)
    case timeout
    case rpc(String)
    case invalidResponse(String)
    case serverExited(Int32)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "未找到 ChatGPT 内置额度服务"
        case .launch(let message):
            return "无法启动额度服务：\(message)"
        case .timeout:
            return "读取额度超时"
        case .rpc(let message):
            return message
        case .invalidResponse(let message):
            return "额度数据格式异常：\(message)"
        case .serverExited(let code):
            return "额度服务意外退出（\(code)）"
        }
    }
}
