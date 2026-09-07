import Foundation

nonisolated struct OdysseusWidgetSnapshot: Codable, Equatable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var generatedAt: Date
    var activeAgents: [OdysseusWidgetAgentSummary]
    var todayStats: OdysseusWidgetTodayStats
    var needsAttention: [OdysseusWidgetAttentionItem]
    var latestMemorySummary: String?
    var privacy: OdysseusWidgetPrivacySettings

    static let empty = OdysseusWidgetSnapshot(
        schemaVersion: schemaVersion,
        generatedAt: Date(),
        activeAgents: [],
        todayStats: OdysseusWidgetTodayStats(),
        needsAttention: [],
        latestMemorySummary: nil,
        privacy: OdysseusWidgetPrivacySettings()
    )
}

nonisolated struct OdysseusWidgetAgentSummary: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var status: String
    var caption: String?
    var updatedAt: Date
}

nonisolated struct OdysseusWidgetTodayStats: Codable, Equatable {
    var voiceInteractions: Int
    var agentTasksCreated: Int
    var agentCompletions: Int
    var agentFailures: Int
    var logReviewComments: Int

    init(
        voiceInteractions: Int = 0,
        agentTasksCreated: Int = 0,
        agentCompletions: Int = 0,
        agentFailures: Int = 0,
        logReviewComments: Int = 0
    ) {
        self.voiceInteractions = voiceInteractions
        self.agentTasksCreated = agentTasksCreated
        self.agentCompletions = agentCompletions
        self.agentFailures = agentFailures
        self.logReviewComments = logReviewComments
    }
}

nonisolated struct OdysseusWidgetAttentionItem: Codable, Identifiable, Equatable {
    nonisolated enum Kind: String, Codable, Equatable {
        case failedAgent
        case missingPermission
        case missingCredential
        case flaggedLog
        case staleSnapshot
    }

    var id: UUID
    var kind: Kind
    var title: String
    var detail: String?
    var createdAt: Date
    var deepLink: URL?

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        detail: String? = nil,
        createdAt: Date = Date(),
        deepLink: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
        self.deepLink = deepLink
    }
}

nonisolated struct OdysseusWidgetPrivacySettings: Codable, Equatable {
    var widgetsEnabled: Bool
    var includesAgentTaskNames: Bool
    var includesMemorySnippets: Bool
    var includesFocusedAppContext: Bool

    init(
        widgetsEnabled: Bool = true,
        includesAgentTaskNames: Bool = false,
        includesMemorySnippets: Bool = false,
        includesFocusedAppContext: Bool = false
    ) {
        self.widgetsEnabled = widgetsEnabled
        self.includesAgentTaskNames = includesAgentTaskNames
        self.includesMemorySnippets = includesMemorySnippets
        self.includesFocusedAppContext = includesFocusedAppContext
    }
}

nonisolated enum OdysseusWidgetDeepLink {
    static let agents = URL(string: "odysseus://agents")!
    static let settings = URL(string: "odysseus://settings")!
    static let logs = URL(string: "odysseus://logs")!
    static let memory = URL(string: "odysseus://memory")!

    static func agent(_ id: UUID) -> URL {
        URL(string: "odysseus://agent/\(id.uuidString)") ?? agents
    }
}
