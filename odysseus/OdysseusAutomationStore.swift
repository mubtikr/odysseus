//
//  OdysseusAutomationStore.swift
//  Odysseus
//
//  JSON-backed automation registry + a single 30-second tick scheduler.
//  Persists to ~/Library/Application Support/Odysseus/automations.json.
//  Uses CompanionManager.submitAgentPromptFromUI(_:) to fire prompts;
//  routes through createAndSelectNewCodexAgentSession(asAgent:) when an
//  automation is bound to a specialist agent slug.
//

import AppKit
import OCAutomation
import Combine
import Foundation

@MainActor
final class OdysseusAutomationStore: ObservableObject {
  static let shared = OdysseusAutomationStore()
  static let skillDiscoveryAutomationName = "App skill discovery"
  private static let skillDiscoveryDefaultDisabledMigrationKey = "OdysseusSkillDiscoveryAutomationDefaultDisabledMigration.v1"

  static var skillDiscoverySuggestionsURL: URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return appSupport
      .appendingPathComponent("Odysseus", isDirectory: true)
      .appendingPathComponent("skill-discovery-suggestions.json", isDirectory: false)
  }

  static var skillSuggestionRulesURL: URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return appSupport
      .appendingPathComponent("Odysseus", isDirectory: true)
      .appendingPathComponent("skill-suggestion-rules.json", isDirectory: false)
  }

  static var skillDiscoveryAutomationPrompt: String {
    """
    Odysseus scheduled skill discovery pass.

    Goal: find useful Agent Mode skills for the apps and workflows the user is actively using, then surface install/connect options in the Odysseus Connect tab.

    Be efficient:
    1. Identify likely active apps/workflows from the current screen/window context, the last few foreground apps recorded by Odysseus, recent Odysseus logs, and obvious local project folders. Keep Odysseus's default suggestions available, but when recent apps are visible, include suggestions tailored to those apps using known skills, MCP/connectors, gog routes, browser automation, or screen-context workflows. Do not overfit to only the immediately previous app, and do not scan huge folders blindly.
    2. Search local skills first under ~/Library/Application Support/Odysseus/AgentMode/CodexHome/OdysseusBundledSkills, ~/Library/Application Support/Odysseus/AgentMode/CodexHome/OdysseusLearnedSkills, ~/.codex/skills, ~/.agents/skills, ~/Documents/GitHub/*/skills, and any directly relevant repo skill folders. Prefer `find`/metadata over reading every large file.
    3. Only then do targeted web research for public skills or official app integrations that match those apps. Use current sources and avoid broad marketplace scraping.
    4. Recommend only practical, low-risk options that Odysseus can install locally or connect through existing app/tool routes.

    Write a compact JSON array to:
    \(Self.skillDiscoverySuggestionsURL.path)

    Schema:
    [
      {
        "id": "stable-slug",
        "title": "Skill or integration name",
        "detail": "Why it matches the current apps/workflow",
        "source": "local|online|installed",
        "installPrompt": "Exact Odysseus Agent Mode prompt to install or connect it"
      }
    ]

    Keep at most 8 suggestions, deduplicate installed skills, and prefer local matches over online ones.
    """
  }

  @Published private(set) var automations: [OdysseusAutomation] = []

  private let storeURL: URL
  private var timer: Timer?
  private weak var companion: CompanionManager?
  private var runningAutomationSessionIDs: [UUID: UUID] = [:]

  private init() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    let dir = appSupport.appendingPathComponent("Odysseus", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    self.storeURL = dir.appendingPathComponent("automations.json")
    load()
    ensureSkillDiscoveryAutomationInstalled()
  }

  // MARK: lifecycle

  func bind(companion: CompanionManager) {
    self.companion = companion
    startTimer()
  }

  func startTimer() {
    timer?.invalidate()
    let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor [self] in
        self.tick()
      }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  // MARK: CRUD

  func add(_ automation: OdysseusAutomation) {
    var a = automation
    a.nextRun = a.enabled ? a.computingNextRun(after: Date()) : nil
    automations.append(a)
    save()
  }

  func update(_ automation: OdysseusAutomation) {
    guard let idx = automations.firstIndex(where: { $0.id == automation.id }) else { return }
    guard !isProtectedSystemAutomation(automations[idx]) else { return }
    var a = automation
    a.nextRun = a.enabled ? a.computingNextRun(after: Date()) : nil
    automations[idx] = a
    save()
  }

  func remove(id: UUID) {
    automations.removeAll { $0.id == id && !isProtectedSystemAutomation($0) }
    save()
  }

  func setEnabled(id: UUID, enabled: Bool) {
    guard let idx = automations.firstIndex(where: { $0.id == id }) else { return }
    automations[idx].enabled = enabled
    automations[idx].nextRun = enabled ? automations[idx].computingNextRun(after: Date()) : nil
    save()
  }

  @discardableResult
  func ensureSkillDiscoveryAutomationInstalled() -> OdysseusAutomation {
    _ = OdysseusAgentStore.shared.ensureSkillDiscoveryAgentInstalled()

    if let idx = automations.firstIndex(where: { isProtectedSystemAutomation($0) || $0.name == Self.skillDiscoveryAutomationName }) {
      let existing = automations[idx]
      var repaired = existing
      var shouldSave = false

      if existing.name != Self.skillDiscoveryAutomationName ||
          existing.prompt != Self.skillDiscoveryAutomationPrompt ||
          existing.agentSlug != OdysseusAgentStore.skillDiscoveryAgentSlug {
        repaired.name = Self.skillDiscoveryAutomationName
        repaired.prompt = Self.skillDiscoveryAutomationPrompt
        repaired.agentSlug = OdysseusAgentStore.skillDiscoveryAgentSlug
        repaired.nextRun = repaired.enabled ? repaired.computingNextRun(after: Date()) : nil
        shouldSave = true
      }

      if !UserDefaults.standard.bool(forKey: Self.skillDiscoveryDefaultDisabledMigrationKey) {
        repaired.enabled = false
        repaired.nextRun = nil
        UserDefaults.standard.set(true, forKey: Self.skillDiscoveryDefaultDisabledMigrationKey)
        shouldSave = true
      }

      if shouldSave {
        automations[idx] = repaired
        save()
        return repaired
      }
      return existing
    }

    let automation = OdysseusAutomation(
      name: Self.skillDiscoveryAutomationName,
      schedule: .interval(seconds: 6 * 60 * 60),
      prompt: Self.skillDiscoveryAutomationPrompt,
      agentSlug: OdysseusAgentStore.skillDiscoveryAgentSlug,
      enabled: false
    )
    UserDefaults.standard.set(true, forKey: Self.skillDiscoveryDefaultDisabledMigrationKey)
    add(automation)
    return automation
  }

  var skillDiscoveryAutomation: OdysseusAutomation? {
    automations.first(where: { isProtectedSystemAutomation($0) })
  }

  func isProtectedSystemAutomation(_ automation: OdysseusAutomation) -> Bool {
    automation.name == Self.skillDiscoveryAutomationName || automation.agentSlug == OdysseusAgentStore.skillDiscoveryAgentSlug
  }

  // MARK: tick

  private func tick() {
    pruneRunningAutomationSessions()

    let now = Date()
    var didMutate = false
    for i in automations.indices {
      guard automations[i].enabled else { continue }
      if let next = automations[i].nextRun, next <= now {
        if isAutomationRunning(automations[i]) {
          automations[i].nextRun = now.addingTimeInterval(60)
          didMutate = true
          continue
        }

        let firedSessionID = fire(automation: automations[i])
        if let firedSessionID {
          runningAutomationSessionIDs[automations[i].id] = firedSessionID
        }
        automations[i].lastRun = now
        automations[i].nextRun = automations[i].computingNextRun(after: now)
        didMutate = true
      } else if automations[i].nextRun == nil {
        automations[i].nextRun = automations[i].computingNextRun(after: now)
        didMutate = true
      }
    }
    if didMutate { save() }
  }

  private func pruneRunningAutomationSessions() {
    guard let companion else {
      runningAutomationSessionIDs.removeAll()
      return
    }

    runningAutomationSessionIDs = runningAutomationSessionIDs.filter { _, sessionID in
      guard let session = companion.codexAgentSessions.first(where: { $0.id == sessionID }) else {
        return false
      }
      if session.isTurnActiveForChatQueue {
        return true
      }
      switch session.status {
      case .starting, .running:
        return true
      case .stopped, .ready, .failed:
        return false
      }
    }
  }

  private func isAutomationRunning(_ automation: OdysseusAutomation) -> Bool {
    runningAutomationSessionIDs[automation.id] != nil
  }

  @discardableResult
  private func fire(automation: OdysseusAutomation) -> UUID? {
    guard let companion else { return nil }
    let prompt = automation.prompt
    if let slug = automation.agentSlug, let agent = OdysseusAgentStore.shared.agent(slug: slug) {
      let session = companion.createAndSelectNewCodexAgentSession(asAgent: agent)
      session.submitPromptFromUI(prompt, screenContext: nil)
      return session.id
    } else {
      companion.submitAgentPromptFromUI(prompt)
      return nil
    }
  }

  // MARK: persistence

  private func load() {
    guard let data = try? Data(contentsOf: storeURL) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    // M13: previously a decode failure silently returned [] and the next save()
    // would overwrite the file with only the re-seeded automation, destroying
    // all user data. Now: on failure, quarantine the bad file (timestamped
    // backup) and surface the error in-process so the user can recover.
    do {
      let envelope = try decoder.decode(AutomationStoreEnvelope.self, from: data)
      self.automations = envelope.automations
    } catch {
      // Back-compat: pre-versioned files were a bare [OdysseusAutomation].
      if let legacy = try? decoder.decode([OdysseusAutomation].self, from: data) {
        self.automations = legacy
      } else {
        let quarantined = storeURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: storeURL, to: quarantined)
        print("automation load failed — file quarantined at \(quarantined.path). Underlying error: \(error)")
      }
      // Seed in-memory only; the bad file is preserved on disk for recovery.
    }
  }

  private func save() {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    // M13: version the on-disk envelope so future schema changes can migrate
    // explicitly instead of relying on Codable optional-field tolerance.
    do {
      let envelope = AutomationStoreEnvelope(schemaVersion: AutomationStoreEnvelope.currentVersion, automations: automations)
      let data = try encoder.encode(envelope)
      try data.write(to: storeURL, options: [.atomic])
    } catch {
      print("automation save failed: \(error)")
    }
  }
}

