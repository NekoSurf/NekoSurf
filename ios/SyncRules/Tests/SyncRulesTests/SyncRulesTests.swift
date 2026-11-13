import XCTest

@testable import SyncRulesKit

final class SyncRulesTests: XCTestCase {
  typealias Mine = SyncRules.Mine

  func testNewerOnlyByWhenEachChanged() {
    XCTAssertTrue(SyncRules.isNewer(2, than: Mine(modifiedAt: 1)))
    XCTAssertFalse(SyncRules.isNewer(1, than: Mine(modifiedAt: 2)))
    // The same: what's here goes, over a copy of itself.
    XCTAssertFalse(SyncRules.isNewer(1, than: Mine(modifiedAt: 1)))
    // One that doesn't say when, or nothing here.
    XCTAssertFalse(SyncRules.isNewer(nil, than: Mine(modifiedAt: 1)))
    XCTAssertFalse(SyncRules.isNewer(2, than: nil))
    // A saved file's goes on, its file going up apart.
    XCTAssertFalse(SyncRules.isNewer(2, than: Mine(modifiedAt: 1, hasFile: true)))
  }

  func testAChangeElsewhereWinsWhenItWasLater() {
    XCTAssertEqual(SyncRules.onChange(theirs: 1, mine: Mine(modifiedAt: 2)), .keepMine)
    XCTAssertEqual(SyncRules.onChange(theirs: 2, mine: Mine(modifiedAt: 1)), .takeTheirs)
    XCTAssertEqual(
      SyncRules.onChange(theirs: 2, mine: Mine(modifiedAt: 1, onItsWay: true)),
      .takeTheirsAndSendItAgain)
    // What's waiting here is its deletion.
    XCTAssertEqual(SyncRules.onChange(theirs: 2, mine: nil), .keepMine)
  }

  func testADeletionElsewhereWins() {
    XCTAssertEqual(SyncRules.onDeletion(knownHere: true, mine: nil), .delete)
    XCTAssertEqual(SyncRules.onDeletion(knownHere: true, mine: Mine(modifiedAt: 1)), .delete)
    XCTAssertEqual(
      SyncRules.onDeletion(knownHere: true, mine: Mine(modifiedAt: 1, onItsWay: true)),
      .deleteAfterMine)
    // A saved file's, deleted elsewhere while its file was going up here.
    XCTAssertEqual(
      SyncRules.onDeletion(knownHere: true, mine: Mine(modifiedAt: 1, hasFile: true)), .delete)
  }

  func testButNotOverWhatWasPutBackHere() {
    // Deleted from here, then put back before the deletion came back.
    XCTAssertEqual(SyncRules.onDeletion(knownHere: false, mine: Mine(modifiedAt: 1)), .keepMine)
  }
}
