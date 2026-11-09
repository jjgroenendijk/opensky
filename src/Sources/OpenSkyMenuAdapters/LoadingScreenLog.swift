public import OpenSkyFormatsCore

/// The log of the loading screen and the start cover.
public enum LoadingScreenLog {
    public static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Loading"
    )
}
