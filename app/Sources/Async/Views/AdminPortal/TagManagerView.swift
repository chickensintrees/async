import SwiftUI

struct TagManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var newTagName = ""
    @State private var newTagColor = "#007AFF"
    @State private var editingTag: Tag?
    @State private var editName = ""
    @State private var editColor = ""
    @State private var showDeleteConfirmation = false
    @State private var tagToDelete: Tag?

    private let colorOptions = [
        "#007AFF", // Blue
        "#34C759", // Green
        "#FF9500", // Orange
        "#FF3B30", // Red
        "#AF52DE", // Purple
        "#FF2D55", // Pink
        "#5856D6", // Indigo
        "#00C7BE", // Teal
        "#FFD60A", // Yellow
        "#8E8E93"  // Gray
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Create new tag section
                createTagSection

                Divider()

                // Existing tags list
                if appState.tags.isEmpty {
                    emptyState
                } else {
                    tagsList
                }
            }
            .navigationTitle("Manage Tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Tag?", isPresented: $showDeleteConfirmation, presenting: tagToDelete) { tag in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await appState.deleteTag(tag.id)
                    }
                }
            } message: { tag in
                Text("This will remove the tag \"\(tag.name)\" from all connections.")
            }
            .sheet(item: $editingTag) { tag in
                editTagSheet(for: tag)
            }
        }
        .frame(width: 400, height: 500)
    }

    private var createTagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create New Tag")
                .font(.headline)

            HStack(spacing: 12) {
                // Color picker
                Menu {
                    ForEach(colorOptions, id: \.self) { color in
                        Button {
                            newTagColor = color
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: color) ?? .blue)
                                    .frame(width: 20, height: 20)
                                if color == newTagColor {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: newTagColor) ?? .blue)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                }
                .menuStyle(.borderlessButton)

                TextField("Tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    createTag()
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    private var tagsList: some View {
        List {
            ForEach(appState.tags) { tag in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: tag.color) ?? .blue)
                        .frame(width: 16, height: 16)

                    Text(tag.name)
                        .font(.body)

                    Spacer()

                    Button {
                        editName = tag.name
                        editColor = tag.color
                        editingTag = tag
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button {
                        tagToDelete = tag
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Tags", systemImage: "tag")
        } description: {
            Text("Create tags to organize your subscribers.")
        }
    }

    private func editTagSheet(for tag: Tag) -> some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Name", text: $editName)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(colorOptions, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color) ?? .blue)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(color == editColor ? Color.primary : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    editColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Edit Tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingTag = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await appState.updateTag(tag.id, name: editName, color: editColor)
                            editingTag = nil
                        }
                    }
                    .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 300, height: 300)
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        Task {
            _ = await appState.createTag(name: name, color: newTagColor)
            newTagName = ""
        }
    }
}
