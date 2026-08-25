import Foundation
import os.log

public enum LogLevel: Sendable {
    case none
    case basic      // method + URL + status
    case headers    // + headers
    case body       // + body (truncated)
}

public struct LoggingInterceptor: Interceptor {
    
    private let level: LogLevel
    private let logger: Logger
    private let maxBodyLength: Int
    
    public init(level: LogLevel = .headers, subsystem: String = "NetworkArchitecture", maxBodyLength: Int = 2048) {
        self.level = level
        self.logger = Logger(subsystem: subsystem, category: "Networking")
        self.maxBodyLength = maxBodyLength
    }
    
    public func prepare(_ context: RequestContext) async throws {
        guard level != .none else { return }
        
        let method = context.request.httpMethod ?? "?"
        let url = context.request.url?.absoluteString ?? "unknown"
        
        var message = "→ \(method) \(url)"
        
        if level == .headers || level == .body {
            if let headers = context.request.allHTTPHeaderFields, !headers.isEmpty {
                message += "\n  Headers: \(headers)"
            }
        }
        
        if level == .body, let body = context.request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            let truncated = bodyString.prefix(maxBodyLength)
            message += "\n  Body: \(truncated)\(bodyString.count > maxBodyLength ? "…" : "")"
        }
        
        logger.debug("\(message, privacy: .public)")
    }
    
    public func process(_ context: RequestContext) async throws {
        guard level != .none else { return }
        
        let status = context.statusCode.map(String.init) ?? "—"
        let url = context.request.url?.absoluteString ?? "unknown"
        
        var message = "← \(status) \(url)"
        
        if level == .headers || level == .body {
            if let headers = context.httpResponse?.allHeaderFields as? [String: String] {
                message += "\n  Headers: \(headers)"
            }
        }
        
        if level == .body, let data = context.data,
           let bodyString = String(data: data, encoding: .utf8) {
            let truncated = bodyString.prefix(maxBodyLength)
            message += "\n  Body: \(truncated)\(bodyString.count > maxBodyLength ? "…" : "")"
        }
        
        if let error = context.error {
            message += "\n  Error: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
        } else {
            logger.debug("\(message, privacy: .public)")
        }
    }
}
