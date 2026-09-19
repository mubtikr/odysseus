import Foundation
import Testing
@testable import Odysseus

struct OdysseusProfileTests {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let suite = "OdysseusProfileTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func catalogExposesThreeProfiles() {
        let ids = OdysseusProfileCatalog.all.map(\.id)
        #expect(ids == ["local", "realtime", "quality"])
        #expect(OdysseusProfileCatalog.defaultProfileID == "local")
    }

    @Test func taskCompletionVoiceDefaultsOn() {
        let key = AppBundleConfiguration.userAgentCompletionVoiceEnabledDefaultsKey
        let oldValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let oldValue {
                UserDefaults.standard.set(oldValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(AppBundleConfiguration.agentCompletionVoiceEnabled())
    }

    @Test func profileLookupFallsBackToDefaultForUnknownID() {
        #expect(OdysseusProfileCatalog.profile(withID: "realtime").id == "realtime")
        #expect(OdysseusProfileCatalog.profile(withID: nil).id == "local")
        #expect(OdysseusProfileCatalog.profile(withID: "nope").id == "local")
    }

    @Test func applyingLocalProfileWritesExpectedKeys() {
        let defaults = freshDefaults("local")
        OdysseusProfileCatalog.apply(.init(
            id: OdysseusProfileCatalog.local.id,
            displayName: OdysseusProfileCatalog.local.displayName,
            sttProvider: OdysseusProfileCatalog.local.sttProvider,
            responseModelID: OdysseusProfileCatalog.local.responseModelID,
            ttsProvider: OdysseusProfileCatalog.local.ttsProvider,
            activationMode: OdysseusProfileCatalog.local.activationMode,
            ttsVoiceID: OdysseusProfileCatalog.local.ttsVoiceID,
            agentModelID: OdysseusProfileCatalog.local.agentModelID
        ), defaults: defaults)

        #expect(defaults.string(forKey: OdysseusProfileCatalog.activeProfileDefaultsKey) == "local")
        #expect(defaults.string(forKey: AppBundleConfiguration.userVoiceTranscriptionProviderDefaultsKey) == "parakeet")
        #expect(defaults.string(forKey: OdysseusProfileCatalog.voiceResponseModelDefaultsKey) == "fable-5")
        #expect(defaults.string(forKey: AppBundleConfiguration.userTTSProviderDefaultsKey) == "microsoft_edge")
        #expect(defaults.string(forKey: AppBundleConfiguration.userVoiceActivationModeDefaultsKey) == "push_to_talk")
    }

    @Test func applyingRealtimeProfileSelectsSpeechToSpeechStack() {
        let defaults = freshDefaults("realtime")
        OdysseusProfileCatalog.apply(OdysseusProfileCatalog.realtime, defaults: defaults)

        #expect(defaults.string(forKey: AppBundleConfiguration.userVoiceTranscriptionProviderDefaultsKey) == "openai")
        #expect(defaults.string(forKey: OdysseusProfileCatalog.voiceResponseModelDefaultsKey) == OdysseusModelCatalog.defaultSpeechModelID)
        #expect(defaults.string(forKey: AppBundleConfiguration.userTTSProviderDefaultsKey) == "openai_realtime")
    }

    @Test func applyingQualityProfileSelectsCloudStack() {
        let defaults = freshDefaults("quality")
        OdysseusProfileCatalog.apply(OdysseusProfileCatalog.quality, defaults: defaults)

        #expect(defaults.string(forKey: AppBundleConfiguration.userVoiceTranscriptionProviderDefaultsKey) == "deepgram")
        #expect(defaults.string(forKey: AppBundleConfiguration.userTTSProviderDefaultsKey) == "elevenlabs")
        #expect(OdysseusProfileCatalog.activeProfile(defaults: defaults).id == "quality")
    }

    @Test func optionalFieldsDoNotClobberUnrelatedKeysWhenNil() {
        let defaults = freshDefaults("optional")
        defaults.set("existing-codex-model", forKey: "odysseusCodexModel")
        defaults.set("existing-eleven-voice", forKey: AppBundleConfiguration.userElevenLabsVoiceIDDefaultsKey)

        // Built-in profiles carry nil agentModelID / ttsVoiceID, so applying
        // them must leave those unrelated keys intact.
        OdysseusProfileCatalog.apply(OdysseusProfileCatalog.local, defaults: defaults)

        #expect(defaults.string(forKey: "odysseusCodexModel") == "existing-codex-model")
        #expect(defaults.string(forKey: AppBundleConfiguration.userElevenLabsVoiceIDDefaultsKey) == "existing-eleven-voice")
    }
}