/// M13: versioned on-disk envelope for the automation store. The
/// `automations` array is wrapped so future schema changes can migrate
/// explicitly. Decode accepts both the new envelope and the legacy bare-array
/// format (handled in `load()`).
struct AutomationStoreEnvelope: Codable {
  static let currentVersion = 1
  var schemaVersion: Int
  var automations: [OdysseusAutomation]
}

struct OdysseusSkillDiscoverySuggestion: Codable, Identifiable, Equatable {
  var id: String
  var title: String
  var detail: String
  var source: String
  var installPrompt: String
  var chipTitle: String? = nil
  var systemImage: String? = nil

  var sourceLabel: String {
    switch source.lowercased() {
    case "app": return "App"
    case "local": return "Local"
    case "mcp": return "MCP"
    case "installed": return "Installed"
    case "online": return "Online"
    default: return source.isEmpty ? "Suggested" : source.capitalized
    }
  }

  var actionLabel: String {
    switch source.lowercased() {
    case "online", "local": return "Install"
    default: return "Connect"
    }
  }
}

private struct OdysseusSkillSuggestionRule: Codable, Equatable {
  var id: String
  var appMatches: [String]
  var suggestions: [OdysseusSkillDiscoverySuggestion]
}

private struct OdysseusSkillSuggestionRegistry: Codable, Equatable {
  var defaultSuggestions: [OdysseusSkillDiscoverySuggestion]
  var appRules: [OdysseusSkillSuggestionRule]

