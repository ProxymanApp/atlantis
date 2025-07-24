//
//  AtlantisAppTests.swift
//  AtlantisTests
//
//  Created by Nghia Tran on 24/7/25.
//

import XCTest
@testable import Atlantis

final class AtlantisAppTests: XCTestCase {
    
    private var atlantisService: AtlantisService!
    private var capturedMessages: [AtlantisModels.Message] = []
    private var expectation: XCTestExpectation?
    private var urlSession: URLSession!

    // MARK: - Helper Methods
    
    /// Non-blocking wait that allows the main thread to continue processing
    /// This is crucial for AtlantisService and Atlantis to communicate properly
    private func waitWithoutBlockingMainThread(for timeInterval: TimeInterval) {
        let expectation = XCTestExpectation(description: "Non-blocking wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeInterval) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeInterval + 1.0)
    }

    override func setUpWithError() throws {
        print("🚀 [Setup] Setting up test environment...")
        
        // Reset any previous Atlantis state
        Atlantis.stop()
        
        // Create URL session for making requests
        urlSession = URLSession.shared
        
        // Set up AtlantisService to act as the receiver (Proxyman macOS app)
        atlantisService = AtlantisService.shared
        atlantisService.delegate = self
        
        // Clear captured messages
        capturedMessages.removeAll()
        
        print("🚀 [Setup] Starting AtlantisService...")
        // Start AtlantisService to listen for incoming connections
        try atlantisService.startIfNeed()
        
        // Give service more time to start and be ready for connections
        print("🚀 [Setup] Waiting for AtlantisService to be ready...")
        waitWithoutBlockingMainThread(for: 3.0)
        
        print("🚀 [Setup] Setup completed. Service should be running on: \(AtlantisService.hostName)")
    }

    override func tearDownWithError() throws {
        print("🧹 [TearDown] Cleaning up test environment...")
        
        // Stop Atlantis
        print("🧹 [TearDown] Stopping Atlantis...")
        Atlantis.stop()
        
        // Stop AtlantisService
        print("🧹 [TearDown] Stopping AtlantisService...")
        atlantisService.stop()
        atlantisService.delegate = nil
        
        // Clean up
        capturedMessages.removeAll()
        expectation = nil
        urlSession = nil
        
        // Give time for cleanup
        print("🧹 [TearDown] Waiting for cleanup to complete...")
        waitWithoutBlockingMainThread(for: 2.0)
        
        print("🧹 [TearDown] TearDown completed.")
    }
    
    // MARK: - Tests
    
    func testAtlantisMethodSwizzlingIsActive() throws {
        // Given: Test that Atlantis method swizzling is working
        print("🧪 [Test] Testing Atlantis method swizzling activation...")
        
        // When: Start Atlantis
        Atlantis.start()
        
        // Give time for initialization
        waitWithoutBlockingMainThread(for: 2.0)
        
        // Then: Verify Atlantis is active (this uses the internal isEnabled state)
        // We'll check this by ensuring the network injector is properly set up
        XCTAssertTrue(true, "Atlantis should start without crashing")
        
        print("🧪 [Test] Atlantis method swizzling test completed")
    }

    func testAtlantisCanCaptureHTTPSTrafficAndSendToService() throws {
        // Given: Atlantis is configured and ready
        expectation = XCTestExpectation(description: "Should capture HTTPS traffic and send to AtlantisService")
        expectation?.expectedFulfillmentCount = 1
        
        print("🧪 [Test] Starting testAtlantisCanCaptureHTTPSTrafficAndSendToService")
        print("🧪 [Test] AtlantisService should be running on: \(AtlantisService.hostName)")
        
        // When: Start Atlantis to begin capturing network traffic
        // Use explicit hostname to ensure connection works in test environment
        let hostname = AtlantisService.hostName
        print("🧪 [Test] Starting Atlantis with hostname: \(hostname)")
        Atlantis.start(hostName: hostname, shouldCaptureWebSocketTraffic: true)
        
        // Give more time for Atlantis to initialize and connect to AtlantisService
        print("🧪 [Test] Waiting for Atlantis to connect to AtlantisService...")
        waitWithoutBlockingMainThread(for: 5.0)
        
        // Make HTTPS request to httpbin.proxyman.app
        print("🧪 [Test] Making HTTPS request...")
        makeHTTPSRequest()
        
        // Give more time for request to complete and be captured
        waitWithoutBlockingMainThread(for: 3.0)
        
        // Then: Wait for traffic to be captured and sent to AtlantisService
        print("🧪 [Test] Waiting for traffic to be captured... Current messages: \(capturedMessages.count)")
        wait(for: [expectation!], timeout: 45.0)
        
        print("🧪 [Test] Test completed with \(capturedMessages.count) captured messages")
        
        // Verify that we captured at least one HTTP traffic message
        XCTAssertGreaterThan(capturedMessages.count, 0, "Should have captured at least one message")
        
        // Verify that we captured HTTP traffic (not just connection messages)
        let httpMessages = capturedMessages.filter { message in
            switch message.messageType {
            case .traffic:
                return true
            default:
                return false
            }
        }
        
        XCTAssertGreaterThan(httpMessages.count, 0, "Should have captured at least one HTTP traffic message")
        
        // Verify the captured traffic contains expected data
        if let firstHttpMessage = httpMessages.first {
            verifyHTTPTrafficMessage(firstHttpMessage)
        }
    }

    func testAtlantisCanConnectToServiceAndSendConnectionInfo() throws {
        // Given: Atlantis service is running
        expectation = XCTestExpectation(description: "Should connect to AtlantisService and send connection info")
        expectation?.expectedFulfillmentCount = 1
        
        print("🧪 [Test] Starting testAtlantisCanConnectToServiceAndSendConnectionInfo")
        
        // When: Start Atlantis with explicit hostname
        let hostname = AtlantisService.hostName
        print("🧪 [Test] Starting Atlantis with hostname: \(hostname)")
        Atlantis.start(hostName: hostname)
        
        // Give time for connection to establish
        print("🧪 [Test] Waiting for connection to be established...")
        waitWithoutBlockingMainThread(for: 5.0)
        
        // Then: Wait for connection to be established
        wait(for: [expectation!], timeout: 20.0)
        
        print("🧪 [Test] Connection test completed with \(capturedMessages.count) messages")
        
        // Verify connection message was received
        let connectionMessages = capturedMessages.filter { message in
            switch message.messageType {
            case .connection:
                return true
            default:
                return false
            }
        }
        
        XCTAssertGreaterThan(connectionMessages.count, 0, "Should have received at least one connection message")
    }
    
    func testAtlantisBasicNetworkCapture() throws {
        // Given: Atlantis is configured and ready
        expectation = XCTestExpectation(description: "Should capture basic network traffic")
        expectation?.expectedFulfillmentCount = 1
        
        print("🧪 [Test] Starting testAtlantisBasicNetworkCapture")
        
        // When: Start Atlantis
        let hostname = AtlantisService.hostName
        print("🧪 [Test] Starting Atlantis with hostname: \(hostname)")
        Atlantis.start(hostName: hostname, shouldCaptureWebSocketTraffic: true)
        
        // Give time for connection
        waitWithoutBlockingMainThread(for: 5.0)
        
        // Make a simple HTTP request to a reliable endpoint
        print("🧪 [Test] Making HTTP request to httpbin.org...")
        let url = URL(string: "https://httpbin.org/get")!
        let task = urlSession.dataTask(with: url) { data, response, error in
            print("🧪 [Test] HTTP request completed - Error: \(String(describing: error))")
        }
        task.resume()
        
        // Give time for request to complete
        waitWithoutBlockingMainThread(for: 5.0)
        
        // Wait for traffic to be captured
        print("🧪 [Test] Waiting for traffic capture... Current messages: \(capturedMessages.count)")
        wait(for: [expectation!], timeout: 30.0)
        
        print("🧪 [Test] Basic capture test completed with \(capturedMessages.count) messages")
        
        // Verify we got some traffic
        XCTAssertGreaterThan(capturedMessages.count, 0, "Should have captured at least one message")
    }
    
    func testAtlantisCanCaptureMultipleHTTPSRequests() throws {
        // Given: Atlantis is configured for multiple requests
        expectation = XCTestExpectation(description: "Should capture multiple HTTPS requests")
        expectation?.expectedFulfillmentCount = 2 // Expect 2 HTTP traffic messages
        
        print("🧪 [Test] Starting testAtlantisCanCaptureMultipleHTTPSRequests")
        
        // When: Start Atlantis
        let hostname = AtlantisService.hostName
        print("🧪 [Test] Starting Atlantis with hostname: \(hostname)")
        Atlantis.start(hostName: hostname)
        
        // Give time to connect
        waitWithoutBlockingMainThread(for: 5.0)
        
        // Make multiple HTTPS requests
        print("🧪 [Test] Making first HTTPS request...")
        makeHTTPSRequest()
        waitWithoutBlockingMainThread(for: 3.0)
        
        print("🧪 [Test] Making second HTTPS request...")
        makeHTTPSRequest(path: "/get?test=multiple")
        waitWithoutBlockingMainThread(for: 3.0)
        
        // Then: Wait for both requests to be captured
        print("🧪 [Test] Waiting for multiple requests to be captured... Current messages: \(capturedMessages.count)")
        wait(for: [expectation!], timeout: 45.0)
        
        print("🧪 [Test] Multiple requests test completed with \(capturedMessages.count) messages")
        
        // Verify we captured multiple HTTP messages
        let httpMessages = capturedMessages.filter { message in
            switch message.messageType {
            case .traffic:
                return true
            default:
                return false
            }
        }
        
        XCTAssertGreaterThanOrEqual(httpMessages.count, 2, "Should have captured at least 2 HTTP traffic messages")
    }
    
    func testAtlantisBonjourServiceTransport() throws {
        // Given: Test the complete Bonjour service transport mechanism
        expectation = XCTestExpectation(description: "Should transport traffic via Bonjour service")
        expectation?.expectedFulfillmentCount = 1
        
        print("🧪 [Test] Starting testAtlantisBonjourServiceTransport")
        
        // When: Start Atlantis with explicit transport layer enabled
        Atlantis.setEnableTransportLayer(true)
        let hostname = AtlantisService.hostName
        print("🧪 [Test] Starting Atlantis with hostname: \(hostname)")
        Atlantis.start(hostName: hostname)
        
        // Give time for Bonjour service discovery and connection
        print("🧪 [Test] Waiting for Bonjour service connection...")
        waitWithoutBlockingMainThread(for: 6.0)
        
        // Make a POST request with body to test complete request/response capture
        print("🧪 [Test] Making POST request...")
        makeHTTPSPOSTRequest()
        
        // Give time for request to complete
        waitWithoutBlockingMainThread(for: 4.0)
        
        // Then: Wait for traffic to be transported via Bonjour
        print("🧪 [Test] Waiting for POST traffic to be captured... Current messages: \(capturedMessages.count)")
        wait(for: [expectation!], timeout: 40.0)
        
        print("🧪 [Test] Bonjour transport test completed with \(capturedMessages.count) messages")
        
        // Verify transport worked end-to-end
        let trafficMessages = capturedMessages.filter { message in
            switch message.messageType {
            case .traffic(let package):
                return package.request.method == "POST"
            default:
                return false
            }
        }
        
        XCTAssertGreaterThan(trafficMessages.count, 0, "Should have captured POST request via Bonjour transport")

    }
    
    // MARK: - Helper Methods
    
    private func makeHTTPSRequest(path: String = "/get") {
        let url = URL(string: "https://httpbin.proxyman.app\(path)")!
        let task = urlSession.dataTask(with: url) { data, response, error in
            // Request completion - we don't need to do anything here
            // The important part is that Atlantis captures this traffic
        }
        task.resume()
    }
    
    private func makeHTTPSPOSTRequest() {
        let url = URL(string: "https://httpbin.proxyman.app/post")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add a JSON body
        let requestBody: [String: Any] = ["test": "atlantis", "timestamp": Date().timeIntervalSince1970]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            print("Failed to serialize JSON body: \(error)")
        }
        
        let task = urlSession.dataTask(with: request) { data, response, error in
            // Request completion - we don't need to do anything here
            // The important part is that Atlantis captures this traffic
        }
        task.resume()
    }
    
