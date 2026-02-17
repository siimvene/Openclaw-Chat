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
    private var isVoiceMode = false  // When true, responses don't go to chat history
    
    // Multi-session support
    var sessionManager: SessionManager?
    
    // Device ID for pairing (persisted)
    private var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "openclaw_device_id") {
            return id
        }
        let id = "ios-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(id, forKey: "openclaw_device_id")
        return id
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
    
    /// Send a message to the gateway without adding to chat history (for voice mode)
    func sendVoiceMessage(_ text: String) {
        isVoiceMode = true
        sendToGateway(text)
    }
    
    private func sendToGateway(_ text: String) {
        messageId += 1
        let id = "agent-\(messageId)"
        let idempotencyKey = "ios-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
        
        var params: [String: Any] = [
            "message": text,
            "idempotencyKey": idempotencyKey,
            "sessionKey": activeSessionKey
        ]
        
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
            sendConnect()
            return
        }
        
        // Handle connect response
        if type == "res", let id = json["id"] as? String, id == "connect-1" {
            if let payload = json["payload"] as? [String: Any],
               payload["type"] as? String == "hello-ok" {
                isConnecting = false
                isConnected = true
                statusText = "Connected"
                reconnectAttempts = 0
                
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
                
                // If NOT_PAIRED, initiate pairing flow
                if errorCode == "NOT_PAIRED" {
                    statusText = "Requesting pairing..."
                    sendPairRequest()
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
                // Chat mode: add to messages as before
                if currentStreamingMessage == nil {
                    isTyping = false
                    let newMessage = ChatMessage(role: .assistant, content: delta)
                    currentStreamingMessage = newMessage.id
                    messages.append(newMessage)
                } else if let idx = messages.firstIndex(where: { $0.id == currentStreamingMessage }) {
                    messages[idx].content += delta
                }
            }
        }
        
        if stream == "lifecycle",
           let data = payload["data"] as? [String: Any],
           let phase = data["phase"] as? String {
            
            if phase == "start" {
                isTyping = true
                if isVoiceMode {
                    voiceResponse = ""  // Clear for new response
                }
            } else if phase == "end" {
                isTyping = false
                currentStreamingMessage = nil
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
                "id": "webchat-ui",  // Use webchat-ui client ID for Control UI compatibility
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
            "userAgent": "OpenClaw-iOS/1.0.0"
        ]
        
        // Only include auth if token is not empty (allows Tailscale identity auth)
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
    
    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        
        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("Send error: \(error)")
            }
        }
    }
    
    private func handleDisconnect(error: Error) {
        print("[GW] Disconnected: \(error.localizedDescription)")
        isConnecting = false
        isConnected = false
        statusText = "Disconnected"
        lastError = error.localizedDescription
        
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
}
