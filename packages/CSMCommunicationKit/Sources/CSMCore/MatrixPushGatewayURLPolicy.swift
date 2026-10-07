import Foundation

/// The Matrix pusher needs the complete gateway endpoint, not a REST base path.
/// The trusted messaging configuration owns the origin; this policy only
/// resolves its canonical endpoint and rejects credential-bearing variants.
enum MatrixPushGatewayURLPolicy {
    static func resolve(messagingBaseURL: URL) -> URL? {
        guard messagingBaseURL.baseURL == nil,
              var components = URLComponents(url: messagingBaseURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil
        else {
            return nil
        }
        if let port = components.port, !(1...65_535).contains(port) {
            return nil
        }

        // The gateway is at the origin root even when the REST base has a path.
        components.percentEncodedPath = "/_matrix/push/v1/notify"
        return components.url
    }
}