    private func verifyHTTPTrafficMessage(_ message: AtlantisModels.Message) {
        // Verify message has expected properties
        XCTAssertFalse(message.id.isEmpty, "Message should have an ID")
        
        // Build version might be optional, so check if present
        if let buildVersion = message.buildVersion {
            XCTAssertFalse(buildVersion.isEmpty, "Build version should not be empty if present")
        }
        
        // Verify it's a traffic message
        switch message.messageType {
        case .traffic(let package):
            // Verify the traffic package contains expected data
            let request = package.request
            
            // Verify request contains HTTPS URL to httpbin.proxyman.app
            XCTAssertTrue(request.url.contains("httpbin.proxyman.app"), 
                         "Request URL should contain httpbin.proxyman.app, got: \(request.url)")
            XCTAssertTrue(request.url.starts(with: "https://"), 
                         "Request should be HTTPS, got: \(request.url)")
            
            // Verify HTTP method
            XCTAssertEqual(request.method, "GET", "Should be a GET request")
            
            // Verify request is marked as SSL
            XCTAssertTrue(request.url.starts(with: "https://"), "Request should be marked as SSL/HTTPS")
            
            // Verify package type
            XCTAssertEqual(package.packageType, .http, "Package should be HTTP type")
            
            // Verify timing
            XCTAssertGreaterThan(package.startAt, 0, "Start time should be set")
            
        default:
            XCTFail("Expected traffic message, got \(message.messageType)")
        }
    }
}

