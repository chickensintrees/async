import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kanban Column

enum KanbanColumn: String, CaseIterable, Identifiable {
    case backlog = "Backlog"
    case inProgress = "In Progress"
    case done = "Done"

    var id: String { rawValue }

    var labelName: String? {
        switch self {
        case .backlog: return nil  // Default column, no special label
        case .inProgress: return "in-progress"
        case .done: return "done"
        }
    }

    var headerColor: String {
        switch self {
        case .backlog: return "secondary"
        case .inProgress: return "blue"
        case .done: return "green"
        }
    }
}

// MARK: - Kanban Issue

struct KanbanIssue: Identifiable, Codable, Hashable {
    let id: Int
    let number: Int
    var title: String
    var body: String?
    let state: String
    var labels: [KanbanLabel]
    let html_url: String
    let created_at: Date
    let user: KanbanUser?

    // MARK: - Computed Properties

    var column: KanbanColumn {
        if labels.contains(where: { $0.name == "done" }) { return .done }
        if labels.contains(where: { $0.name == "in-progress" }) { return .inProgress }
        return .backlog
    }

    var storyPoints: Int? {
        for label in labels {
            if label.name.hasPrefix("story-points:"),
               let points = Int(label.name.replacingOccurrences(of: "story-points:", with: "")) {
                return points
            }
        }
        return nil
    }

    var isHighPriority: Bool {
        labels.contains { $0.name == "priority:high" }
    }

    var isBlocked: Bool {
        labels.contains { $0.name == "blocked" }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: KanbanIssue, rhs: KanbanIssue) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supporting Types

struct KanbanLabel: Codable, Hashable {
    let name: String
    let color: String
}

struct KanbanUser: Codable, Hashable {
    let login: String
    let avatar_url: String?
}

// MARK: - Transferable (for drag-and-drop)

extension KanbanIssue: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: KanbanIssue.self, contentType: .kanbanIssue)
    }
}

extension UTType {
    static var kanbanIssue: UTType {
        UTType(exportedAs: "com.async.kanban-issue")
    }
}
