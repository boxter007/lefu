import Foundation

public struct SourceID: Hashable, Sendable {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

public enum PlaySignal: String, Sendable { case ratePreferred, elapsedAdvance }
public enum ControlChannel: String, Sendable { case mediaRemote, nowPlayingCLI, none }

public struct DetectionProfile: Sendable {
    public var confirmTicks: Int
    public var pollInterval: TimeInterval
    public var playSignal: PlaySignal
    public var exposesElapsed: Bool
    public var exposesDuration: Bool
    public init(confirmTicks: Int = 2,
                pollInterval: TimeInterval = 1.0,
                playSignal: PlaySignal = .ratePreferred,
                exposesElapsed: Bool = false,
                exposesDuration: Bool = true) {
        self.confirmTicks = confirmTicks
        self.pollInterval = pollInterval
        self.playSignal = playSignal
        self.exposesElapsed = exposesElapsed
        self.exposesDuration = exposesDuration
    }
}

public struct SourceProfile: Sendable, Identifiable {
    public let id: SourceID
    public let displayName: String
    public let bundleIDs: Set<String>
    public let symbolName: String
    public let detection: DetectionProfile
    public let control: ControlChannel
    public let enabledByDefault: Bool
    public init(id: SourceID, displayName: String, bundleIDs: Set<String>,
                symbolName: String, detection: DetectionProfile = DetectionProfile(),
                control: ControlChannel = .mediaRemote,
                enabledByDefault: Bool = false) {
        self.id = id; self.displayName = displayName; self.bundleIDs = bundleIDs
        self.symbolName = symbolName; self.detection = detection; self.control = control
        self.enabledByDefault = enabledByDefault
    }
}

public enum SourceCatalog {
    public static func resolve(bundleID: String?, in profiles: [SourceProfile]) -> SourceProfile? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return profiles.first { $0.bundleIDs.contains(bundleID) }
    }
    public static func filterEnabled(_ profiles: [SourceProfile], enabled: Set<String>) -> [SourceProfile] {
        profiles.filter { enabled.contains($0.id.raw) }
    }
}
