// The app version a save records, read from the running bundle.

import Foundation

public enum SaveAppVersion {
    public static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
    }
}
