import Foundation

/// The signed app variant is the source of truth. An absent or unknown value
/// never enables CallKit or PushKit during a cold launch.
public enum VoiceCallPresentationMode: String, Sendable {
  case inApp = "in_app"
  case system
}

public enum VoiceCallDistributionPolicy {
  public static func mode(for signedDistribution: String?) -> VoiceCallPresentationMode {
    signedDistribution == "global" ? .system : .inApp
  }

  public static var currentMode: VoiceCallPresentationMode {
    mode(for: Bundle.main.object(forInfoDictionaryKey: "CSMVoiceDistribution") as? String)
  }
}
