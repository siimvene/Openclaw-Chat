import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    
    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
