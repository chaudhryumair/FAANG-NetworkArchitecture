import XCTest
@testable import NetworkArchitecture

final class NetworkArchitectureTests: XCTestCase {
    
    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.patch.rawValue, "PATCH")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
    }
    
    func testNetworkErrorIsRetryable() {
        XCTAssertTrue(NetworkError.timeout.isRetryable)
        XCTAssertTrue(NetworkError.noConnectivity.isRetryable)
        XCTAssertTrue(NetworkError.serverError(statusCode: 503).isRetryable)
        XCTAssertTrue(NetworkError.tooManyRequests(retryAfter: 5).isRetryable)
        XCTAssertFalse(NetworkError.unauthorized.isRetryable)
        XCTAssertFalse(NetworkError.notFound.isRetryable)
        XCTAssertFalse(NetworkError.decoding(NSError(domain: "", code: 0)).isRetryable)
    }
    
    func testNetworkErrorMapping() {
        XCTAssertEqual(NetworkError.map(statusCode: 401, data: nil), .unauthorized)
        XCTAssertEqual(NetworkError.map(statusCode: 403, data: nil), .forbidden)
        XCTAssertEqual(NetworkError.map(statusCode: 404, data: nil), .notFound)
        XCTAssertEqual(NetworkError.map(statusCode: 429, data: nil), .tooManyRequests(retryAfter: nil))
        
        if case .serverError(let code) = NetworkError.map(statusCode: 502, data: nil) {
            XCTAssertEqual(code, 502)
        } else {
            XCTFail("Expected serverError")
        }
    }
    
    func testConfigurationDefaults() {
        let url = URL(string: "https://api.example.com")!
        let config = NetworkConfiguration(baseURL: url)
        
        XCTAssertEqual(config.baseURL, url)
        XCTAssertEqual(config.environment, .production)
        XCTAssertEqual(config.timeout, 30)
        XCTAssertTrue(config.waitsForConnectivity)
        XCTAssertFalse(config.defaultHeaders.isEmpty)
    }
}
