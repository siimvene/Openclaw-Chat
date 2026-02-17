import SwiftUI

struct SecurityView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var auditor: SecurityAuditor
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: Int
    
    init(gateway: GatewayClient, selectedTab: Binding<Int>) {
        _auditor = StateObject(wrappedValue: SecurityAuditor(gateway: gateway))
        _selectedTab = selectedTab
    }
    
    var body: some View {
        List {
            // Score card
            if let report = auditor.lastReport {
                Section {
                    scoreCard(report)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                
                // Severity summary
                Section("Summary") {
                    severityRow("Critical", count: report.criticalCount, color: .red)
                    severityRow("High", count: report.highCount, color: .orange)
                    severityRow("Medium", count: report.mediumCount, color: .yellow)
                    severityRow("Low", count: report.lowCount, color: .blue)
                    severityRow("Info", count: report.infoCount, color: .secondary)
                }
                
                // Findings by category
                let categories = Set(report.findings.map(\.category)).sorted()
                ForEach(categories, id: \.self) { category in
                    Section(category) {
                        let findings = report.findings.filter { $0.category == category }
                            .sorted { severityOrder($0.severity) < severityOrder($1.severity) }
                        ForEach(findings) { finding in
                            FindingRow(finding: finding) { selectedFinding in
                                startDiscussion(about: selectedFinding)
                            }
                        }
                    }
                }
                
                // Report metadata
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("Gateway v\(report.gatewayVersion)")
                                .font(.caption2)
                            Text("Scanned: \(report.timestamp.formatted(.dateTime))")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } else if !auditor.isScanning {
                Section {
                    Button {
                        Task { await auditor.runFullAudit() }
                    } label: {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 100, height: 100)
                                
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 48))
                                    .foregroundColor(.blue)
                            }
                            
                            Text("Run Security Audit")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Tap to check your gateway configuration")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            // Call-to-action indicator
                            HStack(spacing: 6) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.caption)
                                Text("Tap to start")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(!gateway.isConnected)
                    .listRowBackground(Color.clear)
                }
            }
            
            // Scan progress
            if auditor.isScanning {
                Section {
                    VStack(spacing: 12) {
                        ProgressView(value: auditor.scanProgress)
                            .tint(.blue)
                        Text("Scanning... \(Int(auditor.scanProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Security Audit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Only show rescan button if there's already a report or scanning
                if auditor.lastReport != nil || auditor.isScanning {
                    Button {
                        Task { await auditor.runFullAudit() }
                    } label: {
                        if auditor.isScanning {
                            ProgressView()
                        } else {
                            Label("Rescan", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(auditor.isScanning || !gateway.isConnected)
                }
            }
        }
    }
    
    private func scoreCard(_ report: AuditReport) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(white: 0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: CGFloat(report.overallScore) / 100)
                    .stroke(
                        scoreColor(report.overallScore),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(report.overallScore)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("/ 100")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(scoreLabel(report.overallScore))
                .font(.headline)
                .foregroundColor(scoreColor(report.overallScore))
            
            Text("\(report.findings.count) findings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    private func severityRow(_ label: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
            Spacer()
            Text("\(count)")
                .foregroundColor(.secondary)
                .fontWeight(.medium)
        }
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        if score >= 40 { return .orange }
        return .red
    }
    
    private func scoreLabel(_ score: Int) -> String {
        if score >= 80 { return "Good" }
        if score >= 60 { return "Fair" }
        if score >= 40 { return "Needs Attention" }
        return "Critical"
    }
    
    private func severityOrder(_ severity: AuditSeverity) -> Int {
        switch severity {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        case .info: return 4
        }
    }
    
    private func startDiscussion(about finding: AuditFinding) {
        // Save current session
        gateway.saveCurrentSession()
        
        // Create a new session for this security discussion
        let session = sessionManager.createSession(name: "Security: \(finding.title)")
        sessionManager.selectSession(session)
        gateway.switchToSession(session.id)
        
        // Compose the initial message with finding details
        let prompt = """
        I need help with a security finding from my OpenClaw gateway audit:
        
        **Category:** \(finding.category)
        **Issue:** \(finding.title)
        **Severity:** \(finding.severity.displayName)
        
        **Description:** \(finding.description)
        
        **Recommendation:** \(finding.recommendation)
        
        Can you help me understand this issue and guide me through remediation steps?
        """
        
        // Send the message to start the conversation
        gateway.sendMessage(prompt)
        
        // Switch to Chat tab and dismiss navigation
        selectedTab = 1
        dismiss()
    }
}

// MARK: - Finding Row

struct FindingRow: View {
    let finding: AuditFinding
    let onDiscuss: (AuditFinding) -> Void
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    severityBadge(finding)
                    
                    Text(finding.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(finding.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Recommendation - tappable if action required
                    if finding.actionRequired {
                        Button {
                            onDiscuss(finding)
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(finding.recommendation)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text("Tap to discuss with AI")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.blue)
                            }
                            .padding(10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // No action needed - show green
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text(finding.recommendation)
                                .font(.caption)
                                .foregroundColor(.green.opacity(0.9))
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
    
    private func severityBadge(_ finding: AuditFinding) -> some View {
        let color = badgeColor(finding)
        let icon = finding.actionRequired ? finding.severity.displayName.prefix(1) : "✓"
        
        return Text(icon)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(color)
            .clipShape(Circle())
    }
    
    private func badgeColor(_ finding: AuditFinding) -> Color {
        // If no action required, show green
        if !finding.actionRequired {
            return .green
        }
        switch finding.severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .info: return .secondary
        }
    }
}
