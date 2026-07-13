
<img src="https://github.com/ProxymanApp/atlantis/blob/0352184d411dbf0a9471967bfdd675cb850b0ccb/images/atlantis_logo.jpg" alt="Capture HTTP, HTTPS, Websocket from iOS with Atlantis by Proxyman" width="60%" height="auto"/>

[![Version](https://img.shields.io/cocoapods/v/atlantis-proxyman.svg?style=flat)](https://cocoapods.org/pods/atlantis-proxyman)
[![Platform](https://img.shields.io/cocoapods/p/atlantis-proxyman.svg?style=flat)](https://cocoapods.org/pods/atlantis-proxyman)
[![Twitter](https://img.shields.io/twitter/url?label=%40proxyman_app&style=social&url=https%3A%2F%2Ftwitter.com%2Fproxyman_app)](https://twitter.com/proxyman_app)
[![License](https://img.shields.io/cocoapods/l/atlantis-proxyman.svg?style=flat)](https://cocoapods.org/pods/atlantis-proxyman)
[Join our Discord Channel](https://discord.gg/tjWEq6Da42)

## Atlantis is developed by Proxyman Team
- Homepage: [https://proxyman.com](https://proxyman.com)
- Twitter: [https://twitter.com/proxyman_app](https://twitter.com/proxyman_app)
- Github: [https://github.com/ProxymanApp](https://github.com/ProxymanApp)

## Features
- [x] ✅ **Automatically** intercept all YOUR HTTP/HTTPS Traffic with 1 click
- [x] ✅ **No Proxy or trust any Certificates**
- [x] ✅ Capture WS/WSS Traffic from URLSessionWebSocketTask
- [x] Automatically capture gRPC-Swift 2 client traffic
- [x] Support iOS Physical Devices and Simulators, including iPhone, iPad, Apple Watch, Apple TV
- [x] **NEW:** Support Android with OkHttp, Retrofit, and Apollo
- [x] Review traffic log from macOS [Proxyman](https://proxyman.com) app ([Github](https://github.com/ProxymanApp/Proxyman))
- [x] Categorize the log by project and devices.
- [x] Ready for Production

![Atlantis: Capture HTTP/HTTPS traffic from iOS app without Proxy and Certificate with Proxyman](/images/Atlantis_Dashboard_1.jpg)

## ⚠️ Note
- Atlantis is built for debugging purposes. Debugging tools (such as Map Local, Breakpoint, and Scripting) don't work.
- If you want to use debugging tools, please use normal Proxy.

## Requirement

### iOS
- macOS Proxyman app
- iOS 16.0+ / macOS 11+ / Mac Catalyst 13.0+ / tvOS 13.0+ / watchOS 10.0+
- Xcode 16.3+ with the Swift 6.1 toolchain
- Automatic gRPC capture requires gRPC-Swift 2 and iOS 18+ / macOS 15+ / tvOS 18+ / watchOS 11+ / visionOS 2+
- A Proxyman build with Atlantis gRPC schema v1 support is required to display captured RPCs

### Android
- See [Atlantis Android](https://github.com/ProxymanApp/atlantis-android) for Android integration.

---

# iOS Integration

## 👉 How to use
### 1. Install Atlantis framework
### Swift Packages Manager (Recommended)
- Add `https://github.com/ProxymanApp/atlantis` to your project

### 2. Add Required settings to `Info.plist`
1. Open your iOS Project -> Open the `Info.plist` file and add the following keys and values:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Atlantis would use Bonjour Service to discover Proxyman app from your local network. Atlantis uses it to transfer the data from your iOS app to Proxyman macOS for debugging purposes.</string>
<key>NSBonjourServices</key>
<array>
    <string>_Proxyman._tcp</string>
</array>
```

- [Info.plist Example](/Example/AtlantisSwiftUIApp/AtlantisSwiftUIApp/Info.plist)
- Reason: Atlantis uses Bonjour Service to transfer the data on your iPhone -> Proxyman macOS. It runs locally on your local network.

### 3. Add Atlantis to your project

#### Swift UI App
- Add Atlantis to your Main SwiftUI App
```swift
import SwiftUI

#if DEBUG
// 1. Import Atlantis
import Atlantis
#endif

@main
struct AtlantisSwiftUIAppApp: App {

    init() {
        // 2. Connect to your Macbook
        #if DEBUG
        Atlantis.start()
        
        // 3. (Optional)
        // If you have many Macbooks on the same WiFi Network, you can specify your Macbook's name
        // Find your Macbook's name by opening Proxyman App -> Certificate Menu -> Install Certificate for iOS -> With Atlantis ->
        // Click on "How to start Atlantis" -> Select "SwiftUI" Tab
        // Atlantis.start(hostName: "Your's Macbook Pro")
        #endif
    }
}
```

#### UIKit App - Swift
- Open file `AppDelegate.swift`

```swift
#if DEBUG
import Atlantis
#endif

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    #if DEBUG
        // 2. Connect to your Macbook
        Atlantis.start()

        // 3. (Optional)
        // If you have many Macbooks on the same WiFi Network, you can specify your Macbook's name
        // Find your Macbook's name by opening Proxyman App -> Certificate Menu -> Install Certificate for iOS -> With Atlantis ->
        // Click on "How to start Atlantis" -> Select "SwiftUI" Tab
        // Atlantis.start(hostName: "Your's Macbook Pro")
    #endif

    return true
}
```

#### UIKit App - Objective-C

```objective-c
#import "Atlantis-Swift.h"

// Or import Atlantis as a module, you can use:
@import Atlantis;

// Add to the end of `application(_:didFinishLaunchingWithOptions:)` in AppDelegate.m file
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    [Atlantis startWithHostName:nil shouldCaptureWebSocketTraffic:YES];
    return YES;
}
```

#### How to get your Mac name
- Useful when you have many Macbooks on the same WiFi Network, and you want to specify which Macbook to connect to.
- You can get the `hostName`: Open Proxyman macOS -> Certificate menu -> Install for iOS -> Atlantis -> How to Start Atlantis -> and copy the `HostName`

![Proxyman get hostname from Atlantis](/images/Atlantis_Dashboard_2.jpg)

### 4. Start capture HTTPS with Atlantis and Proxyman app
1. Open Proxyman for macOS
2. Make sure your iOS devices/simulator and macOS Proxyman are in the **same Wi-Fi network** or connect your iOS Devices to your Mac by a **USB cable**
3. Start your iOS app via Xcode. Works with iOS Simulator or iOS Devices.
4. Proxyman now captures all HTTP/HTTPS, WebSocket, and supported gRPC traffic from your app without client configuration.
5. Enjoy debugging ❤️

## Capture gRPC-Swift 2 Traffic

Atlantis automatically observes client RPCs made by gRPC-Swift 2. Keep the normal `Atlantis.start()` call shown above and start it before the first RPC you want to inspect. The gRPC client may be constructed before Atlantis starts; no client interceptor, system proxy, certificate, transport wrapper, or channel configuration is required.

Captured data includes:

- Logical calls and individual retry or hedging attempts
- Request, response, and trailing metadata, including duplicate and binary values
- Serialized unary and streaming request/response messages
- Local and remote peers, final status, cancellation, and transport failures

Atlantis captures the logical gRPC data before transport compression and TLS. It does not produce a byte-for-byte HTTP/2 trace. Individual payloads larger than 50 MB are represented as omitted, and disconnected buffering is limited to 256 events or 64 MiB.

This integration supports gRPC-Swift 2 clients using the official NIO transports. gRPC-Swift 1, arbitrary SwiftNIO pipelines, AsyncHTTPClient, and server-side RPCs are not captured automatically.

## Capture Websocket Traffic
- By using Atlantis, Proxyman can capture Websocket from `URLSessionWebsocketTask` from iOS out of the box.
- If your app uses 3rd-party Websocket libraries (e.g. Starscream), Atlantis doesn't work because Starscream doesn't use `URLSessionWebsocketTask` under hood.
- Example app: https://github.com/NghiaTranUIT/WebsocketWithProxyman

![Proxyman capture websocket from iOS](./images/capture_ws_proxyman.jpg)

## SwiftUI Example App
Atlantis provides a simple iOS app that can demonstrate how to integrate and use Atlantis and Proxyman. Please follow the following steps:
1. Open Proxyman for macOS
2. Open iOS Project at `./Example/AtlantisSwiftUIApp.xcodeproj`
3. Start the project with any iPhone/iPad Simulator or iPhone/iPad device
4. Tap on some buttons to see the HTTP/HTTPS Request/Response on Proxyman app

<details>
  <summary>Advanced Usage</summary>

By default, if your iOS app uses Apple's Networking classes (e.g. URLSession) or using popular Networking libraries (e.g. Alamofire and AFNetworking) to make an HTTP Request, Atlantis will work **OUT OF THE BOX**.

However, if your app doesn't use any one of them, Atlantis is not able to automatically capture the network traffic. 

To resolve it, Atlantis offers certain functions to help you **manually*** add your Request and Response that will present on the Proxyman app as usual.

#### 1. My app uses C++ Network library and doesn't use URLSession, NSURLSession, or any iOS Networking library
You can construct the Request and Response for Atlantis from the following func
```swift
    /// Handy func to manually add Atlantis' Request & Response, then sending to Proxyman for inspecting
    /// It's useful if your Request & Response are not URLRequest and URLResponse
    /// - Parameters:
    ///   - request: Atlantis' request model
    ///   - response: Atlantis' response model
    ///   - responseBody: The body data of the response
    public class func add(request: Request,
                          response: Response,
                          responseBody: Data?) {
```
- Example:
```swift
@IBAction func getManualBtnOnClick(_ sender: Any) {
    // Init Request and Response
    let header = Header(key: "X-Data", value: "Atlantis")
    let jsonType = Header(key: "Content-Type", value: "application/json")
    let jsonObj: [String: Any] = ["country": "Singapore"]
    let data = try! JSONSerialization.data(withJSONObject: jsonObj, options: [])
    let request = Request(url: "https://proxyman.com/get/data", method: "GET", headers: [header, jsonType], body: data)
    let response = Response(statusCode: 200, headers: [Header(key: "X-Response", value: "Internal Error server"), jsonType])
    let responseObj: [String: Any] = ["error_response": "Not FOund"]
    let responseData = try! JSONSerialization.data(withJSONObject: responseObj, options: [])
    
    // Add to Atlantis and show it on Proxyman app
    Atlantis.add(request: request, response: response, responseBody: responseData)
}
```

#### 2. My app uses GRPC
You can construct the unary Request and Response from GRPC models via the interceptor pattern that is provided by
grpc-swift and leverage this to get a complete log of your calls. 


<details><summary>Here is an example for an AtlantisInterceptor</summary>

```swift
        import Atlantis
        import Foundation
        import GRPC
        import NIO
        import NIOHPACK
        import SwiftProtobuf

        extension HPACKHeaders {
            var atlantisHeaders: [Header] { map { Header(key: $0.name, value: $0.value) } }
        }

        public class AtlantisInterceptor<Request: Message, Response: Message>: ClientInterceptor<Request, Response> {
            private struct LogEntry {
                let id = UUID()
                var path: String = ""
                var started: Date?
                var request: LogRequest = .init()
                var response: LogResponse = .init()
            }

            private struct LogRequest {
                var metadata: [Header] = []
                var messages: [String] = []
                var ended = false
            }

            private struct LogResponse {
                var metadata: [Header] = []
                var messages: [String] = []
                var end: (status: GRPCStatus, metadata: String)?
            }

            private var logEntry = LogEntry()

            override public func send(_ part: GRPCClientRequestPart<Request>,
                                      promise: EventLoopPromise<Void>?,
                                      context: ClientInterceptorContext<Request, Response>)
            {
                logEntry.path = context.path
                if logEntry.started == nil {
                    logEntry.started = Date()
                }
                switch context.type {
                case .clientStreaming, .serverStreaming, .bidirectionalStreaming:
                    streamingSend(part, type: context.type)
                case .unary:
                    unarySend(part)
                }
                super.send(part, promise: promise, context: context)
            }

            private func streamingSend(_ part: GRPCClientRequestPart<Request>, type: GRPCCallType) {
                switch part {
                case .metadata(let metadata):
                    logEntry.request.metadata = metadata.atlantisHeaders
                case .message(let messageRequest, _):
                    Atlantis.addGRPCStreaming(id: logEntry.id,
                                              path: logEntry.path,
                                              message: .data((try? messageRequest.jsonUTF8Data()) ?? Data()),
                                              success: true,
                                              statusCode: 0,
                                              statusMessage: nil,
                                              streamingType: type.streamingType,
                                              type: .send,
                                              startedAt: logEntry.started,
                                              endedAt: Date(),
                                              HPACKHeadersRequest: logEntry.request.metadata,
                                              HPACKHeadersResponse: logEntry.response.metadata)
                case .end:
                    logEntry.request.ended = true
                    switch type {
                    case .unary, .serverStreaming, .bidirectionalStreaming:
                        break
                    case .clientStreaming:
                        Atlantis.addGRPCStreaming(id: logEntry.id,
                                                  path: logEntry.path,
                                                  message: .string("end"),
                                                  success: true,
                                                  statusCode: 0,
                                                  statusMessage: nil,
                                                  streamingType: type.streamingType,
                                                  type: .send,
                                                  startedAt: logEntry.started,
                                                  endedAt: Date(),
                                                  HPACKHeadersRequest: logEntry.request.metadata,
                                                  HPACKHeadersResponse: logEntry.response.metadata)
                    }
                }
            }

            private func unarySend(_ part: GRPCClientRequestPart<Request>) {
                switch part {
                case .metadata(let metadata):
                    logEntry.request.metadata = metadata.atlantisHeaders
                case .message(let messageRequest, _):
                    logEntry.request.messages.append((try? messageRequest.jsonUTF8Data())?.prettyJson ?? "")
                case .end:
                    logEntry.request.ended = true
                }
            }

            override public func receive(_ part: GRPCClientResponsePart<Response>, context: ClientInterceptorContext<Request, Response>) {
                logEntry.path = context.path
                switch context.type {
                case .unary:
                    unaryReceive(part)
                case .bidirectionalStreaming, .serverStreaming, .clientStreaming:
                    streamingReceive(part, type: context.type)
                }
                super.receive(part, context: context)
            }

            private func streamingReceive(_ part: GRPCClientResponsePart<Response>, type: GRPCCallType) {
                switch part {
                case .metadata(let metadata):
                    logEntry.response.metadata = metadata.atlantisHeaders
                case .message(let messageResponse):
                    Atlantis.addGRPCStreaming(id: logEntry.id,
                                              path: logEntry.path,
                                              message: .data((try? messageResponse.jsonUTF8Data()) ?? Data()),
                                              success: true,
                                              statusCode: 0,
                                              statusMessage: nil,
                                              streamingType: type.streamingType,
                                              type: .receive,
                                              startedAt: logEntry.started,
                                              endedAt: Date(),
                                              HPACKHeadersRequest: logEntry.request.metadata,
                                              HPACKHeadersResponse: logEntry.response.metadata)
                case .end(let status, _):
                    Atlantis.addGRPCStreaming(id: logEntry.id,
                                              path: logEntry.path,
                                              message: .string("end"),
                                              success: status.isOk,
                                              statusCode: status.code.rawValue,
                                              statusMessage: status.message,
                                              streamingType: type.streamingType,
                                              type: .receive,
                                              startedAt: logEntry.started,
                                              endedAt: Date(),
                                              HPACKHeadersRequest: logEntry.request.metadata,
                                              HPACKHeadersResponse: logEntry.response.metadata)
                }
            }

            private func unaryReceive(_ part: GRPCClientResponsePart<Response>) {
                switch part {
                case .metadata(let metadata):
                    logEntry.response.metadata = metadata.atlantisHeaders
                case .message(let messageResponse):
                    logEntry.response.messages.append((try? messageResponse.jsonUTF8Data())?.prettyJson ?? "")
                case .end(let status, _):
                    Atlantis.addGRPCUnary(path: logEntry.path,
                                          requestObject: logEntry.request.messages.joined(separator: "\n").data(using: .utf8),
                                          responseObject: logEntry.response.messages.joined(separator: "\n").data(using: .utf8),
                                          success: status.isOk,
                                          statusCode: status.code.rawValue,
                                          statusMessage: status.message,
                                          startedAt: logEntry.started,
                                          endedAt: Date(),
                                          HPACKHeadersRequest: logEntry.request.metadata,
                                          HPACKHeadersResponse: logEntry.response.metadata)
                }
            }

            override public func errorCaught(_ error: Error, context: ClientInterceptorContext<Request, Response>) {
                logEntry.path = context.path
                switch context.type {
                case .unary, .bidirectionalStreaming, .serverStreaming, .clientStreaming:
                    Atlantis.addGRPCUnary(path: logEntry.path,
                                          requestObject: logEntry.request.messages.joined(separator: "\n").data(using: .utf8),
                                          responseObject: logEntry.response.messages.joined(separator: "\n").data(using: .utf8),
                                          success: false,
                                          statusCode: GRPCStatus(code: .unknown, message: "").code.rawValue,
                                          statusMessage: error.localizedDescription,
                                          startedAt: logEntry.started,
                                          endedAt: Date(),
                                          HPACKHeadersRequest: logEntry.request.metadata,
                                          HPACKHeadersResponse: logEntry.response.metadata)
                }

                super.errorCaught(error, context: context)
            }

            override public func cancel(promise: EventLoopPromise<Void>?, context: ClientInterceptorContext<Request, Response>) {
                logEntry.path = context.path
                switch context.type {
                case .unary, .bidirectionalStreaming, .serverStreaming, .clientStreaming:
                    Atlantis.addGRPCUnary(path: logEntry.path,
                                          requestObject: logEntry.request.messages.joined(separator: "\n").data(using: .utf8),
                                          responseObject: logEntry.response.messages.joined(separator: "\n").data(using: .utf8),
                                          success: false,
                                          statusCode: GRPCStatus(code: .cancelled, message: nil).code.rawValue,
                                          statusMessage: "canceled",
                                          startedAt: logEntry.started,
                                          endedAt: Date(),
                                          HPACKHeadersRequest: logEntry.request.metadata,
                                          HPACKHeadersResponse: logEntry.response.metadata)
                }
                super.cancel(promise: promise, context: context)
            }
        }

        extension GRPCCallType {
            var streamingType: Atlantis.GRPCStreamingType {
                switch self {
                case .clientStreaming:
                    return .client
                case .serverStreaming:
                    return .server
                case .bidirectionalStreaming:
                    return .server
                case .unary:
                    fatalError("Unary is not a streaming type")
                }
            }
        }

        private extension Data {
            var prettyJson: String? {
                guard let object = try? JSONSerialization.jsonObject(with: self),
                      let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
                      let prettyPrintedString = String(data: data, encoding: .utf8) else {
                          return nil
                      }
                return prettyPrintedString
            }
        }
```

</details>

- Example:
```swift
    public class YourInterceptorFactory: YourClientInterceptorFactoryProtocol {
        func makeGetYourCallInterceptors() -> [ClientInterceptor<YourRequest, YourResponse>] {
            [AtlantisInterceptor()]
        }
    }

    // Your GRPC services that is generated from SwiftGRPC
    private let client = NoteServiceServiceClient.init(channel: connectionChannel, interceptors: YourInterceptorFactory())
```

#### 3. Use Atlantis on Swift Playground
Atlantis is capable of capturing the HTTP/HTTPS and WS/WSS traffic from your Swift Playground.

1. Use [Arena](https://github.com/finestructure/Arena) to generate a new Swift Playground with Atlantis. If you would like to add Atlantis to your existing Swift Playground, please follow [this tutorial](https://wwdcbysundell.com/2020/importing-swift-packages-into-a-playground-in-xcode12/).
2. Enable Swift Playground Mode
```swift
Atlantis.setIsRunningOniOSPlayground(true)
Atlantis.start()
```

3. Trust Proxyman self-signed certificate

- for macOS: You don't need to do anything if you've already installed & trusted Proxyman Certificate in Certificate Menu -> Install on this Mac.
- for iOS: Since iOS Playground doesn't start any iOS Simulator, it's impossible to inject the Proxyman Certificate. Therefore, we have to manually trust the certificate. Please use [NetworkSSLProxying](https://gist.github.com/NghiaTranUIT/275c8da5068d506869a21bd16da27094) class to do it.

4. Make an HTTP/HTTPS or WS/WSS and inspect it on the Proxyman app.

- Sample Code: https://github.com/ProxymanApp/Atlantis-Swift-Playground-Sample-App


</details>

---

# Android Integration

Atlantis for Android captures HTTP/HTTPS traffic from OkHttp (including Retrofit and Apollo) and sends it to Proxyman for debugging.

> Source code: [github.com/ProxymanApp/atlantis-android](https://github.com/ProxymanApp/atlantis-android)

## 1. Install Atlantis Android

### Gradle (Kotlin DSL)

Add to your app's `build.gradle.kts`:

```kotlin
dependencies {
    debugImplementation("com.proxyman:atlantis-android:1.0.0")
    
    // You must include OkHttp in your project
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
```

### Gradle (Groovy)

```groovy
dependencies {
    debugImplementation 'com.proxyman:atlantis-android:1.0.0'
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
}
```

### JitPack (Alternative)

Add JitPack repository to your `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        maven { url = uri("https://jitpack.io") }
    }
}
```

Then add the dependency:

```kotlin
debugImplementation("com.github.ProxymanApp:atlantis-android:1.0.0")
```

## 2. Initialize Atlantis

### In your Application class

```kotlin
import android.app.Application
import com.proxyman.atlantis.Atlantis

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // Only enable in debug builds
        if (BuildConfig.DEBUG) {
            // Simple start - discovers all Proxyman apps on network
            Atlantis.start(this)
            
            // Or with specific hostname (find it in Proxyman -> Certificate menu)
            // Atlantis.start(this, "MacBook-Pro.local")
        }
    }
}
```

## 3. Add Interceptor to OkHttpClient

```kotlin
import com.proxyman.atlantis.Atlantis
import okhttp3.OkHttpClient

// Create OkHttpClient with Atlantis interceptor
val okHttpClient = OkHttpClient.Builder()
    .addInterceptor(Atlantis.getInterceptor())
    .build()
```

### With Retrofit

```kotlin
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

val retrofit = Retrofit.Builder()
    .baseUrl("https://api.example.com/")
    .client(okHttpClient)  // Use the OkHttpClient with Atlantis
    .addConverterFactory(GsonConverterFactory.create())
    .build()
```

### With Apollo Kotlin

```kotlin
import com.apollographql.apollo3.ApolloClient

val apolloClient = ApolloClient.Builder()
    .serverUrl("https://api.example.com/graphql")
    .okHttpClient(okHttpClient)  // Use the OkHttpClient with Atlantis
    .build()
```

## 4. Required Permissions

Atlantis requires these permissions (automatically added by the library):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

## 5. Start Debugging

1. Open **Proxyman** on your Mac
2. Make sure your Android device/emulator and Mac are on the **same Wi-Fi network**
   - For emulators: Atlantis automatically connects to `10.0.2.2:10909`
   - For physical devices: Uses Network Service Discovery (NSD/mDNS)
3. Run your Android app
4. All HTTP/HTTPS traffic will appear in Proxyman!

## Android Sample App

A sample Android app is included in the [atlantis-android](https://github.com/ProxymanApp/atlantis-android) repo. To run it:

1. Clone [atlantis-android](https://github.com/ProxymanApp/atlantis-android) and open it in Android Studio
2. Run the `sample` module
3. Tap the buttons to make network requests
4. View the traffic in Proxyman

## Android Troubleshooting

### Traffic not appearing in Proxyman?

1. **Emulator**: Make sure Proxyman is running on your Mac. Atlantis connects to `10.0.2.2:10909`.

2. **Physical device**: 
   - Ensure both devices are on the same Wi-Fi network
   - Try specifying the hostname: `Atlantis.start(this, "Your-Mac.local")`

3. **Check logs**: Look for `[Atlantis]` logs in Logcat for connection status.

### OkHttp version compatibility

Atlantis supports OkHttp 4.x and 5.x. If you're using an older version, please upgrade.

---

## ❓ FAQ 
#### 1. How does Atlantis work?

Atlantis uses [Method Swizzling](https://nshipster.com/method-swizzling/) to capture URLSession traffic. For gRPC-Swift 2, it registers a process-wide diagnostics observer in GRPCCore and receives serialized RPC events before the NIO transport applies compression or TLS.

Then it sends to [Proxyman app](https://proxyman.com) via a local Bonjour Service for inspecting.

#### 2. How can Atlantis stream the data to the Proxyman app?

As soon as your iOS app (Atlantis is enabled) and the Proxyman macOS app are the same **local network**, Atlantis could discover the Proxyman app by using [Bonjour Service](https://developer.apple.com/bonjour/). After the connection is established, Atlantis will send the data via Socket.

#### 3. Is it safe to send my network traffic logs to the Proxyman app?

It's completely **safe** since your data is locally transferred between your iOS app and the Proxyman app, no Internet is required. All traffic logs are captures and send to the Proxyman app for inspecting on the fly. 

Atlantis and Proxyman apps do not store any of your data on any server.

#### 4. What kind of data does Atlantis capture?

- All HTTP/HTTPS traffic from your iOS apps, that integrate the Atlantis framework 
- Supported gRPC client metadata, serialized messages, statuses, errors, and retry/hedging identifiers
- Your iOS app name, bundle identifier, and small size of the logo
- iOS devices/simulators name and device models.

**All the above data are not stored anywhere (except in the memory)**. It will be wiped out as soon as you close the app. 

They are required to categorize the traffic on the Proxyman app by project and device name. Therefore, it's easier to know where the request/response comes from.

## Troubleshooting
### 1. I could not see any request from Atlantis on Proxyman app?
For some reason, Bonjour service might not be able to find the Proxyman app. 

=> Make sure your iOS devices and the Mac are in the **same Wi-Fi network** or connect to your Mac with **USB Cable**

=> Please use `Atlantis.start(hostName: "_your_host_name")` version to explicitly tell Atlantis to connect to your Mac.

### 2. I could not use Debugging Tools on Atlantis's requests.
Atlantis is built for inspecting the Network, not debugging purposes. If you would like to use Debugging Tools, please consider using a normal HTTP Proxy


## Credit
- FLEX and maintainer team: https://github.com/FLEXTool/FLEX
- @yagiz from Bagel project: https://github.com/yagiz/Bagel

## License
Atlantis is released under the Apache-2.0 License. See LICENSE for details.
