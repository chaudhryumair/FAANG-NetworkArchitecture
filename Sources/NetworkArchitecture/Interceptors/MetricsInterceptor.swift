import Foundation
import os.signpost

/// Lightweight observability interceptor.
/// Emits signposts and stores basic metrics that can be forwarded
/// to Datadog / New Relic / Firebase Performance / custom backends.
public struct MetricsInterceptor: Interceptor {
    
    public struct Metric: Sendable {
        public let requestID: String
        public let method: String
        public let path: String
        public let statusCode: Int?
        public let durationMs: Double
        public let error: String?
        public let cacheHit: Bool
    }
    
    public typealias MetricsHandler = @Sendable (Metric) -> Void
    
    private let handler: MetricsHandler?
    private let log = OSLog(subsystem: "NetworkArchitecture", category: .pointsOfInterest)
    
    public init(handler: MetricsHandler? = nil) {
        self.handler = handler
    }
    
    public func prepare(_ context: RequestContext) async throws {
        let requestID = UUID().uuidString
        context.metadata["requestID"] = requestID
        context.metadata["startTime"] = Date()
        
        let name = "\(context.request.httpMethod ?? "?") \(context.request.url?.path ?? "")"
        os_signpost(.begin, log: log, name: "NetworkRequest", "%{public}s", name)
    }
    
    public func process(_ context: RequestContext) async throws {
        let end = Date()
        let start = context.metadata["startTime"] as? Date ?? end
        let durationMs = end.timeIntervalSince(start) * 1000
        let requestID = context.metadata["requestID"] as? String ?? "unknown"
        let cacheHit = context.metadata["cacheHit"] != nil
        
        let name = "\(context.request.httpMethod ?? "?") \(context.request.url?.path ?? "")"
        os_signpost(.end, log: log, name: "NetworkRequest", "%{public}s", name)
        
        let metric = Metric(
            requestID: requestID,
            method: context.request.httpMethod ?? "",
            path: context.request.url?.path ?? "",
            statusCode: context.statusCode,
            durationMs: durationMs,
            error: context.error?.localizedDescription,
            cacheHit: cacheHit
        )
        
        handler?(metric)
    }
}
