# OpenClaw Chat

A native iOS/iPadOS client for [OpenClaw](https://openclaw.io) - connect to your self-hosted AI gateway from anywhere.

![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Screenshots

<p float="left">
  <img src="docs/screenshots/screenshot-sessions.png" width="30%" alt="Sessions" />
  <img src="docs/screenshots/screenshot-chat.png" width="30%" alt="Chat" />
  <img src="docs/screenshots/screenshot-status.png" width="30%" alt="Status" />
</p>

## Features

- **Chat Interface** - Natural conversation with your AI assistant with real-time streaming responses
- **Voice Mode** - Hands-free voice-to-voice interaction. Speak your questions and hear responses read aloud
- **Multiple Sessions** - Organize conversations into separate sessions for different topics or projects
- **Security Audit** - Built-in security scanner to check your gateway configuration
- **Usage Tracking** - Monitor token usage and costs in real-time
- **Tailscale Integration** - Secure connectivity to your gateway over your Tailscale network

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- An OpenClaw gateway instance running on your server
- Gateway access token for authentication
- Network connectivity to your gateway (direct, VPN, or Tailscale)

## Building

1. Clone the repository
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if not already installed:
   ```bash
   brew install xcodegen
   ```
3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
4. Open `ClawChat.xcodeproj` in Xcode
5. Build and run

## Configuration

### Initial Setup

1. Launch the app
2. Enter your OpenClaw gateway URL (e.g., `openclaw.your-tailnet.ts.net`)
3. Enter your gateway access token (found in `~/.openclaw/openclaw.json` → `gateway.auth.token`)
4. Tap Connect

### Device Pairing (First Connection Only)

OpenClaw requires device pairing for security. On first connection, the app will show "Waiting for approval..." while a pairing request is created on your gateway.

**To approve the device**, run this command on your gateway server:

```bash
# List pending pairing requests
openclaw devices list

# Approve the pending request
openclaw devices approve <requestId>
```

Once approved, the app will automatically connect. Future connections from the same device will work without re-approval.

**Auto-approval (optional):** To automatically approve devices that connect with a valid token, you can add a cron job on your gateway:

```bash
# Add to crontab -e
* * * * * /path/to/openclaw devices approve --latest 2>/dev/null
```

## Privacy

All communication happens directly between your device and your gateway. No data passes through third-party servers. See [PRIVACY.md](PRIVACY.md) for details.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

For issues and feature requests, please use [GitHub Issues](https://github.com/siimvene/Openclaw-Chat/issues).
