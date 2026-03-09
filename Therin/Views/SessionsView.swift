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
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color.textMuted)
                        .font(.system(size: 14))
                    TextField("Search sessions...", text: $sessionManager.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.glassBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if sessionManager.filteredSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewSessionAlert = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color.appPrimary)
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
                    .tint(.appPrimary)
                }
                .listRowBackground(
                    session.id == sessionManager.activeSessionId
                        ? Color.appPrimary.opacity(0.15)
                        : Color.glassFill
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
            // Session icon with badge
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if isActive {
                        Circle()
                            .fill(Color.onlineGreen)
                            .frame(width: 8, height: 8)
                    }
                    
                    Spacer()
                    
                    Text(relativeDate(session.lastMessageDate))
                        .font(.system(size: 11))
                        .foregroundColor(Color.textMuted)
                }
                
                if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.system(size: 13))
                        .foregroundColor(Color.textMuted)
                        .lineLimit(1)
                }
                
                HStack {
                    Text("\(session.messageCount) messages")
                        .font(.system(size: 11))
                        .foregroundColor(Color.textMuted)
                    
                    Spacer()
                    
                    if session.unreadCount > 0 {
                        Text("\(session.unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.appPrimary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    private var iconName: String {
        if session.isStarred { return "star.fill" }
        return "bubble.left"
    }
    
    private var iconColor: Color {
        if session.isStarred { return .yellow }
        return Color.appPrimary
    }
    
    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
