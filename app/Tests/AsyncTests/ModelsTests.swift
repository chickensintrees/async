import XCTest
@testable import Async

final class ConversationModeTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(ConversationMode.anonymous.displayName, "Mediated")
        XCTAssertEqual(ConversationMode.assisted.displayName, "Enhanced")
        XCTAssertEqual(ConversationMode.direct.displayName, "Direct")
    }

    func testDescriptions() {
        XCTAssertEqual(ConversationMode.anonymous.description, "AI rewrites your message professionally")
        XCTAssertEqual(ConversationMode.assisted.description, "Your message + AI summaries")
        XCTAssertEqual(ConversationMode.direct.description, "Your exact words, no AI")
    }

    func testCaseIterable() {
        XCTAssertEqual(ConversationMode.allCases.count, 3)
        XCTAssertTrue(ConversationMode.allCases.contains(.anonymous))
        XCTAssertTrue(ConversationMode.allCases.contains(.assisted))
        XCTAssertTrue(ConversationMode.allCases.contains(.direct))
    }

    func testRawValues() {
        XCTAssertEqual(ConversationMode.anonymous.rawValue, "anonymous")
        XCTAssertEqual(ConversationMode.assisted.rawValue, "assisted")
        XCTAssertEqual(ConversationMode.direct.rawValue, "direct")
    }
}

final class UserTests: XCTestCase {

    func testFormattedPhone_validUSNumber() {
        let user = makeUser(phoneNumber: "+14125123593")
        XCTAssertEqual(user.formattedPhone, "+1 (412) 512-3593")
    }

    func testFormattedPhone_nilPhone() {
        let user = makeUser(phoneNumber: nil)
        XCTAssertNil(user.formattedPhone)
    }

    func testFormattedPhone_shortNumber() {
        let user = makeUser(phoneNumber: "+1412512")
        XCTAssertEqual(user.formattedPhone, "+1412512") // Returns as-is
    }

    func testFormattedPhone_nonUSNumber() {
        let user = makeUser(phoneNumber: "+447911123456")
        XCTAssertEqual(user.formattedPhone, "+447911123456") // Returns as-is
    }

    func testFormattedPhone_wrongPrefix() {
        let user = makeUser(phoneNumber: "+24125123593")
        XCTAssertEqual(user.formattedPhone, "+24125123593") // Returns as-is, not +1
    }

    func testUserEquatable() {
        let fixedDate = Date(timeIntervalSince1970: 1000000)
        let user1 = makeUser(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: fixedDate)
        let user2 = makeUser(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: fixedDate)
        let user3 = makeUser(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: fixedDate)

        XCTAssertEqual(user1, user2)
        XCTAssertNotEqual(user1, user3)
    }

    private func makeUser(
        id: UUID = UUID(),
        phoneNumber: String? = nil,
        date: Date = Date()
    ) -> User {
        User(
            id: id,
            githubHandle: "testuser",
            displayName: "Test User",
            email: "test@example.com",
            phoneNumber: phoneNumber,
            avatarUrl: nil,
            createdAt: date,
            updatedAt: date
        )
    }
}

final class ConversationTests: XCTestCase {

    func testDisplayTitle_withTitle() {
        let conversation = makeConversation(title: "Project Discussion")
        XCTAssertEqual(conversation.displayTitle, "Project Discussion")
    }

    func testDisplayTitle_nilTitle() {
        let conversation = makeConversation(title: nil)
        // When title is nil, displayTitle falls back to mode + date
        // Note: ConversationWithDetails.displayTitle shows participant names instead
        XCTAssertTrue(conversation.displayTitle.hasPrefix("Enhanced"))
    }

    func testConversationHashable() {
        let id = UUID()
        let conv1 = makeConversation(id: id, title: "Test")
        let conv2 = makeConversation(id: id, title: "Test")

        var set = Set<Conversation>()
        set.insert(conv1)
        set.insert(conv2)

        XCTAssertEqual(set.count, 1)
    }

