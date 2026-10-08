import Automerge
@testable import AutomergeRepo
import AutomergeUtilities
import XCTest

final class RepoFindTest: XCTestCase {
    func testRepoFindWithoutNetworkingActive() async throws {
        // https://github.com/automerge/automerge-repo-swift/issues/84
        let repo = Repo(sharePolicy: SharePolicy.agreeable)
        await repo.setLogLevel(.resolver, to: .tracing)
        await repo.setLogLevel(.network, to: .tracing)
        let websocket = WebSocketProvider(.init(reconnectOnError: false, loggingAt: .tracing))
        await repo.addNetworkAdapter(adapter: websocket)

        let unavailableExpectation =
            expectation(description: "Find should throw an Unavailable error if no peers are available to request from")
        Task {
            do {
                let handle = try await repo.find(id: DocumentId()) // never completes, never errors
                print(handle)
            } catch {
                unavailableExpectation.fulfill()
            }
        }
        await fulfillment(of: [unavailableExpectation], timeout: 5)
    }

    /// A find that cannot be attempted must not leave the handle behind in
    /// `.requesting`.
    ///
    /// #84 fixed the wait: with no peers, `startRemoteFetch` now throws
    /// straight away instead of burning the full resolve budget. What it did
    /// not do is undo the `.requesting` the handle was given a few lines
    /// earlier, and `documentIds()` counts `.requesting` handles. So every
    /// such find left a document the repo would claim to know about, and
    /// `addPeerWithMetadata` walks that list on the next peer and awaits
    /// `beginSync` for each one — inside the `.ready` delegate call the
    /// websocket provider makes *before* it starts the socket's read loop.
    /// Nothing can answer, so each waits out its budget in full and the
    /// handshake never returns.
    func testFailedRemoteFetchDoesNotLeaveDocumentRequesting() async throws {
        let repo = Repo(sharePolicy: SharePolicy.agreeable)
        let websocket = WebSocketProvider(.init(reconnectOnError: false))
        await repo.addNetworkAdapter(adapter: websocket)

        let id = DocumentId()
        do {
            _ = try await repo.find(id: id)
            XCTFail("find should be Unavailable with no peers to ask")
        } catch {
            // expected
        }

        let known = await repo.documentIds()
        XCTAssertFalse(
            known.contains(id),
            "a document that could not be fetched is still reported as known, so the next peer will try to sync it"
        )
    }
}
