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
        NavigationSplitView {
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
            .frame(minWidth: 300)
        } detail: {
            if let connection = appState.selectedConnection {
                ConnectionDetailView(connectionWithUser: connection, isOwnerView: selectedTab == .subscribers)
            } else {
                ContentUnavailableView(
                    "Select a Connection",
                    systemImage: "person.2",
                    description: Text("Choose a connection from the list to view details")
                )
            }
        }
        .navigationTitle("Admin Portal")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if selectedTab == .subscribers {
                    Button(action: { showTagManager = true }) {
                        Image(systemName: "tag")
                    }
                    .help("Manage Tags")
                }

                Button(action: { showSubscribeSheet = true }) {
                    Image(systemName: "person.badge.plus")
                }
                .help("Subscribe to User")
            }
        }
        .searchable(text: $searchText, prompt: "Search by name...")
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
        async let _ = appState.loadSubscribers()
        async let _ = appState.loadSubscriptions()
        async let _ = appState.loadTags()
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
