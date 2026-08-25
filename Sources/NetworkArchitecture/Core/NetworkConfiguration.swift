import Foundation

public enum NetworkEnvironment: String, Sendable, CaseIterable {
    case development
    case staging
    case production
}

public struct NetworkConfiguration: Sendable {
    public let baseURL: URL
    public let environment: NetworkEnvironment
    public let defaultHeaders: [String: String]
    public let timeout: TimeInterval
    public let waitsForConnectivity: Bool
    public let interceptors: [any Interceptor]
    public let decoder: JSONDecoder
    public let encoder: JSONEncoder
    public let urlSessionConfiguration: URLSessionConfiguration
    
    public init(
        baseURL: URL,
        environment: NetworkEnvironment = .production,
        defaultHeaders: [String: String] = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ],
        timeout: TimeInterval = 30,
        waitsForConnectivity: Bool = true,
        interceptors: [any Interceptor] = [],
        decoder: JSONDecoder = .networkDefault,
        encoder: JSONEncoder = .networkDefault,
        urlSessionConfiguration: URLSessionConfiguration? = nil
    ) {
        self.baseURL = baseURL
        self.environment = environment
        self.defaultHeaders = defaultHeaders
        self.timeout = timeout
        self.waitsForConnectivity = waitsForConnectivity
        self.interceptors = interceptors
        self.decoder = decoder
        self.encoder = encoder
        
        let config = urlSessionConfiguration ?? .default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = waitsForConnectivity
        config.httpMaximumConnectionsPerHost = 8
        config.requestCachePolicy = .useProtocolCachePolicy
        
        // Reasonable default cache sizes used by high-scale apps
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,   // 20 MB
            diskCapacity: 100 * 1024 * 1024,    // 100 MB
            diskPath: "NetworkArchitectureCache"
        )
        
        self.urlSessionConfiguration = config
    }
}

public extension JSONDecoder {
    static var networkDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension JSONEncoder {
    static var networkDefault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
