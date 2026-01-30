import SwiftUI

/// Main hub view for therapist agent training feature
/// Provides tab-based navigation to sessions, documents, patterns, and agent chat
struct TherapistTrainingView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: TrainingTab = .sessions

    enum TrainingTab: String, CaseIterable {
        case sessions = "Sessions"
        case documents = "Documents"
        case patterns = "Patterns"
        case agent = "Agent"

        var icon: String {
            switch self {
            case .sessions: return "waveform"
            case .documents: return "doc.text"
            case .patterns: return "sparkles"
            case .agent: return "bubble.left.and.bubble.right"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 4) {
                ForEach(TrainingTab.allCases, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .sessions:
                    SessionListView()
                case .documents:
                    DocumentListView()
                case .patterns:
                    PatternsListView()
                case .agent:
                    TherapistAgentView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Patterns List View

struct PatternsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var patterns: [TherapistPattern] = []
    @State private var isLoading = true
    @State private var selectedPattern: TherapistPattern?
    @State private var filterType: PatternType?

    var filteredPatterns: [TherapistPattern] {
        if let type = filterType {
            return patterns.filter { $0.patternType == type }
        }
        return patterns
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Text("Extracted Patterns")
                    .font(.headline)

                Spacer()

                Picker("Filter", selection: $filterType) {
                    Text("All").tag(nil as PatternType?)
                    ForEach(PatternType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type as PatternType?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Loading patterns...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if patterns.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Patterns Yet")
                        .font(.headline)
                    Text("Upload and process therapy sessions to extract patterns.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // Pattern list
                    List(filteredPatterns, selection: $selectedPattern) { pattern in
                        PatternRow(pattern: pattern)
                            .tag(pattern)
                    }
                    .frame(minWidth: 300)

                    // Pattern detail
                    if let pattern = selectedPattern {
                        PatternDetailView(pattern: pattern)
                    } else {
                        Text("Select a pattern to view details")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task {
            await loadPatterns()
        }
    }

    private func loadPatterns() async {
        guard let userId = appState.currentUser?.id else { return }
        isLoading = true
        do {
            patterns = try await TherapistExtractionService.shared.loadPatterns(for: userId)
        } catch {
            print("Failed to load patterns: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Pattern Row

struct PatternRow: View {
    let pattern: TherapistPattern

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pattern.patternType.icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let category = pattern.category {
                        Text(category.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if pattern.occurrenceCount > 1 {
                        Text("\(pattern.occurrenceCount)x")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            if let conf = pattern.confidence {
                Text("\(Int(conf * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(conf >= 0.7 ? .green : .orange)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pattern Detail View

struct PatternDetailView: View {
    let pattern: TherapistPattern

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: pattern.patternType.icon)
                        .font(.title2)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading) {
                        Text(pattern.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        HStack(spacing: 12) {
                            Label(pattern.patternType.displayName, systemImage: "tag")
                            if let category = pattern.category {
                                Label(category.displayName, systemImage: "folder")
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Content
                GroupBox("Content") {
                    Text(pattern.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Metadata
                GroupBox("Metadata") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let conf = pattern.confidence {
                            HStack {
                                Text("Confidence:")
                                    .foregroundColor(.secondary)
                                Text("\(Int(conf * 100))%")
                                    .fontWeight(.medium)
                                    .foregroundColor(conf >= 0.7 ? .green : .orange)
                            }
                        }

                        HStack {
                            Text("Occurrences:")
                                .foregroundColor(.secondary)
                            Text("\(pattern.occurrenceCount)")
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Extracted:")
                                .foregroundColor(.secondary)
                            Text(pattern.createdAt, style: .date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 300)
    }
}

// Preview disabled - requires Xcode
// #Preview {
//     TherapistTrainingView()
//         .environmentObject(AppState())
//         .frame(width: 900, height: 600)
// }
