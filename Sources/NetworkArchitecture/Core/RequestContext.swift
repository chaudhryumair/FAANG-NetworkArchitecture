import Foundation

/// Mutable context that travels through the interceptor chain.
public final class RequestContext: @unchecked Sendable {
    public var request: URLRequest
    public var response: URLResponse?
    public var data: Data?
    public var error: Error?
    public var retryCount: Int = 0
    public var metadata: [String: any Sendable] = [:]
    
    public init(request: URLRequest) {
        self.request = request
    }
    
    public var httpResponse: HTTPURLResponse? {
        response as? HTTPURLResponse
    }
    
    public var statusCode: Int? {
        httpResponse?.statusCode
    }
}
