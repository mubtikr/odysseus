import Foundation

enum OdysseusRuntimeMode {
    static var isOdysseusBundle: Bool {
        Bundle.main.bundleIdentifier == "com.mubtikr.odysseus"
    }

    static var isDevelopmentBuild: Bool {
        #if DEBUG
        return true
        #else
        return isOdysseusBundle
        #endif
    }

    static var stableApplicationPath: String {
        "/Applications/Odysseus.app"
    }
}