  static func load(from url: URL) -> OdysseusSkillSuggestionRegistry {
    ensureUserConfigExists(at: url)

    if let data = try? Data(contentsOf: url),
       let decoded = try? JSONDecoder().decode(OdysseusSkillSuggestionRegistry.self, from: data) {
      return decoded
    }

    if let bundledURL = bundledConfigURL,
       let data = try? Data(contentsOf: bundledURL),
       let decoded = try? JSONDecoder().decode(OdysseusSkillSuggestionRegistry.self, from: data) {
      return decoded
    }

    return fallback
  }

  func suggestions(for context: OdysseusSkillDiscoveryStore.ApplicationContext?, slug: (String) -> String) -> [OdysseusSkillDiscoverySuggestion] {
    guard let context else { return [] }
    let haystack = "\(context.name) \(context.bundleIdentifier ?? "")".lowercased()
    for rule in appRules where rule.appMatches.contains(where: { haystack.contains($0.lowercased()) }) {
      return rule.suggestions.map { suggestion in
        var resolved = suggestion
        resolved.id = resolved.id.replacingOccurrences(of: "{appSlug}", with: slug(context.name))
        resolved.title = resolved.title.replacingOccurrences(of: "{appName}", with: context.name)
        resolved.detail = resolved.detail.replacingOccurrences(of: "{appName}", with: context.name)
        resolved.installPrompt = resolved.installPrompt.replacingOccurrences(of: "{appName}", with: context.name)
        resolved.chipTitle = resolved.chipTitle?.replacingOccurrences(of: "{appName}", with: context.name)
        return resolved
      }
    }

    return [
      OdysseusSkillDiscoverySuggestion(
        id: "active-\(slug(context.name))-screen-context",
        title: "\(context.name) screen context",
        detail: "Odysseus can use the active \(context.name) window as visual context and suggest the safest available automation route.",
        source: "app",
        installPrompt: "Use Odysseus's screen context for the active \(context.name) window and suggest the best available skill, MCP, or agent workflow.",
        chipTitle: "\(context.name) context",
        systemImage: "app.fill"
      )
    ]
  }

