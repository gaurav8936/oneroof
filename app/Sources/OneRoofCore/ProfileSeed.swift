import Foundation

/// Test only (1.8.1): which keys of an exported defaults domain a seeded fresh profile imports. AppKit's own keys
/// (window frames, split-view frames) are read from the app's real domain, never from the suite, so they are left out;
/// so is the roofd registration record (a test run never registers the background item).
public enum SeedFilter {
    public static func keep(_ values: [String: Any]) -> [String: Any] {
        values.filter { k, _ in !k.hasPrefix("NS") && k != "roofd.registeredBuild" }
    }
}