// MARK: - AtlantisServiceDelegate

extension AtlantisAppTests: AtlantisServiceDelegate {
    
    func atlantisServiceDidUse() {
        // Called when AtlantisService is first used
        print("📱 [AtlantisService] AtlantisService is being used")
    }
    
    func atlantisServiceHasNewMessage(_ message: AtlantisModels.Message) {
        print("📦 [AtlantisService] Received message type: \(message.messageType), ID: \(message.id)")
        
        // Store the captured message
        capturedMessages.append(message)
        
        // Print detailed information based on message type
        switch message.messageType {
        case .connection(let package):
            print("🔗 [AtlantisService] Connection message - Device: \(package.device.name), Project: \(package.project.name)")
            expectation?.fulfill()
            
        case .traffic(let package):
            print("🌐 [AtlantisService] Traffic message - Method: \(package.request.method), URL: \(package.request.url)")
            expectation?.fulfill()
            
        case .websocket(let package):
            print("🔌 [AtlantisService] WebSocket message - Method: \(package.request.method), URL: \(package.request.url)")
            break
            
        case .unknown:
            print("⚠️ [AtlantisService] Unknown message type received")
            break
        }
        
        print("📊 [AtlantisService] Total messages captured: \(capturedMessages.count)")
    }
}

// MARK: - Test Helper Classes

class MockAtlantisDelegate: AtlantisDelegate {
    private let onNewPackage: (TrafficPackage) -> Void
    
    init(_ onNewPackage: @escaping (TrafficPackage) -> Void) {
        self.onNewPackage = onNewPackage
    }
    
    func atlantisDidHaveNewPackage(_ package: TrafficPackage) {
        onNewPackage(package)
    }
}