  private static func ensureUserConfigExists(at url: URL) {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let bundledURL = bundledConfigURL,
         let data = try? Data(contentsOf: bundledURL) {
        try data.write(to: url, options: [.atomic])
      } else {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(fallback).write(to: url, options: [.atomic])
      }
    } catch {
      print("skill suggestion registry seed failed: \(error)")
    }
  }

  private static var bundledConfigURL: URL? {
    if let direct = Bundle.main.url(forResource: "skill-suggestion-rules", withExtension: "json") {
      return direct
    }
    if let resourceURL = Bundle.main.resourceURL {
      let nested = resourceURL
        .appendingPathComponent("Odysseus", isDirectory: true)
        .appendingPathComponent("skill-suggestion-rules.json", isDirectory: false)
      if FileManager.default.fileExists(atPath: nested.path) {
        return nested
      }
    }
    return nil
  }

  private static let fallback = OdysseusSkillSuggestionRegistry(defaultSuggestions: [], appRules: [])

}

@MainActor
final class OdysseusSkillDiscoveryStore: ObservableObject {
  static let shared = OdysseusSkillDiscoveryStore()

  @Published private(set) var suggestions: [OdysseusSkillDiscoverySuggestion] = []
  @Published private(set) var activeApplicationName: String?

  private let storeURL = OdysseusAutomationStore.skillDiscoverySuggestionsURL

  private init() {
    reload()
  }

  func reload() {
    let savedSuggestions = loadSavedSuggestions()
    let appContexts = currentApplicationContexts()
    let registry = OdysseusSkillSuggestionRegistry.load(from: OdysseusAutomationStore.skillSuggestionRulesURL)
    let contextNames = appContexts.map(\.name).joined(separator: ", ")
    activeApplicationName = contextNames.isEmpty ? nil : contextNames

    suggestions = mergeSuggestions(
      appContexts.flatMap { registry.suggestions(for: $0, slug: slug) },
      savedSuggestions.isEmpty ? registry.defaultSuggestions : savedSuggestions
    )
  }

  private func loadSavedSuggestions() -> [OdysseusSkillDiscoverySuggestion] {
    guard let data = try? Data(contentsOf: storeURL),
          let decoded = try? JSONDecoder().decode([OdysseusSkillDiscoverySuggestion].self, from: data) else {
      return []
    }
    return decoded
  }

  private func mergeSuggestions(_ prioritized: [OdysseusSkillDiscoverySuggestion],
                                _ defaults: [OdysseusSkillDiscoverySuggestion]) -> [OdysseusSkillDiscoverySuggestion] {
    var seen: Set<String> = []
    var merged: [OdysseusSkillDiscoverySuggestion] = []

    for suggestion in prioritized + defaults {
      let key = suggestion.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !key.isEmpty, !seen.contains(key) else { continue }
      seen.insert(key)
      merged.append(suggestion)
      if merged.count == 8 { break }
    }

    return merged
  }

  struct ApplicationContext {
    var name: String
    var bundleIdentifier: String?
  }

  private func currentApplicationContexts(limit: Int = 4) -> [ApplicationContext] {
    let ownBundleIdentifier = Bundle.main.bundleIdentifier
    var contexts: [ApplicationContext] = []
    var seen: Set<String> = []

    func append(_ context: ApplicationContext) {
      let key = context.bundleIdentifier?.lowercased()
        ?? context.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
      guard !seen.contains(key) else { return }
      seen.insert(key)
      contexts.append(context)
    }

    if let app = NSWorkspace.shared.frontmostApplication,
       app.bundleIdentifier != ownBundleIdentifier,
       let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !name.isEmpty {
      append(ApplicationContext(name: name, bundleIdentifier: app.bundleIdentifier))
    }

    for app in OdysseusApplicationUsageLogStore.shared.recentApplications(limit: limit, excluding: ownBundleIdentifier) {
      append(ApplicationContext(name: app.name, bundleIdentifier: app.bundleIdentifier))
      if contexts.count == limit { break }
    }

    return contexts
  }

  private func slug(for value: String) -> String {
    let allowed = CharacterSet.alphanumerics
    let parts = value
      .lowercased()
      .unicodeScalars
      .map { allowed.contains($0) ? Character($0) : "-" }
    return String(parts)
      .split(separator: "-")
      .joined(separator: "-")
  }


}
