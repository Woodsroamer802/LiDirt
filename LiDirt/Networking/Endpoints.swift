import Foundation

enum Endpoints {
    static func projects(base: URL) -> URL {
        base.appendingPathComponent("projects")
    }

    static func project(base: URL, id: UUID) -> URL {
        projects(base: base).appendingPathComponent(id.uuidString)
    }

    static func scans(base: URL, projectId: UUID) -> URL {
        project(base: base, id: projectId).appendingPathComponent("scans")
    }

    static func scan(base: URL, scanId: UUID) -> URL {
        base.appendingPathComponent("scans").appendingPathComponent(scanId.uuidString)
    }
}
