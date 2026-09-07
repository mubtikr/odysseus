//
//  CompanionManager+Profiles.swift
//  odysseus
//
//  Live application of a settings profile. Unlike OdysseusProfileCatalog.apply
//  (which only writes UserDefaults), this routes through the existing
//  CompanionManager setters so the running app reacts immediately — each setter
//  persists its own key AND updates @Published / runtime state (wake word,
//  dictation provider, TTS client, etc.).
//
//  Step 2 of design-notes/settings-profiles-spec.md.
//

import Foundation

extension CompanionManager {
    /// Applies a profile to the live app: STT provider, response model, TTS
    /// provider, and activation mode, plus optional TTS voice / agent model.
    /// Unknown enum raw values fall back to the current selection rather than
    /// forcing an invalid state.
    func applyProfile(_ profile: OdysseusProfile) {
        UserDefaults.standard.set(profile.id, forKey: OdysseusProfileCatalog.activeProfileDefaultsKey)

        setVoiceTranscriptionProvider(profile.sttProvider)
        setSelectedModel(profile.responseModelID)

        if let ttsProvider = OdysseusTTSProvider(rawValue: profile.ttsProvider) {
            setTTSProvider(ttsProvider)
        }
        if let activationMode = OdysseusVoiceActivationMode(rawValue: profile.activationMode) {
            setVoiceActivationMode(activationMode)
        }

        if let agentModelID = profile.agentModelID {
            UserDefaults.standard.set(agentModelID, forKey: "odysseusCodexModel")
        }
        // ttsVoiceID is left to OdysseusProfileCatalog.apply / future voice
        // wiring; built-in profiles carry nil so there is nothing to set here.
    }

    /// The profile whose id was last applied (default when none recorded yet).
    var activeProfile: OdysseusProfile {
        OdysseusProfileCatalog.activeProfile()
    }
}
