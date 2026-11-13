import Foundation

/// Which copy wins when the same item changed here and elsewhere, for
/// CloudSync: kept apart from CloudKit, so they can be tested on their own
/// (ios/SyncRules, `swift test`).
enum SyncRules {
  /// A change made here and not in iCloud yet, as the rules need it.
  struct Mine: Equatable {
    /// When it was made here, in milliseconds since 1970.
    var modifiedAt: Double
    /// It's a saved file's, whose file goes up apart: a change to one
    /// elsewhere doesn't replace it, the change here going on.
    var hasFile = false
    /// It's being sent now, and can't be taken back.
    var onItsWay = false
  }

  /// Whether a copy from iCloud changed at [theirs] (milliseconds since
  /// 1970, nil if it doesn't say) is newer than [mine].
  static func isNewer(_ theirs: Double?, than mine: Mine?) -> Bool {
    guard let mine, !mine.hasFile, let theirs else { return false }
    return theirs > mine.modifiedAt
  }

  enum OnChange: Equatable {
    /// What's here goes on, over it.
    case keepMine
    /// It's taken here, and what was waiting here no longer goes.
    case takeTheirs
    /// It's taken here; what's on its way goes anyway, so it's sent again
    /// after, over that.
    case takeTheirsAndSendItAgain
  }

  /// A change from elsewhere to an item changed here too ([mine]; nil if
  /// what's waiting here is its deletion): the one changed last wins.
  static func onChange(theirs: Double?, mine: Mine?) -> OnChange {
    guard isNewer(theirs, than: mine), let mine else { return .keepMine }
    return mine.onItsWay ? .takeTheirsAndSendItAgain : .takeTheirs
  }

  enum OnDeletion: Equatable {
    /// What's here goes on, putting it back.
    case keepMine
    /// It's deleted here, and what was waiting here no longer goes.
    case delete
    /// It's deleted here; what's on its way goes anyway, so it's deleted
    /// again after.
    case deleteAfterMine
  }

  /// An item deleted elsewhere, which was changed here too ([mine]; nil if
  /// nothing of it is waiting here, or only its deletion). [knownHere]: this
  /// device knew it was in iCloud, so it was deleted after this device
  /// last heard of it, not deleted from here and since put back.
  ///
  /// Deleting wins, as when history is cleared on one device while a
  /// thread's being read on another: there's no saying when it was
  /// deleted, and what's waiting here is seldom more than a moment old. A
  /// saved file's too, deleted elsewhere while its file was going up from
  /// here, after its record.
  static func onDeletion(knownHere: Bool, mine: Mine?) -> OnDeletion {
    guard let mine else { return .delete }
    if !knownHere { return .keepMine }
    return mine.onItsWay ? .deleteAfterMine : .delete
  }
}
