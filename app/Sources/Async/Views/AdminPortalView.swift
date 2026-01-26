import SwiftUI

enum AdminPortalTab: String, CaseIterable {
    case subscribers = "Subscribers"
    case subscriptions = "Subscriptions"
}

struct AdminPortalView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AdminPortalTab = .subscribers
    @State private var showTagManager = false
    @State private var showSubscribeSheet = false
    @State private var statusFilter: ConnectionStatus? = nil
    @State private var tagFilter: Tag? = nil
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and toolbar
            adminHeader

            Divider()

            // Main content: list + detail
            HStack(spacing: 0) {
                // Left panel: list
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("View", selection: $selectedTab) {
                        ForEach(AdminPortalTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    // Filter bar (for subscribers tab)
                    if selectedTab == .subscribers {
                        filterBar
                    }

                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search by name...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    Divider()

                    // Content based on selected tab
                    switch selectedTab {
                    case .subscribers:
                        SubscribersListView(
                            statusFilter: statusFilter,
                            tagFilter: tagFilter,
                            searchText: searchText
                        )
                    case .subscriptions:
                        SubscriptionsListView(searchText: searchText)
                    }
                }
                .frame(width: 320)

                Divider()

                // Right panel: detail
                if let connection = appState.selectedConnection {
                    ConnectionDetailView(connectionWithUser: connection, isOwnerView: selectedTab == .subscribers)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Select a Connection")
                            .font(.headline)
                        Text("Choose a connection from the list to view details")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showTagManager) {
            TagManagerView()
        }
        .sheet(isPresented: $showSubscribeSheet) {
            SubscribeSheet()
        }
        .task {
            await loadData()
        }
        .onChange(of: selectedTab) { _, _ in
            appState.selectedConnection = nil
        }
    }

    private var adminHeader: some View {
        HStack {
            Text("Admin Portal")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            if selectedTab == .subscribers {
                Button(action: { showTagManager = true }) {
                    Image(systemName: "tag")
                }
                .buttonStyle(.bordered)
                .help("Manage Tags")
                .accessibilityLabel("Manage Tags")
            }

            Button(action: { showSubscribeSheet = true }) {
                Image(systemName: "person.badge.plus")
            }
            .buttonStyle(.bordered)
            .help("Subscribe to User")
            .accessibilityLabel("Subscribe to User")
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var filterBar: some View {
        HStack {
            // Status filter
            Menu {
                Button("All Statuses") {
                    statusFilter = nil
                }
                Divider()
                ForEach(ConnectionStatus.allCases, id: \.self) { status in
                    Button(status.displayName) {
                        statusFilter = status
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(statusFilter?.displayName ?? "Status")
                }
            }
            .menuStyle(.borderlessButton)

            // Tag filter
            if !appState.tags.isEmpty {
                Menu {
                    Button("All Tags") {
                        tagFilter = nil
                    }
                    Divider()
                    ForEach(appState.tags) { tag in
                        Button {
                            tagFilter = tag
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: tag.color) ?? .blue)
                                    .frame(width: 10, height: 10)
                                Text(tag.name)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "tag")
                        Text(tagFilter?.name ?? "Tag")
                    }
                }
                .menuStyle(.borderlessButton)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func loadData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.appState.loadSubscribers() }
            group.addTask { await self.appState.loadSubscriptions() }
            group.addTask { await self.appState.loadTags() }
        }
    }
}

// Color hex extension is now in DesignSystem.swift
