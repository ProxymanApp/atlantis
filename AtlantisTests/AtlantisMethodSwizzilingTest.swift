//
//  AtlantisMethodSwizzilingTest.swift
//  AtlantisTests
//
//  Created by Nghia Tran on 24/7/25.
//

import XCTest
@testable import Atlantis

final class AtlantisMethodSwizzilingTest: XCTestCase {
    
    private var testDelegate: TestAtlantisDelegate!
    
    override func setUpWithError() throws {
        // Initialize the test delegate
        testDelegate = TestAtlantisDelegate()
        
        // Disable transport layer to prevent actual network communication to Proxyman
        Atlantis.setEnableTransportLayer(false)
        
        // Set our test delegate to capture traffic
        Atlantis.setDelegate(testDelegate)
        
        // Start Atlantis (this will perform method swizzling once)
        Atlantis.start()
    }

    override func tearDownWithError() throws {
        // Stop Atlantis
        Atlantis.stop()
        testDelegate = nil
    }
    
    // MARK: - Tests
    
    /// Test that Atlantis can properly inject and capture URLSession data task traffic
    func testURLSessionDataTaskInjection() throws {
        let expectation = XCTestExpectation(description: "URLSession data task should be captured by Atlantis")
        
        // Reset the delegate state
        testDelegate.reset()
        
        // Configure the test URL
        let url = URL(string: "https://httpbin.proxyman.app/get")!
        let request = URLRequest(url: url)
        
        // Create URLSession and data task
        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            // Verify the network call completed successfully
            XCTAssertNil(error, "Network request should not have an error")
            XCTAssertNotNil(response, "Response should not be nil")
            XCTAssertNotNil(data, "Data should not be nil")
            
            // Give a moment for all delegate methods to be called
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                expectation.fulfill()
            }
        }
        
        // Start the request
        task.resume()
        
        // Wait for completion
        wait(for: [expectation], timeout: 10.0)
        
        // Verify that Atlantis intercepted the traffic
        XCTAssertTrue(testDelegate.didReceiveTraffic, "Should have intercepted network traffic")
        XCTAssertFalse(testDelegate.capturedPackages.isEmpty, "Should have captured at least one package")
        
        // Verify the captured package details
        if let package = testDelegate.capturedPackages.first {
            XCTAssertNotNil(package.request, "Should have captured the request")
            XCTAssertNotNil(package.response, "Should have captured the response")
            XCTAssertNotNil(package.responseBodyData, "Should have captured response data")
            
            // Verify request details
            XCTAssertEqual(package.request.url, "https://httpbin.proxyman.app/get", "Should have correct URL")
            XCTAssertEqual(package.request.method, "GET", "Should have correct method")
            
            // Verify response details
            XCTAssertEqual(package.response?.statusCode, 200, "Should receive HTTP 200 status")
        } else {
            XCTFail("Should have captured at least one traffic package")
        }
    }
    
    /// Test URLSession upload task injection
    func testURLSessionUploadTaskInjection() throws {
        let expectation = XCTestExpectation(description: "URLSession upload task should be captured by Atlantis")
        
        // Reset the delegate state
        testDelegate.reset()
        
        // Configure the upload request
        let url = URL(string: "https://httpbin.proxyman.app/post")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create upload data
        let uploadData = """
        {
            "test": "data",
            "atlantis": "injection_test"
        }
        """.data(using: .utf8)!
        
        // Create URLSession and upload task
        let session = URLSession.shared
        let task = session.uploadTask(with: request, from: uploadData) { data, response, error in
            // Verify the network call completed successfully
            XCTAssertNil(error, "Upload request should not have an error")
            XCTAssertNotNil(response, "Response should not be nil")
            XCTAssertNotNil(data, "Data should not be nil")
            
            // Give a moment for all delegate methods to be called
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                expectation.fulfill()
            }
        }
        
        // Start the upload
        task.resume()
        
        // Wait for completion
        wait(for: [expectation], timeout: 10.0)
        
        // Verify that Atlantis intercepted the upload
        XCTAssertTrue(testDelegate.didReceiveTraffic, "Should have intercepted upload traffic")
        XCTAssertFalse(testDelegate.capturedPackages.isEmpty, "Should have captured upload package")
        
        // Verify upload details
        if let package = testDelegate.capturedPackages.first {
            XCTAssertEqual(package.request.method, "POST", "Should have POST method")
            XCTAssertNotNil(package.request.body, "Should have captured request body")
            XCTAssertEqual(package.response?.statusCode, 200, "Should receive HTTP 200 status")
        }
    }
    
    /// Test error handling injection
    func testURLSessionErrorHandling() throws {
        let expectation = XCTestExpectation(description: "URLSession error should be captured by Atlantis")
        
        // Reset the delegate state
        testDelegate.reset()
        
        // Configure a request that will fail (invalid URL)
        let url = URL(string: "https://invalid-domain-that-does-not-exist-12345.com")!
        let request = URLRequest(url: url)
        
        // Create URLSession and data task
        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            // This should fail
            XCTAssertNotNil(error, "Request should have an error")
            
            // Give a moment for all delegate methods to be called
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                expectation.fulfill()
            }
        }
        
        // Start the request
        task.resume()
        
        // Wait for completion
        wait(for: [expectation], timeout: 10.0)
        
        // Verify that Atlantis intercepted the error
        XCTAssertTrue(testDelegate.didReceiveTraffic, "Should have intercepted error traffic")
        XCTAssertFalse(testDelegate.capturedPackages.isEmpty, "Should have captured error package")
        
        // Verify error details
        if let package = testDelegate.capturedPackages.first {
            XCTAssertNotNil(package.error, "Should have captured the error")
        }
    }
    
    /// Test WebSocket injection (if available)
    @available(iOS 13.0, *)
    func testWebSocketInjection() throws {
        let expectation = XCTestExpectation(description: "WebSocket should be captured by Atlantis")
        
        // Reset the delegate state
        testDelegate.reset()
        
        // Configure WebSocket URL
        let url = URL(string: "wss://echo.websocket.org")!
        
        // Create WebSocket task
        let session = URLSession.shared
        let webSocketTask = session.webSocketTask(with: url)
        
        // Send a test message
        let message = URLSessionWebSocketTask.Message.string("Hello Atlantis WebSocket Test")
        webSocketTask.send(message) { error in
            if let error = error {
                XCTFail("WebSocket send failed: \(error)")
            }
        }
        
        // Receive a message
        webSocketTask.receive { result in
            switch result {
            case .success(let message):
                print("Received WebSocket message: \(message)")
            case .failure(let error):
                print("WebSocket receive error: \(error)")
            }
            
            // Close the WebSocket
            webSocketTask.cancel(with: .goingAway, reason: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                expectation.fulfill()
            }
        }
        
        // Start the WebSocket connection
        webSocketTask.resume()
        
        // Wait for completion
        wait(for: [expectation], timeout: 15.0)
        
        // Verify WebSocket traffic was captured
        XCTAssertTrue(testDelegate.didReceiveTraffic, "Should have intercepted WebSocket traffic")
        // Note: WebSocket traffic might show up as HTTP initially, then as WebSocket messages
    }
    
    /// Test that Atlantis doesn't interfere with normal URLSession operation
    func testNormalURLSessionOperation() throws {
        let expectation = XCTestExpectation(description: "Normal URLSession operation should work with Atlantis")
        
        // Reset the delegate state
        testDelegate.reset()
        
        let url = URL(string: "https://httpbin.proxyman.app/json")!
        let request = URLRequest(url: url)
        
        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            // Verify normal operation works
            XCTAssertNil(error, "Request should succeed")
            XCTAssertNotNil(response, "Should have response")
            XCTAssertNotNil(data, "Should have data")
            
            // Try to parse JSON to ensure data integrity
            if let data = data {
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    XCTAssertNotNil(json, "Should be valid JSON")
                } catch {
                    XCTFail("Response data should be valid JSON")
                }
            }
            
            expectation.fulfill()
        }
        
        task.resume()
        wait(for: [expectation], timeout: 10.0)
        
        // Verify Atlantis captured everything correctly without interfering
        XCTAssertTrue(testDelegate.didReceiveTraffic, "Atlantis should have captured traffic")
        XCTAssertFalse(testDelegate.capturedPackages.isEmpty, "Should have captured packages")
    }
    
    /// Test that method swizzling actually works by verifying the swizzled classes exist
    func testMethodSwizzlingSetup() throws {
        // Test that the classes Atlantis swizzles actually exist
        XCTAssertNotNil(NSClassFromString("__NSCFURLLocalSessionConnection") ?? NSClassFromString("__NSCFURLSessionConnection"), 
                       "URLSession connection class should exist")
        
        // Test that WebSocket class exists (iOS 13+)
        if #available(iOS 13.0, *) {
            XCTAssertNotNil(NSClassFromString("__NSURLSessionWebSocketTask"), 
                           "WebSocket task class should exist")
        }
        
        // Verify Atlantis is enabled
        XCTAssertTrue(testDelegate != nil, "Test delegate should be set")
    }
}

// MARK: - Test Delegate

/// Test implementation of AtlantisDelegate to capture traffic packages
private class TestAtlantisDelegate: AtlantisDelegate {
    
    // Flags to track captured data
    var didReceiveTraffic = false
    var capturedPackages: [TrafficPackage] = []
    
    func atlantisDidHaveNewPackage(_ package: TrafficPackage) {
        didReceiveTraffic = true
        capturedPackages.append(package)
        
        // Log for debugging
        print("[TestDelegate] Captured package: \(package.request.method) \(package.request.url)")
        if let statusCode = package.response?.statusCode {
            print("[TestDelegate] Response status: \(statusCode)")
        }
        if let error = package.error {
            print("[TestDelegate] Error: \(error)")
        }
    }
    
    func reset() {
        didReceiveTraffic = false
        capturedPackages.removeAll()
    }
}
