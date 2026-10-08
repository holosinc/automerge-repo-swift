import Automerge
@testable import AutomergeRepo
import XCTest

final class AnswerRequestTests: XCTestCase {
    /// A request for a document this repo knows without holding it gets an
    /// answer.
    ///
    /// A sync server asked for a document it lacks asks its other peers, and
    /// answers the client that asked only once every one of them has. A repo
    /// holding a handle with no content (one it asked for and was told is
    /// unavailable) resolved it to answer, which threw, and replied with an
    /// error message. automerge-repo ignores those, so the server's request,
    /// and the client's behind it, stayed open for good.
    func testRequestForDocumentKnownWithoutContentIsAnsweredUnavailable() async throws {
        let repo = Repo(
            sharePolicy: SharePolicy.agreeable,
            maxResolveFetchIterations: 3,
            resolveFetchIterationDelay: .milliseconds(10)
        )
        let adapter = await TestOutgoingNetworkProvider()
        await repo.addNetworkAdapter(adapter: adapter)
        let server: PEER_ID = "sync-server"
        // The server never answers this repo's own request (an error message
        // is only logged), so the fetch gives up on its own.
        await adapter.configure(.init(remotePeer: server, remotePeerMetadata: nil) { _ in
            .error(.init(message: "no answer"))
        })
        try await adapter.connect(to: "server")

        // This repo asks for the document and gives up: it now holds a
        // handle with no content.
        let id = DocumentId()
        do {
            _ = try await repo.find(id: id)
            XCTFail("precondition: nobody has the document")
        } catch {}

        // The server, asked for it by another client, asks this repo.
        let before = await adapter.messagesReceivedByRemotePeer().count
        await repo.handleRequest(msg: .init(
            documentId: id.description,
            senderId: server,
            targetId: repo.peerId,
            sync_message: Document().generateSyncMessage(state: SyncState()) ?? Data()
        ))

        let replies = await adapter.messagesReceivedByRemotePeer().dropFirst(before)
        XCTAssertEqual(replies.count, 1, "exactly one answer")
        guard case let .unavailable(answer) = replies.first else {
            return XCTFail("expected unavailable, got \(String(describing: replies.first))")
        }
        XCTAssertEqual(answer.documentId, id.description)
        XCTAssertEqual(answer.targetId, server)
    }

    /// The same, for a document an empty sync message readied.
    ///
    /// This repo asks the server for a document nobody has, and the server
    /// answers with a sync message from its own empty copy. That readies the
    /// handle with an empty document. When the server is then asked for the
    /// document by another client, it asks this repo, which must say it
    /// doesn't have it rather than send another empty sync.
    func testRequestForDocumentReadiedEmptyIsAnsweredUnavailable() async throws {
        let repo = Repo(sharePolicy: SharePolicy.agreeable)
        let adapter = await TestOutgoingNetworkProvider()
        await repo.addNetworkAdapter(adapter: adapter)
        let server: PEER_ID = "sync-server"
        await adapter.configure(.init(remotePeer: server, remotePeerMetadata: nil) { _ in
            .error(.init(message: "no answer"))
        })
        try await adapter.connect(to: "server")

        let id = DocumentId()
        let empty = Document().generateSyncMessage(state: SyncState()) ?? Data()
        await repo.handleSync(msg: .init(
            documentId: id.description, senderId: server, targetId: repo.peerId, sync_message: empty
        ))

        let before = await adapter.messagesReceivedByRemotePeer().count
        await repo.handleRequest(msg: .init(
            documentId: id.description, senderId: server, targetId: repo.peerId, sync_message: empty
        ))

        let replies = await adapter.messagesReceivedByRemotePeer().dropFirst(before)
        XCTAssertEqual(replies.count, 1, "exactly one answer")
        guard case .unavailable = replies.first else {
            return XCTFail("expected unavailable, got \(String(describing: replies.first))")
        }
    }
}
