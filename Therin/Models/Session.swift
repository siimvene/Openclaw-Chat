import Foundation

struct Session: Identifiable, Codable {
    let id: String
    var name: String
    var lastMessage: String
    var lastMessageDate: Date
    var isStarred: Bool
    var unreadCount: Int
    var messageCount: Int
    
    var sessionKey: String {
        "agent:main:ios:\(id)"
    }
    
    init(id: String = UUID().uuidString.prefix(8).lowercased().description,
         name: String = "New Chat",
         lastMessage: String = "",
         lastMessageDate: Date = Date(),
         isStarred: Bool = false,
         unreadCount: Int = 0,
         messageCount: Int = 0) {
        self.id = id
        self.name = name
        self.lastMessage = lastMessage
        self.lastMessageDate = lastMessageDate
        self.isStarred = isStarred
        self.unreadCount = unreadCount
        self.messageCount = messageCount
    }
}

struct SessionMessages: Codable {
    let sessionId: String
    var messages: [ChatMessage]
}
