import SwiftUI

// MARK: - Models

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let capability: String
    let params: String
    let result: String
}

// MARK: - App Store

@Observable
public final class AppStore: @unchecked Sendable {
    public var counter: Int = 0
    public var username: String = "Guest"
    public var items: [String] = [
        "Morning Standup", "Design Review", "Sprint Planning", "API Integration",
        "Code Review", "Remo Demo", "Release Notes", "User Testing",
        "Launch Prep", "Post-mortem", "Architecture Review", "Performance Audit",
        "Accessibility Pass", "Localization Check", "Security Review", "Dependency Update",
        "Changelog Draft", "Beta Feedback", "Stakeholder Sync", "Ship It",
    ]
    public var currentRoute: String = "home"

    var accentColorName: String = "blue"
    var toastMessage: String?
    var showConfetti: Bool = false
    var activityLog: [LogEntry] = []

    public init() {}

    var accentColor: Color {
        switch accentColorName {
        case "red": .red
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "pink": .pink
        case "yellow": .yellow
        case "mint": .mint
        case "teal": .teal
        default: .blue
        }
    }

    func log(capability: String, params: String, result: String) {
        let entry = LogEntry(
            timestamp: .now,
            capability: capability,
            params: params,
            result: result
        )
        DispatchQueue.main.async { [self] in
            activityLog.insert(entry, at: 0)
            if activityLog.count > 200 {
                activityLog = Array(activityLog.prefix(200))
            }
        }
    }
}
