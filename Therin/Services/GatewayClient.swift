import Foundation
import Combine
import UIKit

// Delegate to handle WebSocket lifecycle events
class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onOpen?()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose?(closeCode, reason)
    }
}

@MainActor
class GatewayClient: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isTyping = false
    @Published var messages: [ChatMessage] = []
    @Published var statusText = "Disconnected"
    @Published var lastError: String?
    
    // Server info from connect response
    @Published var serverVersion: String = "Unknown"
    @Published var uptimeMs: Int = 0
    
    // Voice mode response (separate from chat messages)
    @Published var voiceResponse: String = ""
    
    // Pairing state
    @Published var isPairing = false
    @Published var pairingNodeId: String?
    
    private var webSocket: URLSessionWebSocketTask?
    private var token: String = ""
    private var messageId = 0
    private var currentStreamingMessage: UUID?
    private var responseBuffer = ""  // Buffer for non-streaming display
    private var isVoiceMode = false  // When true, responses don't go to chat history
    
    // Multi-session support
    var sessionManager: SessionManager?
    
    // Device identity for cryptographic authentication
    private let deviceIdentity = DeviceIdentity.shared
    
    // Challenge nonce from gateway (for signing)
    private var pendingNonce: String?
    
    // Device ID derived from keypair
    private var deviceId: String {
        deviceIdentity.deviceId
    }
    
    var activeSessionKey: String {
        if let sessionId = sessionManager?.activeSessionId {
            return "agent:main:ios:\(sessionId)"
        }
        return "agent:main:ios:openclaw"
    }
    
    private var reconnectAttempts = 0
    private var gatewayURL: String?
    private var pendingRequests: [String: CheckedContinuation<[String: Any]?, Never>] = [:]
    private var requestCounter = 0
    private var wsDelegate: WebSocketDelegate?
    private var urlSession: URLSession?
    
    init() {}
    
    func configure(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        // Load messages for active session
        if let sessionId = sessionManager.activeSessionId {
            messages = sessionManager.loadMessages(for: sessionId)
        }
    }
    
    func saveCurrentSession() {
        if let currentId = sessionManager?.activeSessionId, !messages.isEmpty {
            sessionManager?.saveMessages(messages, for: currentId)
            sessionManager?.updateLastMessage(
                for: currentId,
                message: messages.last?.content ?? "",
                count: messages.count
            )
        }
    }
    
    func switchToSession(_ sessionId: String) {
        // Don't switch if already on this session
        guard sessionId != sessionManager?.activeSessionId else { return }
        
        // Save current session messages before switching
        saveCurrentSession()
        
        // Load new session messages
        messages = sessionManager?.loadMessages(for: sessionId) ?? []
        currentStreamingMessage = nil
        isTyping = false
    }
    
    func connect(url: String, token: String) {
        // Prevent duplicate connections
        if isConnected || isConnecting {
            print("[GW] Skipping connect - already connected/connecting")
            return
        }
        
        print("[GW] Starting connection to: \(url)")
        self.isConnecting = true
        self.token = token
        self.gatewayURL = url
        self.lastError = nil
        self.reconnectAttempts = 0
        self.statusText = "Connecting..."
        
        // Build WebSocket URL
        var wsURL = url
        if !wsURL.hasPrefix("ws://") && !wsURL.hasPrefix("wss://") {
            let isLocal = wsURL.hasPrefix("localhost") || wsURL.hasPrefix("127.0.0.1") || wsURL.contains(":18789")
            wsURL = (isLocal ? "ws://" : "wss://") + wsURL
        }
        
        if !wsURL.hasSuffix("/gateway") {
            wsURL = wsURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            wsURL += "/gateway"
        }
        
        guard let url = URL(string: wsURL) else {
            lastError = "Invalid URL"
            return
        }
        
        let delegate = WebSocketDelegate()
        delegate.onOpen = { [weak self] in
            Task { @MainActor in
                print("[WS] WebSocket opened")
                self?.statusText = "Connected to WebSocket..."
            }
        }
        delegate.onClose = { [weak self] code, reason in
            Task { @MainActor in
                let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
                print("[WS] WebSocket closed: code=\(code.rawValue) reason=\(reasonStr)")
                self?.handleDisconnect(error: NSError(domain: "WebSocket", code: Int(code.rawValue), userInfo: [NSLocalizedDescriptionKey: "WebSocket closed: \(reasonStr)"]))
            }
        }
        self.wsDelegate = delegate
        
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.urlSession = session
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let scheme = url.scheme, let host = url.host {
            let port = url.port.map { ":\($0)" } ?? ""
            let httpScheme = scheme == "wss" ? "https" : "http"
            request.setValue("\(httpScheme)://\(host)\(port)", forHTTPHeaderField: "Origin")
        }
        
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()
        
        receiveMessage()
        schedulePing()
    }
    
    func disconnect() {
        // Save current messages before disconnecting
        if let sessionId = sessionManager?.activeSessionId {
            sessionManager?.saveMessages(messages, for: sessionId)
        }
        
        // Prevent auto-reconnect
        reconnectAttempts = 999
        gatewayURL = nil
        token = ""
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        wsDelegate = nil
        isConnecting = false
        isConnected = false
        statusText = "Disconnected"
    }
    
    private func schedulePing() {
        guard let ws = webSocket else { return }
        
        ws.sendPing { [weak self] error in
            if let error = error {
                // Only log if not a cancellation error
                if (error as NSError).code != -999 {
                    print("[WS] Ping error: \(error)")
                }
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                // Only continue pinging if still connected
                guard self?.webSocket != nil, self?.isConnected == true else { return }
                self?.schedulePing()
            }
        }
    }
    
    func sendMessage(_ text: String) {
        // Display and send the message
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        saveCurrentMessages()
        
        sendToGateway(text)
    }
    
    /// Send a message with an image attachment
    func sendMessageWithImage(_ text: String, imageData: Data) {
        // Display message with image thumbnail
        let userMessage = ChatMessage(role: .user, content: text, imageData: imageData)
        messages.append(userMessage)
        saveCurrentMessages()
        
        sendToGateway(text, imageData: imageData)
    }
    
    /// Send a message to the gateway without adding to chat history (for voice mode)
    func sendVoiceMessage(_ text: String) {
        isVoiceMode = true
        sendToGateway(text, imageData: nil)
    }
    
    private func sendToGateway(_ text: String, imageData: Data? = nil) {
        messageId += 1
        let id = "agent-\(messageId)"
        let idempotencyKey = "ios-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
        
        var params: [String: Any] = [
            "message": text,
            "idempotencyKey": idempotencyKey,
            "sessionKey": activeSessionKey
        ]
        
        // Add image as attachment if present (compress first to stay under 5MB limit)
        if let imageData = imageData,
           let image = UIImage(data: imageData) {
            let (compressed, mimeType) = compressImage(image)
            params["attachments"] = [
                [
                    "type": "image",
                    "mimeType": mimeType,
                    "content": compressed.base64EncodedString()
                ]
            ]
        }
        
        // Add model override if selected
        let selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? ""
        if !selectedModel.isEmpty {
            params["model"] = selectedModel
        }
        
        let request: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "agent",
            "params": params
        ]
        
        send(request)
        isTyping = true
    }
    
    private func compressImage(_ image: UIImage) -> (Data, String) {
        let maxDim: CGFloat = 1600
        let scale = min(maxDim / image.size.width, maxDim / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return (resized.jpegData(compressionQuality: 0.7) ?? Data(), "image/jpeg")
    }

    private func detectImageMimeType(_ data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        
        var header = [UInt8](repeating: 0, count: 8)
        data.copyBytes(to: &header, count: 8)
        
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 {
            return "image/png"
        }
        // JPEG: FF D8 FF
        if header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF {
            return "image/jpeg"
        }
        // GIF: 47 49 46
        if header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46 {
            return "image/gif"
        }
        // WebP: 52 49 46 46 ... 57 45 42 50
        if header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 {
            return "image/webp"
        }
        
        return nil
    }
    
    func clearMessages() {
        messages.removeAll()
        saveCurrentMessages()
    }
    
    // MARK: - Private
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self?.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self?.receiveMessage()
                    
                case .failure(let error):
                    self?.handleDisconnect(error: error)
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        let type = json["type"] as? String
        let event = json["event"] as? String
        
        if type == "event" && event == "connect.challenge" {
            // Capture the nonce for signing
            if let payload = json["payload"] as? [String: Any],
               let nonce = payload["nonce"] as? String {
                pendingNonce = nonce
                print("[GW] Received challenge nonce: \(nonce.prefix(20))...")
            }
            sendConnect()
            return
        }
        
        // Handle connect response
        if type == "res", let id = json["id"] as? String, id == "connect-1" {
            print("[GW] Connect response: ok=\(json["ok"] ?? "nil")")
            print("[GW] Full connect response: \(json)")
            
            if let payload = json["payload"] as? [String: Any],
               payload["type"] as? String == "hello-ok" {
                print("[GW] Connected successfully!")
                isConnecting = false
                isConnected = true
                statusText = "Connected"
                reconnectAttempts = 0
                pendingNonce = nil
                
                // Extract and store device token if provided
                if let auth = payload["auth"] as? [String: Any],
                   let deviceToken = auth["deviceToken"] as? String,
                   let host = gatewayURL {
                    let hostKey = extractHost(from: host)
                    deviceIdentity.storeDeviceToken(deviceToken, for: hostKey)
                    print("[GW] Stored device token for \(hostKey)")
                    
                    // Log granted scopes
                    if let scopes = auth["scopes"] as? [String] {
                        print("[GW] Granted scopes: \(scopes.joined(separator: ", "))")
                    }
                }
                
                // Extract server info
                if let server = payload["server"] as? [String: Any] {
                    serverVersion = server["version"] as? String ?? "Unknown"
                }
                if let snapshot = payload["snapshot"] as? [String: Any] {
                    uptimeMs = snapshot["uptimeMs"] as? Int ?? 0
                }
                return
            }
            
            // Handle connect error (auth rejection, etc.)
            if json["ok"] as? Bool == false {
                let errorInfo = json["error"] as? [String: Any]
                let errorCode = errorInfo?["code"] as? String ?? "UNKNOWN"
                let errorMessage = errorInfo?["message"] as? String ?? "Connection rejected"
                
                print("[GW] Connect error: \(errorCode) - \(errorMessage)")
                
                // If NOT_PAIRED, the gateway has auto-created a pairing request
                // We need to wait for approval and keep reconnecting
                if errorCode == "NOT_PAIRED" {
                    let details = errorInfo?["details"] as? [String: Any]
                    let requestId = details?["requestId"] as? String
                    print("[GW] Pairing required, requestId: \(requestId ?? "unknown")")
                    
                    isPairing = true
                    isConnecting = true
                    statusText = "Waiting for approval..."
                    
                    // Keep reconnecting to check if pairing was approved
                    // Use a slower reconnect interval while waiting for approval
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        guard let self = self, self.isPairing, let url = self.gatewayURL else { return }
                        self.isConnecting = false
                        self.connect(url: url, token: self.token)
                    }
                    return
                }
                
                isConnecting = false
                isPairing = false
                lastError = "\(errorCode): \(errorMessage)"
                statusText = "Auth failed"
                
                // Don't auto-reconnect on auth errors
                reconnectAttempts = 999
                
                webSocket?.cancel(with: .normalClosure, reason: nil)
                return
            }
        }
        
        // Handle pairing events
        if type == "event" && event == "node.pair.resolved" {
            handlePairResolved(json)
            return
        }
        
        if type == "event" && event == "device.pair.resolved" {
            handleDevicePairResolved(json)
            return
        }
        
        // Handle device token rotation/revocation
        if type == "event" && event == "device.token.rotate" {
            handleDeviceTokenRotate(json)
            return
        }
        
        if type == "event" && event == "device.token.revoke" {
            handleDeviceTokenRevoke()
            return
        }
        
        // Handle pairing response
        if type == "res", let id = json["id"] as? String, id == "pair-1" {
            handlePairResponse(json)
            return
        }
        
        if type == "event" && event == "agent" {
            handleAgentEvent(json)
            return
        }
        
        if type == "res",
           let id = json["id"] as? String,
           id.hasPrefix("agent-") {
            handleAgentResponse(json)
            return
        }
        
        // Handle generic request responses (health, usage, etc.)
        if type == "res",
           let id = json["id"] as? String,
           let continuation = pendingRequests.removeValue(forKey: id) {
            let payload = json["payload"] as? [String: Any]
            continuation.resume(returning: payload)
        }
    }
    
    private func handleAgentEvent(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        
        let payloadSession = payload["sessionKey"] as? String
        let stream = payload["stream"] as? String
        
        // Handle events for non-active sessions
        if let payloadSession = payloadSession, payloadSession != activeSessionKey {
            // Only increment unread once when a message completes, not on every delta
            if stream == "lifecycle",
               let data = payload["data"] as? [String: Any],
               let phase = data["phase"] as? String,
               phase == "end" {
                if let manager = sessionManager {
                    let sessionId = payloadSession.replacingOccurrences(of: "agent:main:ios:", with: "")
                    manager.incrementUnread(for: sessionId)
                }
            }
            return
        }
        
        // Handle events for active session
        if stream == "assistant",
           let data = payload["data"] as? [String: Any],
           let delta = data["delta"] as? String {
            
            if isVoiceMode {
                // Voice mode: accumulate in voiceResponse, don't add to chat
                voiceResponse += delta
            } else {
                // Chat mode: buffer response, show all at once when complete
                responseBuffer += delta
            }
        }
        
        if stream == "lifecycle",
           let data = payload["data"] as? [String: Any],
           let phase = data["phase"] as? String {
            
            if phase == "start" {
                isTyping = true
                responseBuffer = ""  // Clear buffer for new response
                if isVoiceMode {
                    voiceResponse = ""  // Clear for new response
                }
            } else if phase == "end" {
                isTyping = false
                currentStreamingMessage = nil
                if let error = data["error"] as? String {
                    messages.append(ChatMessage(role: .system, content: "Error: \(error)"))
                } else if !isVoiceMode && !responseBuffer.isEmpty {
                    // Show complete response all at once
                    messages.append(ChatMessage(role: .assistant, content: responseBuffer))
                    responseBuffer = ""
                }
                if !isVoiceMode {
                    saveCurrentMessages()
                }
                isVoiceMode = false  // Reset after response complete
            }
        }
    }
    
    private func handleAgentResponse(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        
        let status = payload["status"] as? String
        
        if status == "accepted" {
            isTyping = true
        } else if status == "ok" || status == "error" {
            isTyping = false
            currentStreamingMessage = nil
            
            if status == "error" {
                let error = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                messages.append(ChatMessage(role: .system, content: "Error: \(error)"))
            }
            
            saveCurrentMessages()
        }
    }
    
    private func sendConnect() {
        statusText = "Authenticating..."
        
        var params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "webchat-ui",
                "version": "1.0.0",
                "platform": "ios",
                "mode": "ui"
            ],
            "role": "operator",
            "scopes": ["operator.read", "operator.write"],
            "caps": [],
            "commands": [],
            "permissions": [:],
            "locale": Locale.current.identifier,
            "userAgent": "ClawChat-iOS/1.0.0"
        ]
        
        // Include auth with gateway token
        // Note: deviceToken is only received, not sent - the device identity (keypair) authenticates us
        var authBlock: [String: Any] = [:]
        if !token.isEmpty {
            authBlock["token"] = token
        }
        if !authBlock.isEmpty {
            params["auth"] = authBlock
        }
        
        // Build device identity block with signed challenge
        let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let clientId = "webchat-ui"
        let clientMode = "ui"
        let role = "operator"
        let scopes = ["operator.read", "operator.write"]
        
        var deviceBlock: [String: Any] = [
            "id": deviceId,
            "publicKey": deviceIdentity.publicKeyBase64
        ]
        
        // Sign the full payload if we have a nonce
        if let nonce = pendingNonce {
            let tokenForSigning = authBlock["token"] as? String ?? ""
            if let signature = deviceIdentity.signPayload(
                clientId: clientId,
                clientMode: clientMode,
                role: role,
                scopes: scopes,
                signedAtMs: signedAtMs,
                token: tokenForSigning,
                nonce: nonce
            ) {
                deviceBlock["nonce"] = nonce
                deviceBlock["signature"] = signature
                deviceBlock["signedAt"] = signedAtMs
                print("[GW] Signed device auth payload")
            }
        }
        
        params["device"] = deviceBlock
        
        print("[GW] Connect with device identity: \(deviceId.prefix(16))...")
        
        let request: [String: Any] = [
            "type": "req",
            "id": "connect-1",
            "method": "connect",
            "params": params
        ]
        
        send(request)
    }
    
    // MARK: - Helpers
    
    private func extractHost(from url: String) -> String {
        var cleanUrl = url
        if cleanUrl.hasPrefix("wss://") {
            cleanUrl = String(cleanUrl.dropFirst(6))
        } else if cleanUrl.hasPrefix("ws://") {
            cleanUrl = String(cleanUrl.dropFirst(5))
        }
        return cleanUrl.components(separatedBy: "/").first ?? cleanUrl
    }
    
    // MARK: - Device Pairing
    
    private func sendPairRequest() {
        isPairing = true
        statusText = "Waiting for approval..."
        
        // Get device name
        let deviceName = UIDevice.current.name
        
        let request: [String: Any] = [
            "type": "req",
            "id": "pair-1",
            "method": "node.pair.request",
            "params": [
                "nodeId": deviceId,
                "name": deviceName,
                "platform": "ios",
                "silent": false
            ]
        ]
        
        send(request)
    }
    
    private func handlePairResponse(_ json: [String: Any]) {
        if json["ok"] as? Bool == true {
            // Pairing request submitted successfully, wait for approval
            if let payload = json["payload"] as? [String: Any] {
                pairingNodeId = payload["nodeId"] as? String ?? deviceId
                statusText = "Waiting for approval on gateway..."
                print("[Pairing] Request submitted, nodeId: \(pairingNodeId ?? "unknown")")
            }
        } else {
            // Pairing request failed
            let errorInfo = json["error"] as? [String: Any]
            let errorCode = errorInfo?["code"] as? String ?? "UNKNOWN"
            let errorMessage = errorInfo?["message"] as? String ?? "Pairing failed"
            
            isPairing = false
            isConnecting = false
            lastError = "\(errorCode): \(errorMessage)"
            statusText = "Pairing failed"
            
            webSocket?.cancel(with: .normalClosure, reason: nil)
        }
    }
    
    private func handlePairResolved(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        
        let status = payload["status"] as? String
        let nodeId = payload["nodeId"] as? String
        
        print("[Pairing] Resolved: status=\(status ?? "nil"), nodeId=\(nodeId ?? "nil")")
        
        // Only handle if it's for our device
        guard nodeId == pairingNodeId || nodeId == deviceId else { return }
        
        if status == "approved" {
            // We got approved! Extract and save the token
            if let pairingToken = payload["token"] as? String {
                print("[Pairing] Approved! Got token.")
                
                // Save token to UserDefaults
                UserDefaults.standard.set(pairingToken, forKey: "gatewayToken")
                
                // Update our token and reconnect
                token = pairingToken
                isPairing = false
                statusText = "Approved! Reconnecting..."
                
                // Close current connection and reconnect with token
                webSocket?.cancel(with: .normalClosure, reason: nil)
                
                // Reconnect after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, let url = self.gatewayURL else { return }
                    self.isConnecting = false // Reset to allow reconnect
                    self.connect(url: url, token: pairingToken)
                }
            }
        } else if status == "rejected" {
            isPairing = false
            isConnecting = false
            lastError = "Pairing rejected by gateway"
            statusText = "Pairing rejected"
            pairingNodeId = nil
            
            webSocket?.cancel(with: .normalClosure, reason: nil)
        } else if status == "expired" {
            isPairing = false
            isConnecting = false
            lastError = "Pairing request expired"
            statusText = "Pairing expired"
            pairingNodeId = nil
            
            webSocket?.cancel(with: .normalClosure, reason: nil)
        }
    }
    
    func cancelPairing() {
        isPairing = false
        pairingNodeId = nil
        disconnect()
    }
    
    private func handleDevicePairResolved(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        
        let status = payload["status"] as? String
        let resolvedDeviceId = payload["deviceId"] as? String
        
        print("[GW] Device pair resolved: status=\(status ?? "nil"), deviceId=\(resolvedDeviceId ?? "nil")")
        
        guard resolvedDeviceId == deviceId else { return }
        
        if status == "approved" {
            print("[GW] Device pairing approved!")
            isPairing = false
            statusText = "Approved!"
        } else if status == "rejected" {
            isPairing = false
            isConnecting = false
            lastError = "Device pairing rejected"
            statusText = "Pairing rejected"
            webSocket?.cancel(with: .normalClosure, reason: nil)
        }
    }
    
    private func handleDeviceTokenRotate(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
              let newToken = payload["token"] as? String,
              let host = gatewayURL else { return }
        
        let hostKey = extractHost(from: host)
        deviceIdentity.storeDeviceToken(newToken, for: hostKey)
        print("[GW] Device token rotated and stored")
    }
    
    private func handleDeviceTokenRevoke() {
        guard let host = gatewayURL else { return }
        
        let hostKey = extractHost(from: host)
        deviceIdentity.clearDeviceToken(for: hostKey)
        print("[GW] Device token revoked - will need to re-authenticate")
        
        lastError = "Device token revoked"
        statusText = "Token revoked"
        disconnect()
    }
    
    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            print("[GW] Failed to serialize message to JSON")
            return
        }
        
        print("[GW] Sending WebSocket message, size: \(text.count) bytes")
        
        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("[GW] WebSocket send error: \(error)")
            } else {
                print("[GW] WebSocket message sent successfully")
            }
        }
    }
    
    private func handleDisconnect(error: Error) {
        print("[GW] Disconnected: \(error.localizedDescription)")
        isConnecting = false
        isConnected = false
        lastError = error.localizedDescription

        // Don't auto-reconnect during pairing — the pairing timer handles retries
        if isPairing {
            statusText = "Waiting for approval..."
            print("[GW] In pairing flow, skipping auto-reconnect")
            return
        }

        statusText = "Disconnected"
        reconnectAttempts += 1
        print("[GW] Reconnect attempt \(reconnectAttempts)/5")
        if reconnectAttempts < 5, let url = gatewayURL {
            let delay = Double(reconnectAttempts * 2)
            print("[GW] Scheduling reconnect in \(delay)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.connect(url: url, token: self?.token ?? "")
            }
        } else {
            print("[GW] Max reconnect attempts reached or no URL")
        }
    }
    
    // MARK: - Message Persistence
    
    private func saveCurrentMessages() {
        if let sessionId = sessionManager?.activeSessionId {
            sessionManager?.saveMessages(messages, for: sessionId)
            sessionManager?.updateLastMessage(
                for: sessionId,
                message: messages.last?.content ?? "",
                count: messages.count
            )
        } else {
            // Fallback: save to legacy key
            let toSave = Array(messages.suffix(100))
            if let data = try? JSONEncoder().encode(toSave) {
                UserDefaults.standard.set(data, forKey: "chatMessages")
            }
        }
    }
    
    // MARK: - Gateway API Requests
    
    func sendRequest(method: String, params: [String: Any] = [:]) async -> [String: Any]? {
        guard isConnected else { return nil }
        
        requestCounter += 1
        let reqId = "\(method)-\(requestCounter)"
        
        let request: [String: Any] = [
            "type": "req",
            "id": reqId,
            "method": method,
            "params": params
        ]
        
        return await withCheckedContinuation { continuation in
            pendingRequests[reqId] = continuation
            send(request)
            
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let pending = pendingRequests.removeValue(forKey: reqId) {
                    pending.resume(returning: nil)
                }
            }
        }
    }
    
    func getHealth() async -> [String: Any]? {
        return await sendRequest(method: "health")
    }
    
    func getUsage() async -> [String: Any]? {
        return await sendRequest(method: "usage.status")
    }
    
    func getUsageCost() async -> [String: Any]? {
        return await sendRequest(method: "usage.cost")
    }
    
    func getModels() async -> [[String: Any]]? {
        guard let response = await sendRequest(method: "models.list") else { return nil }
        return response["models"] as? [[String: Any]]
    }
    // MARK: - Server-side TTS
    
    /// Convert text to speech using gateway TTS service (ElevenLabs)
    func convertToSpeech(_ text: String) async -> Data? {
        guard isConnected else {
            print("[TTS] Not connected to gateway")
            return nil
        }
        
        let params: [String: Any] = [
            "text": text,
            "provider": "elevenlabs"
        ]
        
        guard let response = await sendRequest(method: "tts.convert", params: params) else {
            print("[TTS] No response from gateway")
            return nil
        }
        
        if let audioBase64 = response["audio"] as? String,
           let data = Data(base64Encoded: audioBase64) {
            print("[TTS] Received \(data.count) bytes of audio")
            return data
        }
        
        if let errorMsg = response["error"] as? String {
            print("[TTS] Error: \(errorMsg)")
        }
        
        return nil
    }
}