    private func makeConversation(
        id: UUID = UUID(),
        title: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> Conversation {
        Conversation(
            id: id,
            mode: .assisted,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

final class MessageTests: XCTestCase {

    let viewerId = UUID()
    let senderId = UUID()

    // MARK: - Direct Mode Tests

    func testDisplayContent_directMode_showsRaw() {
        let message = makeMessage(raw: "Hello!", processed: "Processed hello")
        let content = message.displayContent(for: viewerId, mode: .direct)
        XCTAssertEqual(content, "Hello!")
    }

    func testDisplayContent_directMode_ignoresProcessed() {
        let message = makeMessage(raw: "Raw content", processed: "Should be ignored")
        let content = message.displayContent(for: viewerId, mode: .direct)
        XCTAssertFalse(content.contains("Should be ignored"))
    }

    // MARK: - Assisted Mode Tests

    func testDisplayContent_assistedMode_showsBothWhenProcessed() {
        let message = makeMessage(raw: "Original message", processed: "AI summary")
        let content = message.displayContent(for: viewerId, mode: .assisted)

        XCTAssertTrue(content.contains("Original message"))
        XCTAssertTrue(content.contains("AI summary"))
        XCTAssertTrue(content.contains("AI Summary:"))
    }

    func testDisplayContent_assistedMode_showsOnlyRawWhenNoProcessed() {
        let message = makeMessage(raw: "Just raw", processed: nil)
        let content = message.displayContent(for: viewerId, mode: .assisted)

        XCTAssertEqual(content, "Just raw")
    }

    // MARK: - Anonymous Mode Tests

    func testDisplayContent_anonymousMode_showsRawWhenViewerInVisibleTo() {
        let message = makeMessage(
            raw: "Secret raw content",
            processed: "Sanitized content",
            rawVisibleTo: [viewerId]
        )
        let content = message.displayContent(for: viewerId, mode: .anonymous)

        XCTAssertEqual(content, "Secret raw content")
    }

    func testDisplayContent_anonymousMode_showsProcessedWhenViewerNotInVisibleTo() {
        let otherId = UUID()
        let message = makeMessage(
            raw: "Secret raw content",
            processed: "Sanitized content",
            rawVisibleTo: [otherId]
        )
        let content = message.displayContent(for: viewerId, mode: .anonymous)

        XCTAssertEqual(content, "Sanitized content")
    }

    func testDisplayContent_anonymousMode_showsRawWhenNoProcessedAndNotVisible() {
        let otherId = UUID()
        let message = makeMessage(
            raw: "Raw fallback",
            processed: nil,
            rawVisibleTo: [otherId]
        )
        let content = message.displayContent(for: viewerId, mode: .anonymous)

        XCTAssertEqual(content, "Raw fallback")
    }

    func testDisplayContent_anonymousMode_nilViewer() {
        let message = makeMessage(
            raw: "Raw content",
            processed: "Processed content",
            rawVisibleTo: [UUID()]
        )
        let content = message.displayContent(for: nil, mode: .anonymous)

        XCTAssertEqual(content, "Processed content")
    }

    func testDisplayContent_anonymousMode_nilVisibleTo() {
        let message = makeMessage(
            raw: "Raw content",
            processed: "Processed content",
            rawVisibleTo: nil
        )
        let content = message.displayContent(for: viewerId, mode: .anonymous)

        XCTAssertEqual(content, "Processed content")
    }

    // MARK: - Helper

    private func makeMessage(
        raw: String,
        processed: String?,
        rawVisibleTo: [UUID]? = nil
    ) -> Message {
        Message(
            id: UUID(),
            conversationId: UUID(),
            senderId: senderId,
            contentRaw: raw,
            contentProcessed: processed,
            isFromAgent: false,
            agentContext: nil,
            createdAt: Date(),
            processedAt: processed != nil ? Date() : nil,
            rawVisibleTo: rawVisibleTo
        )
    }
}

final class MessageReadTests: XCTestCase {

    func testMessageReadInit() {
        let messageId = UUID()
        let userId = UUID()
        let readAt = Date()

        let read = MessageRead(
            messageId: messageId,
            userId: userId,
            readAt: readAt
        )

        XCTAssertEqual(read.messageId, messageId)
        XCTAssertEqual(read.userId, userId)
        XCTAssertEqual(read.readAt, readAt)
    }
}

// MARK: - ConnectionStatus Tests

final class ConnectionStatusTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(ConnectionStatus.pending.displayName, "Pending")
        XCTAssertEqual(ConnectionStatus.active.displayName, "Active")
        XCTAssertEqual(ConnectionStatus.paused.displayName, "Paused")
        XCTAssertEqual(ConnectionStatus.declined.displayName, "Declined")
        XCTAssertEqual(ConnectionStatus.archived.displayName, "Archived")
    }

    func testColors() {
        XCTAssertEqual(ConnectionStatus.pending.color, "orange")
        XCTAssertEqual(ConnectionStatus.active.color, "green")
        XCTAssertEqual(ConnectionStatus.paused.color, "yellow")
        XCTAssertEqual(ConnectionStatus.declined.color, "red")
        XCTAssertEqual(ConnectionStatus.archived.color, "gray")
    }

    func testRawValues() {
        XCTAssertEqual(ConnectionStatus.pending.rawValue, "pending")
        XCTAssertEqual(ConnectionStatus.active.rawValue, "active")
        XCTAssertEqual(ConnectionStatus.paused.rawValue, "paused")
        XCTAssertEqual(ConnectionStatus.declined.rawValue, "declined")
        XCTAssertEqual(ConnectionStatus.archived.rawValue, "archived")
    }

    func testCaseIterable() {
        XCTAssertEqual(ConnectionStatus.allCases.count, 5)
    }
}

// MARK: - Connection Tests

final class ConnectionTests: XCTestCase {

    func testConnectionInit() {
        let id = UUID()
        let ownerId = UUID()
        let subscriberId = UUID()
        let now = Date()

        let connection = Connection(
            id: id,
            ownerId: ownerId,
            subscriberId: subscriberId,
            status: .active,
            requestMessage: "Please add me!",
            statusChangedAt: now,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertEqual(connection.id, id)
        XCTAssertEqual(connection.ownerId, ownerId)
        XCTAssertEqual(connection.subscriberId, subscriberId)
        XCTAssertEqual(connection.status, .active)
        XCTAssertEqual(connection.requestMessage, "Please add me!")
    }

    func testConnectionEquatable() {
        let fixedDate = Date(timeIntervalSince1970: 1000000)
        let id = UUID()
        let ownerId = UUID()
        let subscriberId = UUID()

        let conn1 = Connection(
            id: id, ownerId: ownerId, subscriberId: subscriberId,
            status: .pending, requestMessage: nil,
            statusChangedAt: fixedDate, createdAt: fixedDate, updatedAt: fixedDate
        )
        let conn2 = Connection(
            id: id, ownerId: ownerId, subscriberId: subscriberId,
            status: .pending, requestMessage: nil,
            statusChangedAt: fixedDate, createdAt: fixedDate, updatedAt: fixedDate
        )

        XCTAssertEqual(conn1, conn2)
    }

    func testConnectionHashable() {
        let id = UUID()
        let ownerId = UUID()
        let subscriberId = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1000000)

        // Same properties = same hash
        let conn1 = Connection(
            id: id, ownerId: ownerId, subscriberId: subscriberId,
            status: .active, requestMessage: nil,
            statusChangedAt: fixedDate, createdAt: fixedDate, updatedAt: fixedDate
        )
        let conn2 = Connection(
            id: id, ownerId: ownerId, subscriberId: subscriberId,
            status: .active, requestMessage: nil,
            statusChangedAt: fixedDate, createdAt: fixedDate, updatedAt: fixedDate
        )

        var set = Set<Connection>()
        set.insert(conn1)
        set.insert(conn2)

        XCTAssertEqual(set.count, 1)
    }
}

// MARK: - Tag Tests

final class TagTests: XCTestCase {

    func testTagInit() {
        let id = UUID()
        let ownerId = UUID()
        let now = Date()

        let tag = Tag(
            id: id,
            ownerId: ownerId,
            name: "VIP",
            color: "#22C55E",
            createdAt: now
        )

        XCTAssertEqual(tag.id, id)
        XCTAssertEqual(tag.ownerId, ownerId)
        XCTAssertEqual(tag.name, "VIP")
        XCTAssertEqual(tag.color, "#22C55E")
    }

    func testTagEquatable() {
        let fixedDate = Date(timeIntervalSince1970: 1000000)
        let id = UUID()
        let ownerId = UUID()

        let tag1 = Tag(id: id, ownerId: ownerId, name: "Test", color: "#FFF", createdAt: fixedDate)
        let tag2 = Tag(id: id, ownerId: ownerId, name: "Test", color: "#FFF", createdAt: fixedDate)

        XCTAssertEqual(tag1, tag2)
    }

    func testTagHashable() {
        let id = UUID()
        let ownerId = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1000000)

        // Same properties = same hash
        let tag1 = Tag(id: id, ownerId: ownerId, name: "VIP", color: "#FFF", createdAt: fixedDate)
        let tag2 = Tag(id: id, ownerId: ownerId, name: "VIP", color: "#FFF", createdAt: fixedDate)

        var set = Set<Tag>()
        set.insert(tag1)
        set.insert(tag2)

        XCTAssertEqual(set.count, 1)
    }
}

// MARK: - ConnectionTag Tests

final class ConnectionTagTests: XCTestCase {

