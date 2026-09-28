import Automerge
@testable import AutomergeRepo
import Combine
import XCTest

final class ReconnectSyncTests: XCTestCase {
    /// A sync message lost while the connection was down doesn't silence the
    /// document once the peer is back.
    ///
    /// The sync state records a message as sent when it is generated, and the
    /// protocol sends nothing more until the peer replies. Sent while offline,
    /// the message was dropped, no reply ever came, and every later sync to
    /// that peer, reconnects included, generated nothing: the document's
    /// offline edits never reached the server until the app relaunched.
    func testReconnectingPeerGetsDocumentChangedWhileOffline() async throws {
        let repo = Repo(sharePolicy: SharePolicy.agreeable)
        let handle = try await repo.create()
        try handle.doc.put(obj: .ROOT, key: "title", value: .String("edited offline"))
        let peer: PEER_ID = "sync-server"

        // What beginSync does while the socket is down: generate from the
        // stored state (the transport then drops the message).
        let state = await repo.syncState(id: handle.id, peer: peer)
        XCTAssertNotNil(handle.doc.generateSyncMessage(state: state))
        await repo.updateSyncState(id: handle.id, peer: peer, syncState: state)
        let waiting = await repo.syncState(id: handle.id, peer: peer)
        XCTAssertNil(
            handle.doc.generateSyncMessage(state: waiting),
            "precondition: with the lost message unanswered the protocol holds back"
        )

        var synced: [DocumentId] = []
        let sink = repo.syncRequestPublisher.sink { request in
            if request.peer == peer { synced.append(request.id) }
        }
        defer { sink.cancel() }

        // The connection comes back.
        await repo.addPeerWithMetadata(peer: peer, metadata: nil)

        XCTAssertEqual(synced, [handle.id], "the reconnect starts a sync for the document edited offline")
    }
}
