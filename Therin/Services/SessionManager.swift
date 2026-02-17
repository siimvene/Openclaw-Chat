import Foundation
import Combine

@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var activeSessionId: String?
    @Published var searchText = ""
    
    private let storageKey = "openclaw_sessions"
    private let messagesKeyPrefix = "openclaw_messages_"
    
    var activeSession: Session? {
        sessions.first { $0.id == activeSessionId }
    }
    
    var filteredSessions: [Session] {
        let filtered: [Session]
        if searchText.isEmpty {
            filtered = sessions
        } else {
            let query = searchText.lowercased()
            filtered = sessions.filter {
                $0.name.lowercased().contains(query) ||
                $0.lastMessage.lowercased().contains(query)
            }
        }
        // Starred first, then by date
        return filtered.sorted { a, b in
            if a.isStarred != b.isStarred { return a.isStarred }
            return a.lastMessageDate > b.lastMessageDate
        }
    }
    
    var totalUnread: Int {
        sessions.reduce(0) { $0 + $1.unreadCount }
    }
    
    init() {
        loadSessions()
        migrateIfNeeded()
    }
    
    // MARK: - Session CRUD
    
    @discardableResult
    func createSession(name: String? = nil) -> Session {
        let session = Session(
            name: name ?? "Chat \(sessions.count + 1)"
        )
        sessions.insert(session, at: 0)
        // Don't set activeSessionId here - let the caller do it via selectSession
        // after gateway.switchToSession has saved current messages
        saveSessions()
        return session
    }
    
    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        UserDefaults.standard.removeObject(forKey: messagesKeyPrefix + session.id)
        if activeSessionId == session.id {
            activeSessionId = sessions.first?.id
        }
        saveSessions()
    }
    
    func renameSession(_ session: Session, to name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].name = name
        saveSessions()
    }
    
    func toggleStar(_ session: Session) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].isStarred.toggle()
        saveSessions()
    }
    
    func selectSession(_ session: Session) {
        activeSessionId = session.id
        markRead(session)
    }
    
    func markRead(_ session: Session) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].unreadCount = 0
        saveSessions()
    }
    
    func incrementUnread(for sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }),
              activeSessionId != sessionId else { return }
        sessions[idx].unreadCount += 1
        saveSessions()
    }
    
    func updateLastMessage(for sessionId: String, message: String, count: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].lastMessage = String(message.prefix(100))
        sessions[idx].lastMessageDate = Date()
        sessions[idx].messageCount = count
        saveSessions()
    }
    
    // MARK: - Message Persistence (per session)
    
    func loadMessages(for sessionId: String) -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: messagesKeyPrefix + sessionId),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return messages
    }
    
    func saveMessages(_ messages: [ChatMessage], for sessionId: String) {
        let toSave = Array(messages.suffix(200))
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: messagesKeyPrefix + sessionId)
        }
    }
    
    // MARK: - Persistence
    
    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([Session].self, from: data) {
            sessions = loaded
            activeSessionId = sessions.first?.id
        }
    }
    
    /// Migrate old single-session messages to multi-session
    private func migrateIfNeeded() {
        guard sessions.isEmpty else { return }
        
        // Check for legacy messages
        if let data = UserDefaults.standard.data(forKey: "chatMessages"),
           let messages = try? JSONDecoder().decode([ChatMessage].self, from: data),
           !messages.isEmpty {
            let session = Session(
                name: "Migrated Chat",
                lastMessage: String(messages.last?.content.prefix(100) ?? ""),
                lastMessageDate: messages.last?.timestamp ?? Date(),
                messageCount: messages.count
            )
            sessions = [session]
            activeSessionId = session.id
            saveMessages(messages, for: session.id)
            saveSessions()
            
            // Clean up legacy key
            UserDefaults.standard.removeObject(forKey: "chatMessages")
        }
    }
}
