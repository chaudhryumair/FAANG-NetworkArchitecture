import Foundation

/// Production-grade retry with exponential backoff + full jitter + Retry-After support.
/// Matches the strategies used by high-scale mobile clients.
public struct RetryInterceptor: Interceptor {
    
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let retryableStatusCodes: Set<Int>
    
    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 30.0,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.retryableStatusCodes = retryableStatusCodes
    }
    
    public func process(_ context: RequestContext) async throws {
        // Only act when we already have a failure and still have attempts left
        guard context.retryCount < maxAttempts else { return }
        
        let shouldRetry: Bool
        
        if let error = context.error as? NetworkError {
            shouldRetry = error.isRetryable
        } else if let status = context.statusCode {
            shouldRetry = retryableStatusCodes.contains(status)
        } else if context.error is URLError {
            shouldRetry = true
        } else {
            shouldRetry = false
        }
        
        guard shouldRetry else { return }
        
        // Honor Retry-After header when present
        var delay = calculateDelay(attempt: context.retryCount)
        if let retryAfter = parseRetryAfter(from: context.httpResponse) {
            delay = max(delay, retryAfter)
        }
        
        context.retryCount += 1
        
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        // Note: Actual re-execution is handled by higher-level retry loop
        // if the client is configured for it. This interceptor records intent
        // and applies delay. For full automatic retry, wrap the client call.
    }
    
    private func calculateDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff with full jitter
        let exp = min(maxDelay, baseDelay * pow(2.0, Double(attempt)))
        return Double.random(in: 0...exp)
    }
    
    private func parseRetryAfter(from response: HTTPURLResponse?) -> TimeInterval? {
        guard let header = response?.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(header) {
            return seconds
        }
        // HTTP-date format is rarer; basic support can be added if needed
        return nil
    }
}

/// Helper that performs the actual retry loop around any async throwing work.
public func withRetry<T: Sendable>(
    maxAttempts: Int = 3,
    baseDelay: TimeInterval = 0.5,
    maxDelay: TimeInterval = 30,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?
    
    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch let error as NetworkError where error.isRetryable && attempt < maxAttempts - 1 {
            lastError = error
            let exp = min(maxDelay, baseDelay * pow(2.0, Double(attempt)))
            let delay = Double.random(in: 0...exp)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            throw error
        }
    }
    
    throw lastError ?? NetworkError.unknown(NSError(domain: "Retry", code: -1))
}
