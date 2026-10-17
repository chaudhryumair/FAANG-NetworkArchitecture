import Foundation

/// Circuit breaker states following the classic production pattern.
public enum CircuitState: Sendable {
    case closed
    case open(until: Date)
    case halfOpen
}

/// Production-grade circuit breaker interceptor.
///
/// Tracks consecutive failures per host. When the failure threshold is reached
the circuit opens and subsequent requests fail fast for a cool-down period.
/// After the cool-down the circuit becomes half-open and allows a single probe.
public actor CircuitBreakerInterceptor: Interceptor {
    
    public let failureThreshold: Int
    public let recoveryTimeout: TimeInterval
    public let halfOpenMaxCalls: Int
    
    private var states: [String: CircuitState] = [:]
    private var failureCounts: [String: Int] = [:]
    private var halfOpenSuccesses: [String: Int] = [:]
    
    public init(
        failureThreshold: Int = 5,
        recoveryTimeout: TimeInterval = 30,
        halfOpenMaxCalls: Int = 1
    ) {
        self.failureThreshold = failureThreshold
        self.recoveryTimeout = recoveryTimeout
        self.halfOpenMaxCalls = halfOpenMaxCalls
    }
    
    nonisolated public func prepare(_ context: RequestContext) async throws {
        try await self._prepare(context)
    }
    
    nonisolated public func process(_ context: RequestContext) async throws {
        try await self._process(context)
    }
    
    // MARK: - Private
    
    private func _prepare(_ context: RequestContext) async throws {
        guard let host = context.request.url?.host else { return }
        
        let state = currentState(for: host)
        
        switch state {
        case .open(let until):
            if Date() < until {
                throw NetworkError.circuitOpen(host: host, retryAfter: until.timeIntervalSinceNow)
            } else {
                // Transition to half-open
                states[host] = .halfOpen
                halfOpenSuccesses[host] = 0
            }
        case .halfOpen:
            // Allow limited probes
            break
        case .closed:
            break
        }
    }
    
    private func _process(_ context: RequestContext) async throws {
        guard let host = context.request.url?.host else { return }
        
        let isSuccess: Bool
        if let status = context.statusCode {
            isSuccess = (200..<500).contains(status) // 4xx are client errors – do not trip circuit
        } else if context.error != nil {
            isSuccess = false
        } else {
            isSuccess = true
        }
        
        if isSuccess {
            recordSuccess(for: host)
        } else {
            // Only count server errors / transport failures
            if let status = context.statusCode, (500..<600).contains(status) {
                recordFailure(for: host)
            } else if context.error != nil {
                recordFailure(for: host)
            }
        }
    }
    
    private func currentState(for host: String) -> CircuitState {
        if let state = states[host] {
            if case .open(let until) = state, Date() >= until {
                return .halfOpen
            }
            return state
        }
        return .closed
    }
    
    private func recordSuccess(for host: String) {
        let state = currentState(for: host)
        switch state {
        case .halfOpen:
            let count = (halfOpenSuccesses[host] ?? 0) + 1
            halfOpenSuccesses[host] = count
            if count >= halfOpenMaxCalls {
                // Close the circuit
                states[host] = .closed
                failureCounts[host] = 0
                halfOpenSuccesses[host] = 0
            }
        case .closed, .open:
            failureCounts[host] = 0
            states[host] = .closed
        }
    }
    
    private func recordFailure(for host: String) {
        let state = currentState(for: host)
        switch state {
        case .halfOpen:
            // Probe failed → re-open
            states[host] = .open(until: Date().addingTimeInterval(recoveryTimeout))
            halfOpenSuccesses[host] = 0
        case .closed, .open:
            let count = (failureCounts[host] ?? 0) + 1
            failureCounts[host] = count
            if count >= failureThreshold {
                states[host] = .open(until: Date().addingTimeInterval(recoveryTimeout))
            }
        }
    }
}
