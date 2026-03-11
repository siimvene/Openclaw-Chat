import Foundation
import Combine
import UIKit

final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
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
    @Published var isPairing = false
    @Published var isTyping = false
    @Published var messages: [ChatMessage] = []
    @Published var statusText = "Disconnected"
    @Published var lastError: String?
    @Published var uptimeMs: Int = 0
    @Published var voiceResponse: String = ""
    @Published var activeModel: String = ""
    
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var wsDelegate: WebSocketDelegate?
    private var token: String = ""
    private var messageId = 0
    private var currentStreamingMessage: UUID?
    
    private var reconnectAttempts = 0
    private var gatewayURL: String?
    private var shouldAutoReconnect = true
    private var connectStartedAt: Date?
    private var lastPingAckAt: Date?
    private var reconnectTask: Task<Void, Never>?
    private var pendingRequests: [String: CheckedContinuation<[String: Any]?, Never>] = [:]
    private var requestCounter = 0
    private var responseBuffer = ""
    private var isVoiceMode = false
    private var connectionGeneration = 0
    
    var sessionManager: SessionManager?
    
    // For SecurityAuditor
    var serverVersion: String = "unknown"
    
    var activeSessionKey: String {
        if let sessionId = sessionManager?.activeSessionId {
            return "agent:main:ios:\(sessionId)"
        }
        return "agent:main:ios:therin"
    }
    
    init() {
        loadMessages()
    }
    
    func configure(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        if let sessionId = sessionManager.activeSessionId {
            messages = sessionManager.loadMessages(for: sessionId)
        }
    }
    
    func saveCurrentSession() {
        saveCurrentMessages()
    }
    
    func switchToSession(_ sessionId: String) {
        guard sessionId != sessionManager?.activeSessionId else { return }
        saveCurrentMessages()
        messages = sessionManager?.loadMessages(for: sessionId) ?? []
        currentStreamingMessage = nil
        isTyping = false
    }
    
    /// Fetch gateway health for security audit
    func getHealth() async -> [String: Any]? {
        guard let url = gatewayURL else { return nil }
        
        var healthURL = url
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        if !healthURL.hasPrefix("https://") && !healthURL.hasPrefix("http://") {
            healthURL = "https://" + healthURL
        }
        if !healthURL.hasSuffix("/") { healthURL += "/" }
        healthURL += "health"
        
        guard let requestURL = URL(string: healthURL) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Extract version if present
                if let version = json["version"] as? String {
                    await MainActor.run { self.serverVersion = version }
                }
                return json
            }
        } catch {
            print("Health check failed: \(error)")
        }
        return nil
    }
    
    func connect(url: String, token: String) {
        if isConnecting {
            return
        }
        
        self.token = token
        self.gatewayURL = url
        self.lastError = nil
        self.statusText = "Connecting..."
        self.isConnecting = true
        self.shouldAutoReconnect = true
        self.connectStartedAt = Date()
        self.reconnectTask?.cancel()
        
        // Ensure wss:// prefix
        var wsURL = url
        if !wsURL.hasPrefix("ws://") && !wsURL.hasPrefix("wss://") {
            wsURL = "wss://" + wsURL
        }
        
        guard let url = URL(string: wsURL) else {
            lastError = "Invalid URL"
            isConnecting = false
            return
        }
        
        tearDownSocket()
        
        connectionGeneration += 1
        let generation = connectionGeneration
        
        let delegate = WebSocketDelegate()
        delegate.onOpen = { [weak self] in
            Task { @MainActor in
                guard self?.connectionGeneration == generation else { return }
                self?.statusText = "Authenticating..."
            }
        }
        delegate.onClose = { [weak self] code, reason in
            Task { @MainActor in
                guard self?.connectionGeneration == generation else { return }
                self?.handleSocketClose(code: code, reason: reason)
            }
        }
        wsDelegate = delegate
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        urlSession = session
        
        var request = URLRequest(url: url)
        if let host = url.host {
            request.setValue("https://\(host)", forHTTPHeaderField: "Origin")
        }
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()
        
        receiveMessage(generation: generation)
        startConnectWatchdog(generation: generation)
    }
    
    func disconnect() {
        shouldAutoReconnect = false
        isConnecting = false
        reconnectTask?.cancel()
        tearDownSocket()
        isConnected = false
        statusText = "Disconnected"
    }
    
    /// Called when app returns to foreground - check socket health
    func checkConnectionHealth() {
        guard shouldAutoReconnect else { return }
        guard let url = gatewayURL, !token.isEmpty || !url.isEmpty else { return }
        
        // Guard against being stuck in handshake forever.
        if isConnecting, let started = connectStartedAt, Date().timeIntervalSince(started) > 8 {
            forceReconnect(reason: "Handshake timeout on resume")
            return
        }
        
        // If we think we're connected, verify with a ping
        if webSocket != nil {
            let sentAt = Date()
            webSocket?.sendPing { [weak self] error in
                Task { @MainActor in
                    if error != nil {
                        self?.forceReconnect(reason: "Ping failed on resume")
                    } else {
                        self?.lastPingAckAt = Date()
                    }
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self else { return }
                if self.isConnecting || self.isConnected { return }
                if (self.lastPingAckAt ?? .distantPast) < sentAt {
                    self.forceReconnect(reason: "No ping ack on resume")
                }
            }
        } else if !isConnected && gatewayURL != nil {
            // We should be connected but aren't - reconnect
            forceReconnect(reason: "Missing socket while disconnected")
        }
    }
    
    private func forceReconnect(reason: String) {
        reconnectTask?.cancel()
        tearDownSocket()
        isConnected = false
        isConnecting = false
        reconnectAttempts = 0
        
        if let url = gatewayURL {
            statusText = "Reconnecting..."
            print("[GW] Force reconnect: \(reason)")
            connect(url: url, token: token)
        }
    }
    
    func sendMessage(_ text: String) {
        guard webSocket != nil, isConnected else {
            messages.append(ChatMessage(role: .system, content: "Not connected. Reconnect and try again."))
            saveCurrentMessages()
            checkConnectionHealth()
            return
        }
        
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        saveCurrentMessages()
        sendToGateway(text)
    }
    
    func sendMessageWithImage(_ text: String, imageData: Data) {
        guard webSocket != nil, isConnected else {
            messages.append(ChatMessage(role: .system, content: "Not connected. Reconnect and try again."))
            saveCurrentMessages()
            checkConnectionHealth()
            return
        }
        
        let userMessage = ChatMessage(role: .user, content: text, imageData: imageData)
        messages.append(userMessage)
        saveCurrentMessages()
        sendToGateway(text, imageData: imageData)
    }
    
    func sendVoiceMessage(_ text: String) {
        guard webSocket != nil, isConnected else {
            voiceResponse = ""
            messages.append(ChatMessage(role: .system, content: "Not connected. Reconnect and try again."))
            saveCurrentMessages()
            checkConnectionHealth()
            return
        }
        
        isVoiceMode = true
        voiceResponse = ""
        sendToGateway(text)
    }
    
    func convertToSpeech(_ text: String) async -> Data? {
        guard let response = await sendRequest(method: "tts.convert", params: ["text": text, "provider": "elevenlabs"]) else {
            return nil
        }
        if let audioBase64 = response["audio"] as? String {
            return Data(base64Encoded: audioBase64)
        }
        return nil
    }
    
    
    func fetchActiveModel() async {
        guard let response = await sendRequest(method: "config.get") else { return }
        if let agents = response["agents"] as? [String: Any],
           let defaults = agents["defaults"] as? [String: Any],
           let model = defaults["model"] as? [String: Any],
           let primary = model["primary"] as? String {
            activeModel = primary
        }
    }
    
    
    func cancelPairing() {
        isPairing = false
        disconnect()
    }
    
    func wipeDeviceDataAndChats() {
        messages.removeAll()
        isTyping = false
        currentStreamingMessage = nil
        responseBuffer = ""
        
        guard let manager = sessionManager else {
            saveCurrentMessages()
            return
        }
        
        manager.wipeAllLocalChatData()
        let session = manager.createSession(name: "General")
        manager.selectSession(session)
        saveCurrentMessages()
    }
    
    func clearMessages() {
        messages.removeAll()
        saveCurrentMessages()
    }
    
    // MARK: - Private
    
    private func receiveMessage(generation: Int) {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.connectionGeneration == generation else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveMessage(generation: generation)
                    
                case .failure(let error):
                    self.handleDisconnect(error: error)
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
        
        // Handle challenge
        if type == "event" && event == "connect.challenge" {
            sendConnect()
            return
        }
        
        // Handle hello-ok
        if type == "res",
           let id = json["id"] as? String,
           id == "connect-1",
           let payload = json["payload"] as? [String: Any],
           payload["type"] as? String == "hello-ok" {
            isConnected = true
            isConnecting = false
            statusText = "Connected"
            reconnectAttempts = 0
            connectStartedAt = nil
            if let snapshot = payload["snapshot"] as? [String: Any] {
                uptimeMs = snapshot["uptimeMs"] as? Int ?? 0
            }
            if let server = payload["server"] as? [String: Any] {
                serverVersion = server["version"] as? String ?? serverVersion
            }
            Task { await fetchActiveModel() }
            return
        }
        
        // Handle auth error
        if type == "res",
           let id = json["id"] as? String,
           id == "connect-1",
           let error = json["error"] as? [String: Any] {
            let code = error["code"] as? String ?? "unknown"
            let message = error["message"] as? String ?? "Authentication failed"
            lastError = "\(code): \(message)"
            statusText = "Auth failed"
            isConnected = false
            isConnecting = false
            // Don't auto-reconnect on auth errors
            shouldAutoReconnect = false
            return
        }
        
        if type == "res",
           let id = json["id"] as? String,
           let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(returning: json["payload"] as? [String: Any])
            return
        }
        
        // Handle agent events
        if type == "event" && event == "agent" {
            handleAgentEvent(json)
            return
        }
        
        // Handle agent response
        if type == "res",
           let id = json["id"] as? String,
           id.hasPrefix("agent-") {
            handleAgentResponse(json)
        }
    }
    
    private func handleAgentEvent(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        
        // Skip content events from non-active sessions.
        if let payloadSession = payload["sessionKey"] as? String, payloadSession != activeSessionKey {
            if let sessionId = payloadSession.components(separatedBy: "agent:main:ios:").last,
               let stream = payload["stream"] as? String,
               stream == "lifecycle",
               let data = payload["data"] as? [String: Any],
               let phase = data["phase"] as? String,
               phase == "end" {
                sessionManager?.incrementUnread(for: sessionId)
            }
            return
        }
        
        let stream = payload["stream"] as? String
        
        // Streaming text
        if stream == "assistant",
           let data = payload["data"] as? [String: Any],
           let delta = data["delta"] as? String {
            if isVoiceMode {
                voiceResponse += delta
            } else {
                responseBuffer += delta
            }
        }
        
        // Lifecycle
        if stream == "lifecycle",
           let data = payload["data"] as? [String: Any],
           let phase = data["phase"] as? String {
            
            if phase == "start" {
                isTyping = true
                responseBuffer = ""
                if isVoiceMode {
                    voiceResponse = ""
                }
            } else if phase == "end" {
                isTyping = false
                currentStreamingMessage = nil
                if !isVoiceMode && !responseBuffer.isEmpty {
                    messages.append(ChatMessage(role: .assistant, content: responseBuffer))
                    responseBuffer = ""
                    saveCurrentMessages()
                }
                isVoiceMode = false
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
            "permissions": [:] as [String: Any],
            "locale": Locale.current.identifier,
            "userAgent": "Therin-iOS/1.0.0"
        ]
        
        // Only include auth if token is provided (empty = rely on Tailscale identity)
        if !token.isEmpty {
            params["auth"] = ["token": token]
        }
        
        let request: [String: Any] = [
            "type": "req",
            "id": "connect-1",
            "method": "connect",
            "params": params
        ]
        
        send(request)
    }
    
    private func send(_ dict: [String: Any], onError: ((Error?) -> Void)? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        
        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("Send error: \(error)")
            }
            onError?(error)
        }
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
        
        if let imageData,
           let image = UIImage(data: imageData) {
            let compressed = compressImage(image)
            params["attachments"] = [[
                "type": "image",
                "mimeType": "image/jpeg",
                "content": compressed.base64EncodedString()
            ]]
        }
        
        send([
            "type": "req",
            "id": id,
            "method": "agent",
            "params": params
        ]) { [weak self] error in
            guard let self, let error else { return }
            Task { @MainActor in
                self.isTyping = false
                self.isVoiceMode = false
                self.messages.append(ChatMessage(role: .system, content: "Send failed: \(error.localizedDescription)"))
                self.saveCurrentMessages()
            }
        }
        isTyping = true
    }
    
    private func compressImage(_ image: UIImage) -> Data {
        let maxDim: CGFloat = 1600
        let scale = min(maxDim / image.size.width, maxDim / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.75) ?? Data()
    }
    
    private func handleSocketClose(code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "No reason"
        
        switch code {
        case .policyViolation, .tlsHandshakeFailure:
            lastError = "Socket closed (\(code.rawValue)): \(reasonText)"
            statusText = "Connection rejected"
            isConnected = false
            isConnecting = false
            shouldAutoReconnect = false
            tearDownSocket()
            
        case .abnormalClosure:
            lastError = "Connection closed unexpectedly (1006). Reconnecting..."
            handleDisconnect(error: NSError(domain: "WebSocket", code: Int(code.rawValue), userInfo: [NSLocalizedDescriptionKey: reasonText]))
            
        default:
            lastError = "Socket closed (\(code.rawValue)): \(reasonText)"
            handleDisconnect(error: NSError(domain: "WebSocket", code: Int(code.rawValue), userInfo: [NSLocalizedDescriptionKey: reasonText]))
        }
    }
    
    private func handleDisconnect(error: Error) {
        guard shouldAutoReconnect else { return }
        
        isConnected = false
        isConnecting = false
        statusText = "Disconnected"
        lastError = error.localizedDescription
        
        // Auto-reconnect
        reconnectAttempts += 1
        if reconnectAttempts < 5, let url = gatewayURL {
            reconnectTask?.cancel()
            let delay = reconnectAttempts
            reconnectTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Double(delay * 2) * 1_000_000_000))
                guard let self else { return }
                self.connect(url: url, token: self.token)
            }
        }
    }
    
    private func startConnectWatchdog(generation: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, self.connectionGeneration == generation else { return }
            if self.isConnecting && !self.isConnected {
                self.forceReconnect(reason: "Connect watchdog timeout")
            }
        }
    }
    
    private func tearDownSocket() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        wsDelegate = nil
    }
    
    // MARK: - Persistence
    
    private var messagesKey: String {
        "chatMessages:\(activeSessionKey)"
    }
    
    private func saveCurrentMessages() {
        if let sessionId = sessionManager?.activeSessionId {
            sessionManager?.saveMessages(messages, for: sessionId)
            sessionManager?.updateLastMessage(
                for: sessionId,
                message: messages.last?.content ?? "",
                count: messages.count
            )
        } else {
            let toSave = Array(messages.suffix(100))
            if let data = try? JSONEncoder().encode(toSave) {
                UserDefaults.standard.set(data, forKey: messagesKey)
            }
        }
    }
    
    private func loadMessages() {
        if let data = UserDefaults.standard.data(forKey: messagesKey),
           let loaded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = loaded
        }
    }
    
    // MARK: - Request/Response API
    
    func sendRequest(method: String, params: [String: Any] = [:]) async -> [String: Any]? {
        guard isConnected else { return nil }
        
        requestCounter += 1
        let requestId = "\(method)-\(requestCounter)"
        send([
            "type": "req",
            "id": requestId,
            "method": method,
            "params": params
        ])
        
        return await withCheckedContinuation { continuation in
            pendingRequests[requestId] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let pending = self?.pendingRequests.removeValue(forKey: requestId) {
                    pending.resume(returning: nil)
                }
            }
        }
    }
}
