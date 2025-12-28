//
//  PerformanceAlertService.swift
//  MCPanel
//
//  Monitors server performance and sends macOS notifications for critical thresholds
//

import Foundation
import UserNotifications

// MARK: - Performance Alert Configuration

struct PerformanceThreshold {
    enum Metric {
        case tps
        case mspt
        case memory  // Percentage (0-100)
    }

    enum Severity {
        case warning
        case critical

        var title: String {
            switch self {
            case .warning: return "Warning"
            case .critical: return "Critical"
            }
        }
    }

    let metric: Metric
    let severity: Severity
    let threshold: Double     // Value to trigger alert
    let sustainedSeconds: Int // Must persist for X seconds before alerting

    var metricName: String {
        switch metric {
        case .tps: return "TPS"
        case .mspt: return "MSPT"
        case .memory: return "Memory"
        }
    }

    var comparison: String {
        switch metric {
        case .tps: return "below"      // TPS < threshold is bad
        case .mspt: return "above"     // MSPT > threshold is bad
        case .memory: return "above"   // Memory > threshold is bad
        }
    }

    func isTriggered(by value: Double) -> Bool {
        switch metric {
        case .tps: return value < threshold
        case .mspt: return value > threshold
        case .memory: return value > threshold
        }
    }
}

// MARK: - Performance Alert Service

@MainActor
class PerformanceAlertService: ObservableObject {

    static let shared = PerformanceAlertService()

    // MARK: - Configuration

    /// Default thresholds for performance alerts
    static let defaultThresholds: [PerformanceThreshold] = [
        // TPS thresholds
        PerformanceThreshold(metric: .tps, severity: .warning, threshold: 18, sustainedSeconds: 30),
        PerformanceThreshold(metric: .tps, severity: .critical, threshold: 15, sustainedSeconds: 10),
        // MSPT thresholds
        PerformanceThreshold(metric: .mspt, severity: .warning, threshold: 45, sustainedSeconds: 30),
        PerformanceThreshold(metric: .mspt, severity: .critical, threshold: 50, sustainedSeconds: 10),
        // Memory thresholds
        PerformanceThreshold(metric: .memory, severity: .warning, threshold: 85, sustainedSeconds: 60),
        PerformanceThreshold(metric: .memory, severity: .critical, threshold: 95, sustainedSeconds: 30),
    ]

    /// Active thresholds (can be customized by user)
    @Published var thresholds: [PerformanceThreshold] = PerformanceAlertService.defaultThresholds

    /// Whether notifications are enabled
    @Published var notificationsEnabled: Bool = true

    /// Cooldown period between repeated alerts for same issue (seconds)
    let alertCooldown: TimeInterval = 300  // 5 minutes

    // MARK: - Tracking State

    /// Track when each threshold violation started (per server)
    private var violationStartTimes: [UUID: [String: Date]] = [:]

    /// Track when we last sent an alert for each threshold (per server)
    private var lastAlertTimes: [UUID: [String: Date]] = [:]

    /// Notification center for authorization
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Initialization

    private init() {
        requestNotificationPermission()
    }

    // MARK: - Permission

    /// Request notification permission from the user
    func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[Alerts] Notification permission error: \(error)")
            } else if granted {
                print("[Alerts] Notification permission granted")
            } else {
                print("[Alerts] Notification permission denied")
            }
        }
    }

    // MARK: - Check Performance

    /// Check a status update against thresholds and send alerts if needed
    func checkPerformance(status: StatusUpdatePayload, serverName: String, serverId: UUID) {
        guard notificationsEnabled else { return }

        let now = Date()
        let memoryPercent = Double(status.usedMemoryMB) / Double(max(status.maxMemoryMB, 1)) * 100

        for threshold in thresholds {
            let value: Double
            switch threshold.metric {
            case .tps: value = status.tps
            case .mspt: value = status.mspt ?? 0
            case .memory: value = memoryPercent
            }

            let key = "\(threshold.metric)-\(threshold.severity)"

            if threshold.isTriggered(by: value) {
                // Violation detected
                if violationStartTimes[serverId]?[key] == nil {
                    // Start tracking this violation
                    if violationStartTimes[serverId] == nil {
                        violationStartTimes[serverId] = [:]
                    }
                    violationStartTimes[serverId]?[key] = now
                }

                // Check if sustained long enough
                if let startTime = violationStartTimes[serverId]?[key] {
                    let duration = now.timeIntervalSince(startTime)

                    if duration >= Double(threshold.sustainedSeconds) {
                        // Check cooldown
                        let lastAlert = lastAlertTimes[serverId]?[key]
                        let shouldAlert = lastAlert == nil || now.timeIntervalSince(lastAlert!) >= alertCooldown

                        if shouldAlert {
                            sendAlert(
                                serverName: serverName,
                                serverId: serverId,
                                threshold: threshold,
                                value: value
                            )

                            if lastAlertTimes[serverId] == nil {
                                lastAlertTimes[serverId] = [:]
                            }
                            lastAlertTimes[serverId]?[key] = now
                        }
                    }
                }
            } else {
                // No violation - reset tracking
                violationStartTimes[serverId]?[key] = nil
            }
        }
    }

    // MARK: - Send Alert

    private func sendAlert(
        serverName: String,
        serverId: UUID,
        threshold: PerformanceThreshold,
        value: Double
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(threshold.severity.title): \(serverName)"

        let valueStr: String
        switch threshold.metric {
        case .tps:
            valueStr = String(format: "%.1f", value)
            content.body = "\(threshold.metricName) is \(valueStr) (below \(Int(threshold.threshold)))"
        case .mspt:
            valueStr = String(format: "%.0f", value)
            content.body = "\(threshold.metricName) is \(valueStr)ms (above \(Int(threshold.threshold))ms)"
        case .memory:
            valueStr = String(format: "%.0f", value)
            content.body = "\(threshold.metricName) usage is \(valueStr)% (above \(Int(threshold.threshold))%)"
        }

        content.sound = threshold.severity == .critical ? .defaultCritical : .default
        content.userInfo = ["serverId": serverId.uuidString]

        // Unique identifier for this alert type on this server
        let identifier = "\(serverId)-\(threshold.metric)-\(threshold.severity)"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        notificationCenter.add(request) { error in
            if let error = error {
                print("[Alerts] Failed to send notification: \(error)")
            } else {
                print("[Alerts] Sent \(threshold.severity) alert for \(serverName): \(threshold.metricName)")
            }
        }
    }

    // MARK: - Clear State

    /// Clear all tracking state for a server (e.g., on disconnect)
    func clearState(for serverId: UUID) {
        violationStartTimes[serverId] = nil
        lastAlertTimes[serverId] = nil
    }
}
