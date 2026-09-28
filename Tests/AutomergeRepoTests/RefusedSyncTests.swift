import Automerge
@testable import AutomergeRepo
import XCTest

final class RefusedSyncTests: XCTestCase {
    /// Changes a peer refused are sent again once it will take them.
    ///
    /// The sync state records what went to a peer, and the protocol holds
    /// those changes back until the peer replies. A peer that refuses the
    /// document answers "unavailable" instead, which is not a reply, so the
    /// refused changes counted as delivered for the life of the process: a
    /// later sync to that peer sent nothing it lacked. Seen with a sync server
    /// that denies a document until it is registered, then accepts it.
    func testRefusedChangesAreSentAgainAfterUnavailable() async throws {
        let repo = Repo(sharePolicy: SharePolicy.agreeable)
        let handle = try await repo.create()
        try handle.doc.put(obj: .ROOT, key: "title", value: .String("made while the server refused it"))
        let peer: PEER_ID = "sync-server"

        // What beginSync does: generate from the stored state, and keep it.
        let state = await repo.syncState(id: handle.id, peer: peer)
        XCTAssertNotNil(handle.doc.generateSyncMessage(state: state), "the first sync carries the change")
        await repo.updateSyncState(id: handle.id, peer: peer, syncState: state)

        // The peer answers "unavailable". Before the fix nothing changed, and
        // the protocol, still waiting for a reply, sends nothing more.
        let waiting = await repo.syncState(id: handle.id, peer: peer)
        XCTAssertNil(
            handle.doc.generateSyncMessage(state: waiting),
            "precondition: with no reply the protocol holds the change back"
        )

        await repo.peerReportedUnavailable(id: handle.id, peer: peer)

        let fresh = await repo.syncState(id: handle.id, peer: peer)
        XCTAssertNotNil(
            handle.doc.generateSyncMessage(state: fresh),
            "after the refusal the next sync starts over instead of treating the refused change as delivered"
        )
    }

    /// A refusal for a document this repo does not hold changes nothing.
    func testUnavailableForUnknownDocumentIsIgnored() async throws {
        let repo = Repo(sharePolicy: SharePolicy.agreeable)
        await repo.peerReportedUnavailable(id: DocumentId(), peer: "sync-server")
        let known = await repo.documentIds()
        XCTAssertTrue(known.isEmpty)
    }
}