    func testConnectionTagInit() {
        let connectionId = UUID()
        let tagId = UUID()
        let now = Date()

        let ct = ConnectionTag(
            connectionId: connectionId,
            tagId: tagId,
            assignedAt: now
        )

        XCTAssertEqual(ct.connectionId, connectionId)
        XCTAssertEqual(ct.tagId, tagId)
        XCTAssertEqual(ct.assignedAt, now)
    }

    func testConnectionTagEquatable() {
        let connectionId = UUID()
        let tagId = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1000000)

        let ct1 = ConnectionTag(connectionId: connectionId, tagId: tagId, assignedAt: fixedDate)
        let ct2 = ConnectionTag(connectionId: connectionId, tagId: tagId, assignedAt: fixedDate)

        XCTAssertEqual(ct1, ct2)
    }
}

// MARK: - ConnectionWithUser Tests

final class ConnectionWithUserTests: XCTestCase {

    func testConnectionWithUserInit() {
        let fixedDate = Date(timeIntervalSince1970: 1000000)
        let connectionId = UUID()
        let userId = UUID()

        let connection = Connection(
            id: connectionId,
            ownerId: UUID(),
            subscriberId: userId,
            status: .active,
            requestMessage: nil,
            statusChangedAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let user = User(
            id: userId,
            githubHandle: "testuser",
            displayName: "Test User",
            email: nil,
            phoneNumber: nil,
            avatarUrl: nil,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let tag = Tag(id: UUID(), ownerId: UUID(), name: "VIP", color: "#FFF", createdAt: fixedDate)

        let cwu = ConnectionWithUser(connection: connection, user: user, tags: [tag])

        XCTAssertEqual(cwu.id, connectionId)
        XCTAssertEqual(cwu.connection, connection)
        XCTAssertEqual(cwu.user, user)
        XCTAssertEqual(cwu.tags.count, 1)
        XCTAssertEqual(cwu.tags.first?.name, "VIP")
    }

    func testConnectionWithUserHashable() {
        let fixedDate = Date(timeIntervalSince1970: 1000000)
        let connectionId = UUID()

        let connection = Connection(
            id: connectionId,
            ownerId: UUID(),
            subscriberId: UUID(),
            status: .active,
            requestMessage: nil,
            statusChangedAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let user = User(
            id: UUID(),
            githubHandle: "test",
            displayName: "Test",
            email: nil,
            phoneNumber: nil,
            avatarUrl: nil,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let cwu1 = ConnectionWithUser(connection: connection, user: user, tags: [])
        let cwu2 = ConnectionWithUser(connection: connection, user: user, tags: [])

        var set = Set<ConnectionWithUser>()
        set.insert(cwu1)
        set.insert(cwu2)

        XCTAssertEqual(set.count, 1)
    }
}
