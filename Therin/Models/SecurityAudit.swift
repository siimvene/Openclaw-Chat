import Foundation

enum AuditSeverity: String, Codable, CaseIterable {
    case critical
    case high
    case medium
    case low
    case info
    
    var displayName: String {
        rawValue.capitalized
    }
}

struct AuditFinding: Identifiable, Codable {
    let id: UUID
    let category: String
    let title: String
    let description: String
    let severity: AuditSeverity
    let recommendation: String
    var isFixed: Bool
    let actionRequired: Bool
    
    init(category: String, title: String, description: String, severity: AuditSeverity, recommendation: String, isFixed: Bool = false, actionRequired: Bool = true) {
        self.id = UUID()
        self.category = category
        self.title = title
        self.description = description
        self.severity = severity
        self.recommendation = recommendation
        self.isFixed = isFixed
        // Info findings with "No action needed" don't require action
        self.actionRequired = severity == .info ? actionRequired : true
    }
}

struct AuditReport: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var findings: [AuditFinding]
    let gatewayVersion: String
    
    init(findings: [AuditFinding], gatewayVersion: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.findings = findings
        self.gatewayVersion = gatewayVersion
    }
    
    var criticalCount: Int { findings.filter { $0.severity == .critical }.count }
    var highCount: Int { findings.filter { $0.severity == .high }.count }
    var mediumCount: Int { findings.filter { $0.severity == .medium }.count }
    var lowCount: Int { findings.filter { $0.severity == .low }.count }
    var infoCount: Int { findings.filter { $0.severity == .info }.count }
    
    var overallScore: Int {
        guard !findings.isEmpty else { return 100 }
        let weighted = findings.reduce(0) { sum, f in
            let weight: Int
            switch f.severity {
            case .critical: weight = f.isFixed ? 0 : 25
            case .high: weight = f.isFixed ? 0 : 15
            case .medium: weight = f.isFixed ? 0 : 8
            case .low: weight = f.isFixed ? 0 : 3
            case .info: weight = 0
            }
            return sum + weight
        }
        return max(0, 100 - weighted)
    }
}
