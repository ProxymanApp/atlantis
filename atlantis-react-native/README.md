# react-native-atlantis

Capture HTTP/HTTPS traffic from React Native apps and send to [Proxyman](https://proxyman.com) for debugging.

Atlantis for React Native is a thin bridge over the existing [Atlantis iOS](https://github.com/nicksantamaria/atlantis) and [Atlantis Android](https://github.com/nicksantamaria/atlantis/tree/main/atlantis-android) libraries. All network requests made through `fetch()` are automatically captured and forwarded to the Proxyman macOS app over the local network.

## How It Works

- **iOS**: Atlantis swizzles `NSURLSession` methods to intercept all network traffic. Since React Native uses `NSURLSession` under the hood, all `fetch()` calls are captured automatically.
- **Android**: Atlantis injects an OkHttp interceptor into React Native's networking layer via `OkHttpClientProvider`. All `fetch()` calls are captured automatically.

## Requirements

- React Native >= 0.65
- iOS 13.0+
- Android API 26+ (Android 8.0 Oreo)
- [Proxyman macOS app](https://proxyman.com) running on the same network

## Installation

```bash
npm install react-native-atlantis
```

### iOS

```bash
cd ios && pod install
```

Add the following keys to your `Info.plist` to enable Bonjour discovery (required on iOS 14+):

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Atlantis uses the local network to send HTTP traffic to Proxyman for debugging.</string>
<key>NSBonjourServices</key>
<array>
    <string>_Proxyman._tcp</string>
</array>
```

### Android

No additional configuration required. The library auto-links and handles interceptor injection.

## Usage

```typescript
import { start, stop, isRunning } from 'react-native-atlantis';

// Start capturing traffic (in development only)
if (__DEV__) {
  start();
}

// Optionally connect to a specific Mac
start('MacBook-Pro.local');

// Stop capturing
stop();

// Check if running
const running = await isRunning();
```

## API

### `start(hostName?: string): void`

Start Atlantis and begin capturing HTTP/HTTPS traffic. Traffic is sent to the Proxyman macOS app over the local network.

| Parameter | Type | Description |
|-----------|------|-------------|
| `hostName` | `string` (optional) | Hostname of the Mac running Proxyman. If omitted, Atlantis auto-discovers Proxyman on the network. |

### `stop(): void`

Stop Atlantis and cease capturing traffic. Disconnects from Proxyman.

### `isRunning(): Promise<boolean>`

Check if Atlantis is currently running and capturing traffic.

## Example App

The `example/` directory contains a React Native app that demonstrates all supported HTTP methods.

### Setup

```bash
cd atlantis-react-native/example
npm install

# iOS
cd ios && pod install && cd ..
npx react-native run-ios

# Android
npx react-native run-android
```

The example app provides buttons for GET, POST, PUT, DELETE, and error (404) requests to `httpbin.proxyman.app`. Start Atlantis, then tap any button to see the traffic appear in Proxyman.

## Troubleshooting

### iOS: Traffic not showing in Proxyman

1. Ensure your iPhone/simulator and Mac are on the same network
2. Check that `NSLocalNetworkUsageDescription` and `NSBonjourServices` are in `Info.plist`
3. On real devices, accept the local network permission dialog

### Android: Traffic not showing in Proxyman

1. On emulators, Atlantis connects directly to `10.0.2.2:10909` (host machine)
2. On real devices, ensure the device and Mac are on the same Wi-Fi network
3. Check logcat for `Atlantis` tag messages

### General

- Ensure Proxyman is running on your Mac before calling `start()`
- Atlantis only captures `fetch()` traffic. Third-party HTTP libraries that bypass React Native's networking layer may not be captured.

## License

MIT
