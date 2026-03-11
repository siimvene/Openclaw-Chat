import Foundation

@MainActor
class SecurityAuditor: ObservableObject {
    @Published var isScanning = false
    @Published var lastReport: AuditReport?
    @Published var scanProgress: Double = 0
    
    private let gateway: GatewayClient
    
    init(gateway: GatewayClient) {
        self.gateway = gateway
        loadLastReport()
    }
    
    func runFullAudit() async {
        isScanning = true
        scanProgress = 0
        
        var findings: [AuditFinding] = []
        
        let cachedURL = UserDefaults.standard.string(forKey: "gatewayURL") ?? ""
        let gatewayVersion = gateway.serverVersion
        
        // Phase 1: Health check
        scanProgress = 0.1
        if let health = await gateway.getHealth() {
            findings.append(contentsOf: auditHealth(health))
        } else {
            findings.append(AuditFinding(
                category: "Connectivity",
                title: "Health endpoint unreachable",
                description: "Could not reach the gateway health endpoint. The gateway may be down or misconfigured.",
                severity: .critical,
                recommendation: "Verify the gateway is running and accessible."
            ))
        }
        
        scanProgress = 0.4
        
        // Phase 2: Connection security (use cached values)
        findings.append(contentsOf: auditConnectionSecurity(url: cachedURL))
        
        scanProgress = 0.8
        
        // Phase 3: App-level security (use cached values)
        findings.append(contentsOf: auditAppSecurity(url: cachedURL))
        
        scanProgress = 1.0
        
        let report = AuditReport(findings: findings, gatewayVersion: gatewayVersion)
        lastReport = report
        saveReport(report)
        
        isScanning = false
    }
    
    // MARK: - Audit Checks
    
    private func auditHealth(_ health: [String: Any]) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        
        // Check version
        if let version = health["version"] as? String {
            findings.append(AuditFinding(
                category: "Gateway",
                title: "Gateway version detected",
                description: "Running gateway version \(version).",
                severity: .info,
                recommendation: "Ensure this is the latest version."
            ))
        }
        
        // Check system resources
        let system = health["system"] as? [String: Any] ?? health
        if let cpu = system["cpu"] as? Double ?? system["cpuPercent"] as? Double, cpu > 90 {
            findings.append(AuditFinding(
                category: "Resources",
                title: "High CPU usage",
                description: "CPU usage is at \(String(format: "%.1f", cpu))%. This may indicate resource exhaustion or a denial-of-service condition.",
                severity: .high,
                recommendation: "Investigate running processes and consider scaling resources."
            ))
        }
        
        if let mem = system["memory"] as? Double ?? system["memoryPercent"] as? Double, mem > 90 {
            findings.append(AuditFinding(
                category: "Resources",
                title: "High memory usage",
                description: "Memory usage is at \(String(format: "%.1f", mem))%. Risk of OOM kills.",
                severity: .high,
                recommendation: "Review memory-intensive processes and consider increasing available memory."
            ))
        }
        
        if let disk = system["disk"] as? Double ?? system["diskPercent"] as? Double, disk > 85 {
            findings.append(AuditFinding(
                category: "Resources",
                title: "Disk space low",
                description: "Disk usage is at \(String(format: "%.1f", disk))%.",
                severity: disk > 95 ? .critical : .medium,
                recommendation: "Free disk space or expand storage to prevent service interruption."
            ))
        }
        
        return findings
    }
    
    private func auditConnectionSecurity(url: String) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        
        // Check if using encrypted transport
        if url.hasPrefix("ws://") || url.hasPrefix("http://") {
            if !url.contains("localhost") && !url.contains("127.0.0.1") {
                findings.append(AuditFinding(
                    category: "Transport",
                    title: "Unencrypted connection",
                    description: "Connected via unencrypted WebSocket (ws://). Traffic can be intercepted.",
                    severity: .critical,
                    recommendation: "Use wss:// (WebSocket over TLS) for all non-localhost connections."
                ))
            } else {
                findings.append(AuditFinding(
                    category: "Transport",
                    title: "Local unencrypted connection",
                    description: "Using unencrypted WebSocket for localhost. Acceptable for development via SSH tunnel.",
                    severity: .info,
                    recommendation: "Ensure SSH tunnel is used for remote gateway access."
                ))
            }
        } else {
            findings.append(AuditFinding(
                category: "Transport",
                title: "Encrypted connection",
                description: "Connection uses TLS encryption.",
                severity: .info,
                recommendation: "No action needed.",
                actionRequired: false
            ))
        }
        
        // Check Tailscale usage
        if url.contains(".ts.net") {
            findings.append(AuditFinding(
                category: "Network",
                title: "Tailscale network detected",
                description: "Connection goes through Tailscale private network, providing end-to-end encryption.",
                severity: .info,
                recommendation: "Ensure Tailscale ACLs are properly configured."
            ))
        }
        
        return findings
    }
    
    private func auditAppSecurity(url: String) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        
        let tokenInKeychain = KeychainService.get(.gatewayToken) != nil
        let tokenInDefaults = UserDefaults.standard.string(forKey: "gatewayToken").map { !$0.isEmpty } ?? false
        
        if tokenInDefaults {
            findings.append(AuditFinding(
                category: "Storage",
                title: "Token stored in UserDefaults",
                description: "The gateway authentication token is stored in UserDefaults, which is not encrypted at rest.",
                severity: .medium,
                recommendation: "Migrate token storage to iOS Keychain for encrypted storage."
            ))
        } else if tokenInKeychain {
            findings.append(AuditFinding(
                category: "Storage",
                title: "Token stored in Keychain",
                description: "Authentication token is stored securely in the iOS Keychain.",
                severity: .info,
                recommendation: "No action needed.",
                actionRequired: false
            ))
        }
        
        return findings
    }
    
    // MARK: - Persistence
    
    private func saveReport(_ report: AuditReport) {
        if let data = try? JSONEncoder().encode(report) {
            UserDefaults.standard.set(data, forKey: "openclaw_audit_report")
        }
    }
    
    private func loadLastReport() {
        if let data = UserDefaults.standard.data(forKey: "openclaw_audit_report"),
           let report = try? JSONDecoder().decode(AuditReport.self, from: data) {
            lastReport = report
        }
    }
}
