import Foundation

/// Which copy wins when the same item changed here and elsewhere, for
/// CloudSync: kept apart from CloudKit, so they can be tested on their own
/// (ios/SyncRules, `swift test`).
enum SyncRules {
  /// A change made here and not in iCloud yet, as the rules need it.
  struct Mine: Equatable {
    /// When it was made here, in milliseconds since 1970.
    var modifiedAt: Double
    /// It's a saved file's, whose file goes up apart: those are left as
    /// they are, the change here going on.
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
}
