import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showNewSessionAlert = false
    @State private var newSessionName = ""
    @State private var editingSession: Session?
    @State private var renameText = ""
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search sessions...", text: $sessionManager.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color(white: 0.15))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                if sessionManager.filteredSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .background(Color.black)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewSessionAlert = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .alert("New Session", isPresented: $showNewSessionAlert) {
                TextField("Session name", text: $newSessionName)
                Button("Create") {
                    // Save current messages before creating new session
                    if sessionManager.activeSessionId != nil {
                        gateway.saveCurrentSession()
                    }
                    let name = newSessionName.isEmpty ? nil : newSessionName
                    let session = sessionManager.createSession(name: name)
                    gateway.switchToSession(session.id)
                    sessionManager.selectSession(session)
                    newSessionName = ""
                    selectedTab = 1 // Switch to Chat tab
                }
                Button("Cancel", role: .cancel) {
                    newSessionName = ""
                }
            }
            .alert("Rename Session", isPresented: Binding(
                get: { editingSession != nil },
                set: { if !$0 { editingSession = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let session = editingSession {
                        sessionManager.renameSession(session, to: renameText)
                    }
                    editingSession = nil
                }
                Button("Cancel", role: .cancel) {
                    editingSession = nil
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Sessions")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tap + to start a new conversation")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private var sessionList: some View {
        List {
            ForEach(sessionManager.filteredSessions) { session in
                SessionRow(
                    session: session,
                    isActive: session.id == sessionManager.activeSessionId
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    gateway.switchToSession(session.id)
                    sessionManager.selectSession(session)
                    selectedTab = 1 // Switch to Chat tab
                }
                .swipeActions(edge: .leading) {
                    Button {
                        sessionManager.toggleStar(session)
                    } label: {
                        Label(
                            session.isStarred ? "Unstar" : "Star",
                            systemImage: session.isStarred ? "star.slash" : "star.fill"
                        )
                    }
                    .tint(.yellow)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sessionManager.deleteSession(session)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    Button {
                        renameText = session.name
                        editingSession = session
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .listRowBackground(
                    session.id == sessionManager.activeSessionId
                        ? Color.blue.opacity(0.15)
                        : Color(white: 0.1)
                )
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Star indicator
            if session.isStarred {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    Text(relativeDate(session.lastMessageDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    Text("\(session.messageCount) messages")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if session.unreadCount > 0 {
                        Text("\(session.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
