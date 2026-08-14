import CFNetwork
import Foundation

/// Where the embedded Pi child process gets its proxy route from.
public enum PiProxySource: String {
    /// Explicit proxy variables inherited from the host process environment.
    case hostEnvironment = "env"
    /// Synthesized from the macOS system proxy settings via CFNetwork.
    case systemProxy = "system-proxy"
    /// No proxy anywhere; the child connects directly.
    case direct = "direct"
}

/// Resolves the proxy environment injected into the embedded Pi child process.
///
/// Priority: explicit host environment variables > macOS system proxy > direct.
/// GUI apps launched from Finder do not see the shell's proxy exports, and the Pi
/// runtime does not read macOS system proxy settings itself, so without this the
/// child would attempt a direct connection even while the user runs a system-wide
/// proxy such as Clash.
public enum PiProxyEnvironmentResolver {
    /// Proxy variables respected from the host environment (both cases).
    public static let hostProxyKeys = [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "http_proxy", "https_proxy", "all_proxy", "no_proxy",
    ]

    /// Decide the proxy variables for the Pi child process. `systemProxySettings`
    /// is the dictionary returned by CFNetworkCopySystemProxySettings(); pass nil
    /// when it is unavailable. Pure and deterministic so self-checks can inject
    /// stand-in settings instead of touching the real system configuration.
    public static func resolve(
        hostEnvironment: [String: String],
        systemProxySettings: [String: Any]?
    ) -> (variables: [String: String], source: PiProxySource) {
        var inherited: [String: String] = [:]
        for key in hostProxyKeys {
            if let value = hostEnvironment[key], isValidValue(value) {
                inherited[key] = value
            }
        }
        if !inherited.isEmpty {
            return (inherited, .hostEnvironment)
        }
        guard let settings = systemProxySettings else {
            return ([:], .direct)
        }
        let synthesized = environment(fromSystemProxySettings: settings)
        return synthesized.isEmpty ? ([:], .direct) : (synthesized, .systemProxy)
    }

    /// Read the live macOS system proxy settings via CFNetwork.
    public static func currentSystemProxySettings() -> [String: Any]? {
        CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
    }

    /// Whether the system proxy dictionary requests a PAC script, which cannot be
    /// translated into plain proxy variables and is therefore skipped.
    public static func usesProxyAutoConfiguration(_ settings: [String: Any]) -> Bool {
        isEnabled(settings["ProxyAutoConfigEnable"])
    }

    /// Map a CFNetwork system proxy dictionary to child-process variables.
    /// Returns an empty dictionary when no usable proxy is configured.
    public static func environment(fromSystemProxySettings settings: [String: Any]) -> [String: String] {
        // PAC scripts decide per-URL and cannot be expressed as a proxy URL.
        guard !usesProxyAutoConfiguration(settings) else {
            return [:]
        }
        var variables: [String: String] = [:]
        if isEnabled(settings["HTTPSEnable"]),
           let url = proxyURL(scheme: "http", settings: settings, hostKey: "HTTPSProxy", portKey: "HTTPSPort") {
            variables["HTTPS_PROXY"] = url
        }
        if isEnabled(settings["HTTPEnable"]),
           let url = proxyURL(scheme: "http", settings: settings, hostKey: "HTTPProxy", portKey: "HTTPPort") {
            variables["HTTP_PROXY"] = url
        }
        if variables.isEmpty,
           isEnabled(settings["SOCKSEnable"]),
           let url = proxyURL(scheme: "socks5", settings: settings, hostKey: "SOCKSProxy", portKey: "SOCKSPort") {
            variables["ALL_PROXY"] = url
        }
        if let exceptions = settings["ExceptionsList"] as? [String] {
            let bypass = exceptions.filter(isValidValue).joined(separator: ",")
            if isValidValue(bypass) {
                variables["NO_PROXY"] = bypass
            }
        }
        return variables
    }

    /// Same acceptance rule as the inherited host variables.
    private static func isValidValue(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 2048 && !value.contains("\n")
    }

    private static func isEnabled(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    private static func proxyURL(
        scheme: String,
        settings: [String: Any],
        hostKey: String,
        portKey: String
    ) -> String? {
        guard let host = (settings[hostKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        var url = "\(scheme)://\(host)"
        if let port = (settings[portKey] as? NSNumber)?.intValue, port > 0 {
            url += ":\(port)"
        }
        return isValidValue(url) ? url : nil
    }
}
