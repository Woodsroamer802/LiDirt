import Foundation

/// Publishable Supabase project settings (safe to ship in the app; RLS protects data).
enum SupabaseConfig {
    static let projectRef = "jwpklfannqxcesqnoxra"

    static var projectURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: "https://\(projectRef).supabase.co")!
    }

    /// Prefer Info.plist override; falls back to the project publishable/anon key.
    static var anonKey: String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
           !raw.isEmpty {
            return raw
        }
        // Legacy anon JWT for this LiDirt project (publishable to clients; RLS enforced).
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp3cGtsZmFubnF4Y2VzcW5veHJhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ5MDMyMzgsImV4cCI6MjExMDQ3OTIzOH0.FcasaKD4v3o0kEsS1gGpT50k7itMQdFesis7a-3EwLw"
    }

    static let scanPackagesBucket = "scan-packages"
}
