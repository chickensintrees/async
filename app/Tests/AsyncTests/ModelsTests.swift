import XCTest
@testable import Async

final class ConversationModeTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(ConversationMode.anonymous.displayName, "Anonymous (Agent-Mediated)")
        XCTAssertEqual(ConversationMode.assisted.displayName, "Assisted (With Agent)")
        XCTAssertEqual(ConversationMode.direct.displayName, "Direct (No Agent)")
    }

    func testDescriptions() {
        XCTAssertEqual(ConversationMode.anonymous.description, "Recipient only sees AI-processed version")
        XCTAssertEqual(ConversationMode.assisted.description, "Everyone sees everything, AI can help")
        XCTAssertEqual(ConversationMode.direct.description, "Just you and the recipient, no AI")
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
        XCTAssertEqual(conversation.displayTitle, "Conversation")
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
