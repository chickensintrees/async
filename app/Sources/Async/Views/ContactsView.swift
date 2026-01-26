import SwiftUI
import AppKit

struct ContactsView: View {
    @EnvironmentObject var appState: AppState
    @State private var contacts: [User] = []
    @State private var isLoading = true
    @State private var showAddContact = false
    @State private var selectedContact: User?
    @State private var showAgents = true
    @State private var searchText = ""

    var agentContacts: [User] {
        contacts.filter { $0.isAgent }
    }

    var humanContacts: [User] {
        contacts.filter { $0.isHuman }
    }

    var filteredAgents: [User] {
        if searchText.isEmpty { return agentContacts }
        return agentContacts.filter { matchesSearch($0) }
    }

    var filteredHumans: [User] {
        if searchText.isEmpty { return humanContacts }
        return humanContacts.filter { matchesSearch($0) }
    }

    private func matchesSearch(_ user: User) -> Bool {
        user.displayName.localizedCaseInsensitiveContains(searchText) ||
        (user.githubHandle?.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Contacts")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // Agent toggle
                Toggle(isOn: $showAgents) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("Agents")
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("\(contacts.count) contacts")
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)

                Button(action: { showAddContact = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)

                Button(action: loadContacts) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity)

            // Search bar
            if !contacts.isEmpty {
                SearchBar(text: $searchText, placeholder: "Search contacts...")
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Divider()

            if isLoading {
                ProgressView("Loading contacts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if contacts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No contacts yet")
                        .font(.headline)
                    Text("Add contacts to start messaging")
                        .foregroundColor(.secondary)
                    Button("Add Contact") {
                        showAddContact = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // AI Agents Section
                    if showAgents && !filteredAgents.isEmpty {
                        Section {
                            ForEach(filteredAgents) { contact in
                                ContactRowView(contact: contact, onEdit: {
                                    if !contact.isSystemAgent {
                                        selectedContact = contact
                                    }
                                })
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.purple)
                                Text("AI Agents")
                                    .foregroundColor(.purple)
                                Text("(\(filteredAgents.count))")
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                        }
                    }

                    // People Section
                    if !filteredHumans.isEmpty {
                        Section {
                            ForEach(filteredHumans) { contact in
                                ContactRowView(contact: contact, onEdit: {
                                    selectedContact = contact
                                })
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(.blue)
                                Text("People")
                                    .foregroundColor(.blue)
                                Text("(\(filteredHumans.count))")
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                        }
                    }

                    // No results
                    if !searchText.isEmpty && filteredAgents.isEmpty && filteredHumans.isEmpty {
                        Section {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No contacts match \"\(searchText)\"")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            loadContacts()
        }
        .sheet(isPresented: $showAddContact) {
            AddContactView(onSave: { newContact in
                contacts.append(newContact)
                // Re-sort after adding
                contacts.sort { user1, user2 in
                    if user1.isAgent != user2.isAgent {
                        return user1.isAgent
                    }
                    return user1.displayName.localizedCaseInsensitiveCompare(user2.displayName) == .orderedAscending
                }
                showAddContact = false
            })
        }
        .sheet(item: $selectedContact) { contact in
            EditContactView(contact: contact, onSave: { updated in
                if let index = contacts.firstIndex(where: { $0.id == updated.id }) {
                    contacts[index] = updated
                }
                selectedContact = nil
            }, onDelete: {
                contacts.removeAll { $0.id == contact.id }
                selectedContact = nil
            })
        }
    }

    func loadContacts() {
        isLoading = true
        Task {
            contacts = await appState.loadAllUsers()
            isLoading = false
        }
    }
}

struct AddContactView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    @State private var displayName = ""
    @State private var githubHandle = ""
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var error: String?

    let onSave: (User) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Contact")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            Form {
                Section("Basic Info") {
                    TextField("Display Name", text: $displayName)
                    TextField("GitHub Username (optional)", text: $githubHandle)
                }

                Section("Contact Info") {
                    TextField("Phone Number (e.g., +14125551234)", text: $phoneNumber)
                    TextField("Email (optional)", text: $email)
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Add Contact") {
                    saveContact()
                }
                .buttonStyle(.borderedProminent)
                .disabled(displayName.isEmpty || isSaving)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }

    func saveContact() {
        isSaving = true
        error = nil

        Task {
            if let user = await appState.createUser(
                displayName: displayName,
                githubHandle: githubHandle.isEmpty ? nil : githubHandle,
                phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
                email: email.isEmpty ? nil : email
            ) {
                onSave(user)
            } else {
                error = "Failed to create contact"
            }
            isSaving = false
        }
    }
}

struct EditContactView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    let contact: User
    let onSave: (User) -> Void
    let onDelete: () -> Void

    @State private var displayName: String
    @State private var githubHandle: String
    @State private var phoneNumber: String
    @State private var email: String
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    init(contact: User, onSave: @escaping (User) -> Void, onDelete: @escaping () -> Void) {
        self.contact = contact
        self.onSave = onSave
        self.onDelete = onDelete
        _displayName = State(initialValue: contact.displayName)
        _githubHandle = State(initialValue: contact.githubHandle ?? "")
        _phoneNumber = State(initialValue: contact.phoneNumber ?? "")
        _email = State(initialValue: contact.email ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Contact")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Basic Info") {
                    TextField("Display Name", text: $displayName)
                    TextField("GitHub Username", text: $githubHandle)
                }

                Section("Contact Info") {
                    TextField("Phone Number", text: $phoneNumber)
                    TextField("Email", text: $email)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }

                // Only show delete for non-system agents
                if !contact.isSystemAgent {
                    Section {
                        Button("Delete Contact", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(displayName.isEmpty || isSaving)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 400, height: 380)
        .alert("Delete Contact?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteUser(contact.id)
                    onDelete()
                }
            }
        } message: {
            Text("This will remove \(contact.displayName) from your contacts.")
        }
    }

    func saveChanges() {
        isSaving = true
        errorMessage = nil
        Task {
            if let updated = await appState.updateUser(
                id: contact.id,
                displayName: displayName,
                githubHandle: githubHandle.isEmpty ? nil : githubHandle,
                phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
                email: email.isEmpty ? nil : email
            ) {
                onSave(updated)
                dismiss()
            } else {
                errorMessage = appState.errorMessage ?? "Failed to save"
            }
            isSaving = false
        }
    }
}
