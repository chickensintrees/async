import XCTest
@testable import Async

final class CommitTests: XCTestCase {

    func testShortSha() {
        let commit = makeCommit(sha: "abc1234567890")
        XCTAssertEqual(commit.shortSha, "abc1234")
    }

    func testShortSha_exactlySevenChars() {
        let commit = makeCommit(sha: "1234567")
        XCTAssertEqual(commit.shortSha, "1234567")
    }

    func testShortMessage_singleLine() {
        let commit = makeCommit(message: "Fix bug in login")
        XCTAssertEqual(commit.shortMessage, "Fix bug in login")
    }

    func testShortMessage_multiLine() {
        let commit = makeCommit(message: "Fix bug in login\n\nThis is a longer description\nwith multiple lines")
        XCTAssertEqual(commit.shortMessage, "Fix bug in login")
    }

    func testAuthorLogin_withGitHubUser() {
        let commit = makeCommit(authorLogin: "billmoore", commitAuthorName: "Bill Moore")
        XCTAssertEqual(commit.authorLogin, "billmoore")
    }

    func testAuthorLogin_withoutGitHubUser() {
        let commit = makeCommit(authorLogin: nil, commitAuthorName: "Bill Moore")
        XCTAssertEqual(commit.authorLogin, "Bill Moore")
    }

    func testId_isSha() {
        let commit = makeCommit(sha: "abc123def456")
        XCTAssertEqual(commit.id, "abc123def456")
    }

    private func makeCommit(
        sha: String = "abc1234567890",
        message: String = "Test commit",
        authorLogin: String? = "testuser",
        commitAuthorName: String = "Test User"
    ) -> Commit {
        let author: GitHubUser? = authorLogin.map { GitHubUser(login: $0, avatar_url: nil) }
        return Commit(
            sha: sha,
            commit: Commit.CommitDetail(
                message: message,
                author: Commit.CommitAuthor(name: commitAuthorName, date: Date())
            ),
            author: author,
            html_url: "https://github.com/test/repo/commit/\(sha)"
        )
    }
}

final class IssueTests: XCTestCase {

    func testIsOpen_openState() {
        let issue = makeIssue(state: "open")
        XCTAssertTrue(issue.isOpen)
    }

    func testIsOpen_closedState() {
        let issue = makeIssue(state: "closed")
        XCTAssertFalse(issue.isOpen)
    }

    func testIsPullRequest_withPRRef() {
        let issue = makeIssue(hasPullRequest: true)
        XCTAssertTrue(issue.isPullRequest)
    }

    func testIsPullRequest_withoutPRRef() {
        let issue = makeIssue(hasPullRequest: false)
        XCTAssertFalse(issue.isPullRequest)
    }

    func testId_isNumber() {
        let issue = makeIssue(number: 42)
        XCTAssertEqual(issue.id, 42)
    }

    private func makeIssue(
        number: Int = 1,
        state: String = "open",
        hasPullRequest: Bool = false
    ) -> Issue {
        Issue(
            number: number,
            title: "Test Issue",
            state: state,
            user: GitHubUser(login: "testuser", avatar_url: nil),
            created_at: Date(),
            updated_at: Date(),
            labels: [],
            comments: 0,
            html_url: "https://github.com/test/repo/issues/\(number)",
            pull_request: hasPullRequest ? Issue.PullRequestRef(url: "https://api.github.com/pulls/1") : nil
        )
    }
}

final class RepoEventTests: XCTestCase {

    func testDescription_pushEvent_singleCommit() {
        let event = makeEvent(type: "PushEvent", commits: 1, ref: "refs/heads/main")
        XCTAssertEqual(event.description, "pushed 1 commit to main")
    }

    func testDescription_pushEvent_multipleCommits() {
        let event = makeEvent(type: "PushEvent", commits: 3, ref: "refs/heads/feature")
        XCTAssertEqual(event.description, "pushed 3 commits to feature")
    }

    func testDescription_pushEvent_noRef() {
        let event = makeEvent(type: "PushEvent", commits: 2, ref: nil)
        XCTAssertEqual(event.description, "pushed 2 commits to main")
    }

    func testDescription_issuesEvent() {
        let event = makeEvent(type: "IssuesEvent", action: "opened")
        XCTAssertEqual(event.description, "opened issue")
    }

    func testDescription_issuesEvent_noAction() {
        let event = makeEvent(type: "IssuesEvent", action: nil)
        XCTAssertEqual(event.description, "updated issue")
    }

    func testDescription_pullRequestEvent() {
        let event = makeEvent(type: "PullRequestEvent", action: "merged")
        XCTAssertEqual(event.description, "merged PR")
    }

    func testDescription_issueCommentEvent() {
        let event = makeEvent(type: "IssueCommentEvent")
        XCTAssertEqual(event.description, "commented")
    }

    func testDescription_createEvent() {
        let event = makeEvent(type: "CreateEvent")
        XCTAssertEqual(event.description, "created branch")
    }

    func testDescription_unknownEvent() {
        let event = makeEvent(type: "ForkEvent")
        XCTAssertEqual(event.description, "fork")
    }

    func testDescription_watchEvent() {
        let event = makeEvent(type: "WatchEvent")
        XCTAssertEqual(event.description, "watch")
    }

    private func makeEvent(
        type: String,
        action: String? = nil,
        commits: Int? = nil,
        ref: String? = nil
    ) -> RepoEvent {
        var commitList: [RepoEvent.Payload.PushCommit]? = nil
        if let count = commits {
            commitList = (0..<count).map { i in
                RepoEvent.Payload.PushCommit(sha: "sha\(i)", message: "Commit \(i)")
            }
        }

        return RepoEvent(
            id: UUID().uuidString,
            type: type,
            actor: RepoEvent.Actor(login: "testuser"),
            created_at: Date(),
            payload: RepoEvent.Payload(action: action, ref: ref, commits: commitList)
        )
    }
}

final class DateExtensionTests: XCTestCase {

    func testRelativeString_recent() {
        let recent = Date().addingTimeInterval(-60) // 1 minute ago
        let relative = recent.relativeString
        // Should contain "min" or similar
        XCTAssertFalse(relative.isEmpty)
    }

    func testRelativeString_hourAgo() {
        let hourAgo = Date().addingTimeInterval(-3600)
        let relative = hourAgo.relativeString
        XCTAssertFalse(relative.isEmpty)
    }
}
