import SwiftUI
import AppKit

struct ContactsView: View {
    @EnvironmentObject var appState: AppState
    @State private var contacts: [User] = []
    @State private var isLoading = true
    @State private var showAddContact = false
    @State private var selectedContact: User?

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

                Text("\(contacts.count) contacts")
                    .foregroundColor(.secondary)

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
                List(contacts) { contact in
                    ContactRow(contact: contact, onEdit: {
                        selectedContact = contact
                    })
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

struct ContactRow: View {
    let contact: User
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(contact.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.headline)

                if let github = contact.githubHandle {
                    Text("@\(github)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let phone = contact.formattedPhone {
                HStack(spacing: 4) {
                    Image(systemName: "phone.fill")
                        .font(.caption)
                    Text(phone)
                        .font(.caption)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            } else {
                Text("No phone")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
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

                Section {
                    Button("Delete Contact", role: .destructive) {
                        showDeleteConfirm = true
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
