import SwiftUI
import AVKit
import Photos
import UIKit

@main
struct NekoSurfApp: App {
  @StateObject private var store = AppModel()

  var body: some Scene {
    WindowGroup {
      RootTabView()
        .environmentObject(store)
    }
  }
}

// MARK: - Models

enum BoardSort: String, CaseIterable {
  case byBumpOrder
  case byReplyCount
  case byImagesCount
  case byNewest
  case byOldest

  var title: String {
    switch self {
    case .byBumpOrder: return "Bump Order"
    case .byReplyCount: return "Reply Count"
    case .byImagesCount: return "Image Count"
    case .byNewest: return "Newest"
    case .byOldest: return "Oldest"
    }
  }
}

enum SortDirection: String, CaseIterable {
  case asc
  case desc

  var title: String {
    switch self {
    case .asc: return "Ascending"
    case .desc: return "Descending"
    }
  }
}

enum BoardViewMode: String, CaseIterable {
  case grid
  case list
}

enum ThreadStatus: String {
  case deleted
  case archived
  case online
}

enum SavedAttachmentKind: String, Codable {
  case image
  case video
}

struct AppSettings {
  var allowNSFW: Bool = false
  var boardSort: BoardSort = .byImagesCount
  var boardSortDirection: SortDirection = .desc
  var boardViewMode: BoardViewMode = .grid
  var watchedPostsRetentionDays: Int = 7
  var autoScrollToLastSeen: Bool = false
}

struct Board: Codable, Hashable, Identifiable {
  struct Cooldowns: Codable, Hashable {
    let threads: Int?
    let replies: Int?
    let images: Int?
  }

  let board: String?
  let title: String?
  let wsBoard: Int?
  let perPage: Int?
  let pages: Int?
  let maxFileSize: Int?
  let maxWebmFileSize: Int?
  let maxCommentChars: Int?
  let maxWebmDuration: Int?
  let bumpLimit: Int?
  let imageLimit: Int?
  let cooldowns: Cooldowns?
  let metaDescription: String?
  let isArchived: Int?
  let forcedAnon: Int?
  let countryFlags: Int?
  let userIds: Int?
  let spoilers: Int?
  let customSpoilers: Int?

  var id: String { board ?? UUID().uuidString }

  var isWorkSafe: Bool {
    (wsBoard ?? 0) != 0
  }
}

struct Post: Codable, Hashable, Identifiable {
  let no: Int?
  let sticky: Int?
  let closed: Int?
  let now: String?
  let name: String?
  let sub: String?
  let com: String?
  let filename: String?
  let ext: String?
  let w: Int?
  let h: Int?
  let tnW: Int?
  let tnH: Int?
  let tim: Int?
  let time: Int?
  let md5: String?
  let fsize: Int?
  let resto: Int?
  let capcode: String?
  let semanticUrl: String?
  let replies: Int?
  let images: Int?
  let uniqueIps: Int?
  let lastModified: Int?
  let country: String?
  let board: String?
  let archived: Int?

  var id: String {
    "\(no ?? -1)-\(tim ?? -1)-\(resto ?? -1)-\(time ?? -1)-\(filename ?? "")"
  }

  var isVideo: Bool {
    let lower = (ext ?? "").lowercased()
    return lower == ".webm" || lower == ".mp4"
  }

  var hasMedia: Bool {
    tim != nil && ext != nil
  }
}

struct Bookmark: Codable, Hashable, Identifiable {
  let no: Int?
  let sub: String?
  let com: String?
  let imageUrl: String?
  let board: String?

  var id: String { "\(board ?? "")-\(no ?? 0)" }
}

struct SavedAttachment: Codable, Hashable, Identifiable {
  let savedAttachmentType: String?
  let fileName: String?
  let thumbnail: String?

  var id: String { fileName ?? UUID().uuidString }

  var resolvedType: SavedAttachmentKind {
    let raw = (savedAttachmentType ?? "").lowercased()
    if raw.contains("video") {
      return .video
    }
    if raw.contains("image") {
      return .image
    }
    let ext = (fileName as NSString?)?.pathExtension.lowercased() ?? ""
    if supportedVideoFileExtensions.contains(ext) {
      return .video
    }
    return .image
  }
}

struct WatchedPost: Codable, Hashable {
  let postIndex: Int
  let thread: Int
  let watchedAt: Date
}

struct BookmarkStatus: Hashable {
  let status: ThreadStatus
  let replies: Int?
  let images: Int?
}

struct ThreadLink: Hashable, Identifiable {
  let board: String
  let thread: Int

  var id: String { "\(board)-\(thread)" }
}

struct BoardThreadsResponse: Codable {
  let threads: [Post]
}

struct BoardsResponse: Codable {
  let boards: [Board]
}

struct ThreadPostsResponse: Codable {
  let posts: [Post]
}

// MARK: - Utilities

private let supportedVideoFileExtensions = ["mp4", "webm", "gif"]
private let watchedPostThrottleInterval: TimeInterval = 10
private let scrollRestoreDelayNanoseconds: UInt64 = 150_000_000

enum AppError: LocalizedError {
  case invalidURL
  case invalidThreadURL
  case httpFailure
  case saveFailure(String)
  case missingFile
  case permissionDenied

  var errorDescription: String? {
    switch self {
    case .invalidURL: return "Invalid URL."
    case .invalidThreadURL: return "This link is not supported."
    case .httpFailure: return "Failed to load data."
    case .saveFailure(let message): return message
    case .missingFile: return "File not found."
    case .permissionDenied: return "Permission denied."
    }
  }
}

func stripHTMLTags(_ body: String) -> String {
  body.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
}

func unescape(_ body: String) -> String {
  body
    .replacingOccurrences(of: "&gt;", with: ">")
    .replacingOccurrences(of: "&lt;", with: "<")
    .replacingOccurrences(of: "&amp;", with: "&")
    .replacingOccurrences(of: "&quot;", with: "\"")
    .replacingOccurrences(of: "&apos;", with: "'")
    .replacingOccurrences(of: "&#47;", with: "/")
    .replacingOccurrences(of: "&#92;", with: "\\")
    .replacingOccurrences(of: "&#039;", with: "'")
    .replacingOccurrences(of: "&#39;", with: "'")
    .replacingOccurrences(of: "&nbsp;", with: " ")
    .replacingOccurrences(of: "&copy;", with: "©")
}

func normalizedCommentText(_ raw: String?) -> String {
  let input = raw ?? ""
  if input.isEmpty { return "" }
  var text = input.replacingOccurrences(of: "<br>", with: "\n")
  text = text.replacingOccurrences(of: "<br />", with: "\n")
  text = text.replacingOccurrences(of: "<wbr>", with: "")
  text = text.replacingOccurrences(of: "<s>(.*?)</s>", with: "⟪spoiler:$1⟫", options: .regularExpression)
  text = stripHTMLTags(text)
  text = unescape(text)
  return text
}

func extractQuotedPostIDs(from body: String?) -> [Int] {
  let text = normalizedCommentText(body)
  let pattern = #">>(\d+)"#
  guard let regex = try? NSRegularExpression(pattern: pattern) else {
    return []
  }
  let nsText = text as NSString
  return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
    guard match.numberOfRanges > 1 else { return nil }
    return Int(nsText.substring(with: match.range(at: 1)))
  }
}

func parseThreadLink(_ raw: String) -> ThreadLink? {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  let prefixed = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
  guard let url = URL(string: prefixed), let host = url.host?.lowercased() else {
    return nil
  }
  guard host == "boards.4chan.org" || host == "boards.4channel.org" else {
    return nil
  }
  let components = url.pathComponents.filter { $0 != "/" }
  guard components.count >= 3,
        let threadIndex = components.firstIndex(of: "thread"),
        threadIndex > 0,
        threadIndex + 1 < components.count,
        let threadID = Int(components[threadIndex + 1])
  else {
    return nil
  }
  return ThreadLink(board: components[threadIndex - 1], thread: threadID)
}

func formatDate(epochSeconds: Int?) -> String {
  guard let epochSeconds else { return "" }
  let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
  let formatter = DateFormatter()
  formatter.dateStyle = .medium
  formatter.timeStyle = .short
  return formatter.string(from: date)
}

func formatBytes(_ bytes: Int64) -> String {
  let formatter = ByteCountFormatter()
  formatter.allowedUnits = [.useKB, .useMB, .useGB]
  formatter.countStyle = .file
  return formatter.string(fromByteCount: bytes)
}

func firstText(_ values: String?...) -> String {
  for value in values {
    let normalized = normalizedCommentText(value).trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalized.isEmpty {
      return normalized
    }
  }
  return ""
}

func boardThumbnailURL(board: String, tim: Int) -> URL? {
  URL(string: "https://i.4cdn.org/\(board)/\(tim)s.jpg")
}

func boardMediaURL(board: String, tim: Int, ext: String) -> URL? {
  URL(string: "https://i.4cdn.org/\(board)/\(tim)\(ext)")
}

func buildReplyChildrenIndex(posts: [Post]) -> [Int: [Post]] {
  let postsById = Dictionary(uniqueKeysWithValues: posts.compactMap { post in
    guard let id = post.no else { return nil }
    return (id, post)
  })
  let postOrder = Dictionary(uniqueKeysWithValues: posts.enumerated().compactMap { index, post in
    guard let id = post.no else { return nil }
    return (id, index)
  })
  var repliesByParent: [Int: [Post]] = [:]

  for post in posts {
    guard let postID = post.no else { continue }
    let quoted = extractQuotedPostIDs(from: post.com)
      .filter { postsById[$0] != nil }
      .filter { (postOrder[$0] ?? -1) < (postOrder[postID] ?? 0) }
    guard let parent = quoted.last else { continue }
    repliesByParent[parent, default: []].append(post)
  }

  for key in repliesByParent.keys {
    repliesByParent[key]?.sort { a, b in
      (postOrder[a.no ?? 0] ?? 0) < (postOrder[b.no ?? 0] ?? 0)
    }
  }

  return repliesByParent
}

func buildReplyDescendantCountIndex(posts: [Post]) -> [Int: Int] {
  let repliesByParent = buildReplyChildrenIndex(posts: posts)
  var cache: [Int: Int] = [:]

  func count(_ postID: Int) -> Int {
    if let cached = cache[postID] {
      return cached
    }
    let children = repliesByParent[postID] ?? []
    let total = children.reduce(into: 0) { result, child in
      guard let childID = child.no else { return }
      result += 1 + count(childID)
    }
    cache[postID] = total
    return total
  }

  for post in posts {
    if let id = post.no {
      _ = count(id)
    }
  }

  return cache
}

func collectReplySubtree(rootPostID: Int, posts: [Post]) -> [Post] {
  let repliesByParent = buildReplyChildrenIndex(posts: posts)
  var collected: [Post] = []
  var visited: Set<Int> = [rootPostID]

  func collect(_ parentID: Int) {
    for child in repliesByParent[parentID] ?? [] {
      guard let childID = child.no, visited.insert(childID).inserted else { continue }
      collected.append(child)
      collect(childID)
    }
  }

  collect(rootPostID)
  return collected
}

// MARK: - API

struct APIClient {
  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  func fetchBoards() async throws -> [Board] {
    let url = URL(string: "https://a.4cdn.org/boards.json")!
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response)
    return try decoder.decode(BoardsResponse.self, from: data).boards
  }

  func fetchThreads(
    board: String,
    sort: BoardSort,
    direction: SortDirection,
    searchValue: String?
  ) async throws -> [Post] {
    let url = URL(string: "https://a.4cdn.org/\(board)/catalog.json")!
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response)
    let pages = try decoder.decode([BoardThreadsResponse].self, from: data)
    var posts = pages.flatMap(\.threads)

    switch sort {
    case .byBumpOrder:
      posts.sort { ($0.lastModified ?? 0) < ($1.lastModified ?? 0) }
    case .byReplyCount:
      posts.sort { ($0.replies ?? 0) < ($1.replies ?? 0) }
    case .byImagesCount:
      posts.sort { ($0.images ?? 0) < ($1.images ?? 0) }
    case .byNewest, .byOldest:
      posts.sort { ($0.time ?? 0) < ($1.time ?? 0) }
    }

    if direction == .desc {
      posts.reverse()
    }

    if let searchValue, !searchValue.isEmpty {
      let needle = searchValue.lowercased()
      posts = posts.filter { post in
        [post.sub, post.name, post.com]
          .map { normalizedCommentText($0).lowercased() }
          .contains { $0.contains(needle) }
      }
    }

    return posts
  }

  func fetchPosts(board: String, thread: Int) async throws -> [Post] {
    let url = URL(string: "https://a.4cdn.org/\(board)/thread/\(thread).json")!
    let (data, response) = try await URLSession.shared.data(from: url)
    try validate(response)
    return try decoder.decode(ThreadPostsResponse.self, from: data).posts
  }

  func fetchBookmarkStatus(bookmark: Bookmark) async -> BookmarkStatus {
    guard let board = bookmark.board, let thread = bookmark.no,
          let url = URL(string: "https://a.4cdn.org/\(board)/thread/\(thread).json")
    else {
      return BookmarkStatus(status: .deleted, replies: nil, images: nil)
    }

    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        return BookmarkStatus(status: .deleted, replies: nil, images: nil)
      }
      if httpResponse.statusCode == 404 {
        return BookmarkStatus(status: .deleted, replies: nil, images: nil)
      }
      let posts = try decoder.decode(ThreadPostsResponse.self, from: data).posts
      guard let op = posts.first else {
        return BookmarkStatus(status: .deleted, replies: nil, images: nil)
      }
      return BookmarkStatus(
        status: op.archived == 1 ? .archived : .online,
        replies: op.replies,
        images: op.images
      )
    } catch {
      return BookmarkStatus(status: .deleted, replies: nil, images: nil)
    }
  }

  private func validate(_ response: URLResponse) throws {
    guard let httpResponse = response as? HTTPURLResponse,
          (200..<300).contains(httpResponse.statusCode)
    else {
      throw AppError.httpFailure
    }
  }
}

// MARK: - Persistence / Media

@MainActor
final class AppModel: ObservableObject {
  @Published var settings = AppSettings()
  @Published var favoriteBoards: [String] = []
  @Published var bookmarks: [Bookmark] = []
  @Published var savedAttachments: [SavedAttachment] = []
  @Published var watchedPostsByThread: [Int: WatchedPost] = [:]

  private let defaults = UserDefaults.standard
  private let api = APIClient()

  init() {
    load()
    clearExpiredWatchedPosts()
  }

  func load() {
    if let rawSort = defaults.string(forKey: "boardSort"), let value = BoardSort(rawValue: rawSort) {
      settings.boardSort = value
    }
    if let rawDirection = defaults.string(forKey: "boardSortDirection"), let value = SortDirection(rawValue: rawDirection) {
      settings.boardSortDirection = value
    }
    if let rawViewMode = defaults.string(forKey: "boardViewMode"), let value = BoardViewMode(rawValue: rawViewMode) {
      settings.boardViewMode = value
    }
    if defaults.object(forKey: "allowNSFW") != nil {
      settings.allowNSFW = defaults.bool(forKey: "allowNSFW")
    }
    if defaults.object(forKey: "autoScrollToLastSeen") != nil {
      settings.autoScrollToLastSeen = defaults.bool(forKey: "autoScrollToLastSeen")
    }
    if defaults.object(forKey: "watchedPostsRetentionDays") != nil {
      settings.watchedPostsRetentionDays = defaults.integer(forKey: "watchedPostsRetentionDays")
    }

    favoriteBoards = defaults.stringArray(forKey: "favoriteBoards") ?? []
    bookmarks = decodeBookmarks(defaults.stringArray(forKey: "favoriteThreads") ?? [])
    savedAttachments = normalizeSavedAttachments(defaults.stringArray(forKey: "savedAttachments") ?? [])
    watchedPostsByThread = decodeWatchedPosts(defaults.stringArray(forKey: "watchedPosts") ?? [])
  }

  func toggleFavorite(board: String) {
    if favoriteBoards.contains(board) {
      favoriteBoards.removeAll { $0 == board }
    } else {
      favoriteBoards.append(board)
    }
    defaults.set(favoriteBoards, forKey: "favoriteBoards")
  }

  func addBookmark(for post: Post, board: String) {
    let bookmark = Bookmark(
      no: post.no,
      sub: post.sub,
      com: post.com,
      imageUrl: post.tim.map { "\($0)s.jpg" },
      board: board
    )
    guard !bookmarks.contains(bookmark) else { return }
    bookmarks.append(bookmark)
    persistBookmarks()
  }

  func removeBookmark(_ bookmark: Bookmark) {
    bookmarks.removeAll { $0 == bookmark }
    persistBookmarks()
  }

  func clearBookmarks() {
    bookmarks = []
    persistBookmarks()
  }

  func setBoardSort(_ sort: BoardSort) {
    settings.boardSort = sort
    defaults.set(sort.rawValue, forKey: "boardSort")
  }

  func setBoardSortDirection(_ direction: SortDirection) {
    settings.boardSortDirection = direction
    defaults.set(direction.rawValue, forKey: "boardSortDirection")
  }

  func setBoardViewMode(_ mode: BoardViewMode) {
    settings.boardViewMode = mode
    defaults.set(mode.rawValue, forKey: "boardViewMode")
  }

  func setAllowNSFW(_ value: Bool) {
    settings.allowNSFW = value
    defaults.set(value, forKey: "allowNSFW")
  }

  func setAutoScrollToLastSeen(_ value: Bool) {
    settings.autoScrollToLastSeen = value
    defaults.set(value, forKey: "autoScrollToLastSeen")
  }

  func setWatchedPostsRetentionDays(_ value: Int) {
    settings.watchedPostsRetentionDays = value
    defaults.set(value, forKey: "watchedPostsRetentionDays")
    clearExpiredWatchedPosts()
  }

  func markPostWatched(index: Int, thread: Int) {
    let now = Date()
    if let existing = watchedPostsByThread[thread],
       existing.postIndex == index,
       now.timeIntervalSince(existing.watchedAt) < watchedPostThrottleInterval {
      return
    }
    watchedPostsByThread[thread] = WatchedPost(postIndex: index, thread: thread, watchedAt: now)
    persistWatchedPosts()
  }

  func latestWatchedPost(thread: Int) -> WatchedPost? {
    watchedPostsByThread[thread]
  }

  func clearWatchedPosts() {
    watchedPostsByThread = [:]
    persistWatchedPosts()
  }

  func clearExpiredWatchedPosts() {
    let cutoff = Calendar.current.date(byAdding: .day, value: -settings.watchedPostsRetentionDays, to: Date()) ?? .distantPast
    watchedPostsByThread = watchedPostsByThread.filter { _, watched in
      watched.watchedAt >= cutoff
    }
    persistWatchedPosts()
  }

  func saveRemoteAttachment(board: String, post: Post) async throws {
    guard let tim = post.tim, let ext = post.ext, let mediaURL = boardMediaURL(board: board, tim: tim, ext: ext) else {
      throw AppError.invalidURL
    }
    let fileName = "\(tim)\(ext)"
    if hasSavedAttachment(named: fileName) {
      return
    }
    let savedDirectory = try ensureSavedAttachmentsDirectory()
    let localFileURL = savedDirectory.appendingPathComponent(fileName)
    let (tempURL, _) = try await URLSession.shared.download(from: mediaURL)
    if FileManager.default.fileExists(atPath: localFileURL.path) {
      try? FileManager.default.removeItem(at: localFileURL)
    }
    try FileManager.default.moveItem(at: tempURL, to: localFileURL)

    var thumbnailName = fileName
    if post.isVideo, let thumbnailURL = boardThumbnailURL(board: board, tim: tim) {
      let thumbTarget = savedDirectory.appendingPathComponent("\(tim).jpg")
      let (thumbTemp, _) = try await URLSession.shared.download(from: thumbnailURL)
      if FileManager.default.fileExists(atPath: thumbTarget.path) {
        try? FileManager.default.removeItem(at: thumbTarget)
      }
      try FileManager.default.moveItem(at: thumbTemp, to: thumbTarget)
      thumbnailName = thumbTarget.lastPathComponent
    }

    let attachment = SavedAttachment(
      savedAttachmentType: post.isVideo ? "video" : "image",
      fileName: fileName,
      thumbnail: thumbnailName
    )
    savedAttachments.append(attachment)
    persistSavedAttachments()
  }

  func removeSavedAttachment(_ attachment: SavedAttachment) {
    let baseName = ((attachment.fileName ?? "") as NSString).deletingPathExtension
    savedAttachments.removeAll { $0.id == attachment.id }
    persistSavedAttachments()

    let directory = savedAttachmentsDirectory()
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    for file in files where file.lastPathComponent.contains(baseName) {
      try? FileManager.default.removeItem(at: file)
    }
  }

  func clearSavedAttachments() {
    savedAttachments = []
    persistSavedAttachments()
    let directory = savedAttachmentsDirectory()
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    for file in files {
      try? FileManager.default.removeItem(at: file)
    }
  }

  func localURL(for attachment: SavedAttachment) -> URL {
    savedAttachmentsDirectory().appendingPathComponent(attachment.fileName ?? "")
  }

  func thumbnailURL(for attachment: SavedAttachment) -> URL {
    savedAttachmentsDirectory().appendingPathComponent(attachment.thumbnail ?? attachment.fileName ?? "")
  }

  func exportRemoteMediaToPhotos(board: String, post: Post) async throws {
    guard let tim = post.tim, let ext = post.ext, let url = boardMediaURL(board: board, tim: tim, ext: ext) else {
      throw AppError.invalidURL
    }
    let tempURL = try await downloadToTemporaryFile(from: url, suggestedName: "\(tim)\(ext)")
    try await exportLocalFileToPhotos(tempURL)
  }

  func exportSavedMediaToPhotos(_ attachment: SavedAttachment) async throws {
    try await exportLocalFileToPhotos(localURL(for: attachment))
  }

  func prepareRemoteMediaForShare(board: String, post: Post) async throws -> URL {
    guard let tim = post.tim, let ext = post.ext, let url = boardMediaURL(board: board, tim: tim, ext: ext) else {
      throw AppError.invalidURL
    }
    return try await downloadToTemporaryFile(from: url, suggestedName: "\(tim)\(ext)")
  }

  func savedCacheUsageDescription() -> String {
    let savedSize = folderSize(savedAttachmentsDirectory())
    let cacheSize = Int64(URLCache.shared.currentDiskUsage)
    return formatBytes(savedSize + cacheSize)
  }

  func hasSavedAttachment(named fileName: String) -> Bool {
    let baseName = (fileName as NSString).deletingPathExtension
    return savedAttachmentBaseNames.contains(baseName)
  }

  func hasSavedAttachment(baseName: String) -> Bool {
    savedAttachmentBaseNames.contains(baseName)
  }

  func clearCache() {
    URLCache.shared.removeAllCachedResponses()
    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("NekoSurfShare", isDirectory: true)
    let files = (try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)) ?? []
    for file in files {
      try? FileManager.default.removeItem(at: file)
    }
  }

  func fetchBookmarkStatus(_ bookmark: Bookmark) async -> BookmarkStatus {
    await api.fetchBookmarkStatus(bookmark: bookmark)
  }

  private func persistBookmarks() {
    let encoded = bookmarks.compactMap { bookmark in
      guard let data = try? JSONEncoder().encode(bookmark),
            let string = String(data: data, encoding: .utf8) else { return nil }
      return string
    }
    defaults.set(encoded, forKey: "favoriteThreads")
  }

  private func persistSavedAttachments() {
    let encoded = savedAttachments.compactMap { attachment in
      guard let data = try? JSONEncoder().encode(attachment),
            let string = String(data: data, encoding: .utf8) else { return nil }
      return string
    }
    defaults.set(encoded, forKey: "savedAttachments")
  }

  private func persistWatchedPosts() {
    let encoded = watchedPostsByThread.values.compactMap { watchedPost in
      guard let data = try? JSONEncoder().encode(watchedPost),
            let string = String(data: data, encoding: .utf8) else { return nil }
      return string
    }
    defaults.set(encoded, forKey: "watchedPosts")
  }

  private func decodeBookmarks(_ rawValues: [String]) -> [Bookmark] {
    rawValues.compactMap { raw in
      guard let data = raw.data(using: .utf8) else { return nil }
      return try? JSONDecoder().decode(Bookmark.self, from: data)
    }
  }

  private func normalizeSavedAttachments(_ rawValues: [String]) -> [SavedAttachment] {
    rawValues.compactMap { raw in
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return nil }
      if trimmed.hasPrefix("{") {
        guard let data = trimmed.data(using: .utf8),
              let attachment = try? JSONDecoder().decode(SavedAttachment.self, from: data) else {
          return nil
        }
        return attachment
      }
      let ext = (trimmed as NSString).pathExtension.lowercased()
      let isVideo = supportedVideoFileExtensions.contains(ext)
      let baseName = (trimmed as NSString).deletingPathExtension
      return SavedAttachment(
        savedAttachmentType: isVideo ? "video" : "image",
        fileName: trimmed,
        thumbnail: isVideo ? "\(baseName).jpg" : trimmed
      )
    }
  }

  private func decodeWatchedPosts(_ rawValues: [String]) -> [Int: WatchedPost] {
    var values: [Int: WatchedPost] = [:]
    let decoder = JSONDecoder()
    for raw in rawValues {
      guard let data = raw.data(using: .utf8), let watched = try? decoder.decode(WatchedPost.self, from: data) else {
        continue
      }
      if let current = values[watched.thread] {
        if watched.watchedAt > current.watchedAt {
          values[watched.thread] = watched
        }
      } else {
        values[watched.thread] = watched
      }
    }
    return values
  }

  private func documentsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
  }

  private func savedAttachmentsDirectory() -> URL {
    documentsDirectory().appendingPathComponent("savedAttachments", isDirectory: true)
  }

  @discardableResult
  private func ensureSavedAttachmentsDirectory() throws -> URL {
    let directory = savedAttachmentsDirectory()
    if !FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory
  }

  private func downloadToTemporaryFile(from sourceURL: URL, suggestedName: String) async throws -> URL {
    let shareDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("NekoSurfShare", isDirectory: true)
    if !FileManager.default.fileExists(atPath: shareDirectory.path) {
      try FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
    }
    let target = shareDirectory.appendingPathComponent(suggestedName)
    let (tempURL, _) = try await URLSession.shared.download(from: sourceURL)
    if FileManager.default.fileExists(atPath: target.path) {
      try? FileManager.default.removeItem(at: target)
    }
    try FileManager.default.moveItem(at: tempURL, to: target)
    return target
  }

  private func exportLocalFileToPhotos(_ fileURL: URL) async throws {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else {
      throw AppError.permissionDenied
    }

    let ext = fileURL.pathExtension.lowercased()
    try await withCheckedThrowingContinuation { continuation in
      PHPhotoLibrary.shared().performChanges({
        if supportedVideoFileExtensions.contains(ext) || ext == "mov" {
          PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: fileURL, options: nil)
        } else {
          PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: fileURL, options: nil)
        }
      }, completionHandler: { success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume(returning: ())
        } else {
          continuation.resume(throwing: AppError.saveFailure("Failed to save media to photo library."))
        }
      })
    }
  }

  private func folderSize(_ directory: URL) -> Int64 {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
    return files.reduce(into: 0) { result, url in
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init) ?? 0
      result += size
    }
  }

  private var savedAttachmentBaseNames: Set<String> {
    Set(savedAttachments.compactMap { attachment in
      guard let fileName = attachment.fileName else { return nil }
      return (fileName as NSString).deletingPathExtension
    })
  }
}

// MARK: - Reusable Views

struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ErrorItem: Identifiable {
  let id = UUID()
  let message: String
}

struct SharePayload: Identifiable {
  let id = UUID()
  let url: URL
}

struct LoadingView: View {
  var body: some View {
    VStack(spacing: 12) {
      ProgressView()
      Text("Loading...")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityLabel("Loading content")
  }
}

struct EmptyStateView: View {
  let title: String
  let subtitle: String?

  var body: some View {
    ContentUnavailableView(
      title,
      systemImage: "tray",
      description: subtitle.map(Text.init)
    )
  }
}

struct ReloadView: View {
  let message: String
  let action: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Text(message)
      Button("Reload", action: action)
        .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct AsyncRemoteImage: View {
  let url: URL?
  let contentMode: ContentMode

  var body: some View {
    AsyncImage(url: url) { phase in
      switch phase {
      case .empty:
        Rectangle()
          .fill(Color.secondary.opacity(0.15))
          .overlay(ProgressView())
      case .success(let image):
        image
          .resizable()
          .aspectRatio(contentMode: contentMode)
      case .failure:
        Rectangle()
          .fill(Color.secondary.opacity(0.15))
          .overlay(Image(systemName: "photo"))
      @unknown default:
        Color.clear
      }
    }
  }
}

struct LocalFileImage: View {
  let url: URL

  var body: some View {
    if let image = UIImage(contentsOfFile: url.path) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      Rectangle()
        .fill(Color.secondary.opacity(0.15))
        .overlay(Image(systemName: "photo"))
    }
  }
}

struct RepliesSummaryView: View {
  let replies: String
  let images: String?

  var body: some View {
    HStack(spacing: 12) {
      Label(replies, systemImage: "text.bubble")
      if let images {
        Label(images, systemImage: "photo")
      }
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
  }
}

struct SpoilerText: View {
  let text: String
  @State private var revealed = false

  var body: some View {
    Text(revealed ? text : String(repeating: "█", count: max(4, min(text.count, 20))))
      .foregroundStyle(revealed ? .primary : .black)
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(revealed ? Color.secondary.opacity(0.15) : Color.primary)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .onTapGesture {
        revealed.toggle()
      }
  }
}

struct CommentRenderer: View {
  let rawComment: String
  let board: String
  let thread: Int
  let allPosts: [Post]

  @State private var selectedPost: Post?

  private func tokenizedLines() -> [[CommentToken]] {
    normalizedCommentText(rawComment)
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in tokenize(String(line)) }
  }

  private func tokenize(_ line: String) -> [CommentToken] {
    let pattern = #"(⟪spoiler:.*?⟫|>>\d+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return [.text(line)]
    }
    let nsLine = line as NSString
    let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
    if matches.isEmpty {
      return [.text(line)]
    }
    var tokens: [CommentToken] = []
    var lastIndex = 0
    for match in matches {
      if match.range.location > lastIndex {
        tokens.append(.text(nsLine.substring(with: NSRange(location: lastIndex, length: match.range.location - lastIndex))))
      }
      let value = nsLine.substring(with: match.range)
      if value.hasPrefix(">>") {
        tokens.append(.quoteLink(Int(value.dropFirst(2)) ?? 0))
      } else if value.hasPrefix("⟪spoiler:") {
        let spoiler = value
          .replacingOccurrences(of: "⟪spoiler:", with: "")
          .replacingOccurrences(of: "⟫", with: "")
        tokens.append(.spoiler(spoiler))
      }
      lastIndex = match.range.location + match.range.length
    }
    if lastIndex < nsLine.length {
      tokens.append(.text(nsLine.substring(from: lastIndex)))
    }
    return tokens
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(tokenizedLines().enumerated()), id: \.offset) { entry in
        let tokens = entry.element
        if tokens.count == 1, case .text(let line) = tokens[0], line.isEmpty {
          Color.clear.frame(height: 8)
        } else {
          lineView(tokens)
        }
      }
    }
    .sheet(item: $selectedPost) { post in
      NavigationStack {
        SinglePostView(post: post, board: board, thread: thread, allPosts: allPosts)
      }
    }
  }

  @ViewBuilder
  private func lineView(_ tokens: [CommentToken]) -> some View {
    let isQuoteLine = tokens.allSatisfy {
      switch $0 {
      case .text(let value):
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix(">")
      case .quoteLink:
        return true
      case .spoiler:
        return false
      }
    }

    HStack(alignment: .firstTextBaseline, spacing: 0) {
      ForEach(Array(tokens.enumerated()), id: \.offset) { entry in
        let token = entry.element
        switch token {
        case .text(let value):
          Text(value)
            .foregroundStyle(isQuoteLine ? Color.green : Color.primary)
        case .quoteLink(let target):
          Button {
            selectedPost = allPosts.first(where: { $0.no == target })
          } label: {
            Text(">>\(target)")
              .foregroundStyle(.blue)
              .fontWeight(.semibold)
          }
          .buttonStyle(.plain)
        case .spoiler(let value):
          SpoilerText(text: value)
        }
      }
    }
    .font(.body)
  }

  private enum CommentToken {
    case text(String)
    case quoteLink(Int)
    case spoiler(String)
  }
}

// MARK: - Root UI

struct RootTabView: View {
  enum Tab {
    case boards
    case attachments
    case bookmarks
    case settings
  }

  @State private var selection: Tab = .boards

  var body: some View {
    TabView(selection: $selection) {
      BoardsRootView()
        .tabItem {
          Label("Boards", systemImage: "square.grid.2x2.fill")
        }
        .tag(Tab.boards)

      SavedAttachmentsRootView()
        .tabItem {
          Label("Attachments", systemImage: "paperclip")
        }
        .tag(Tab.attachments)

      BookmarksRootView()
        .tabItem {
          Label("Bookmarks", systemImage: "bookmark.fill")
        }
        .tag(Tab.bookmarks)

      SettingsRootView()
        .tabItem {
          Label("Settings", systemImage: "gearshape")
        }
        .tag(Tab.settings)
    }
  }
}

// MARK: - Boards

struct BoardsRootView: View {
  @EnvironmentObject private var store: AppModel
  @State private var boards: [Board] = []
  @State private var filteredBoards: [Board] = []
  @State private var isLoading = true
  @State private var error: ErrorItem?
  @State private var searchText = ""
  @State private var openLinkPresented = false
  @State private var pendingThreadLink: ThreadLink?

  private let api = APIClient()

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          LoadingView()
        } else if let error {
          ReloadView(message: error.message, action: reload)
        } else {
          List {
            if !favoriteBoards.isEmpty {
              Section("Favorites") {
                ForEach(favoriteBoards) { board in
                  BoardRow(board: board, isFavorite: true)
                }
              }
            }

            Section("Boards") {
              ForEach(boardRows) { board in
                BoardRow(board: board, isFavorite: favoriteIDs.contains(board.board ?? ""))
              }
            }
          }
          .listStyle(.insetGrouped)
        }
      }
      .navigationTitle("NekoSurf")
      .searchable(text: $searchText, prompt: "Search boards")
      .onChange(of: searchText) { _, _ in filterBoards() }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            openLinkPresented = true
          } label: {
            Image(systemName: "link")
          }
        }
      }
      .sheet(isPresented: $openLinkPresented) {
        OpenLinkSheet { link in
          pendingThreadLink = link
        }
      }
      .navigationDestination(item: $pendingThreadLink) { link in
        ThreadPage(board: link.board, threadID: link.thread, initialPost: nil, threadTitle: nil)
      }
      .task { reloadIfNeeded() }
    }
  }

  private var favoriteIDs: Set<String> {
    Set(store.favoriteBoards)
  }

  private var visibleBoards: [Board] {
    store.settings.allowNSFW ? filteredBoards : filteredBoards.filter(\.isWorkSafe)
  }

  private var favoriteBoards: [Board] {
    visibleBoards.filter { favoriteIDs.contains($0.board ?? "") }
  }

  private var boardRows: [Board] {
    visibleBoards
  }

  private func reloadIfNeeded() {
    if boards.isEmpty {
      reload()
    }
  }

  private func reload() {
    isLoading = true
    error = nil
    Task {
      do {
        let fetched = try await api.fetchBoards()
        await MainActor.run {
          boards = fetched
          filteredBoards = fetched
          isLoading = false
          filterBoards()
        }
      } catch {
        await MainActor.run {
          isLoading = false
          self.error = ErrorItem(message: error.localizedDescription)
        }
      }
    }
  }

  private func filterBoards() {
    guard !searchText.isEmpty else {
      filteredBoards = boards
      return
    }
    let needle = searchText.lowercased()
    filteredBoards = boards.filter { board in
      [board.board, board.metaDescription, board.title]
        .compactMap { $0?.lowercased() }
        .contains { $0.contains(needle) }
    }
  }
}

struct BoardRow: View {
  @EnvironmentObject private var store: AppModel
  let board: Board
  let isFavorite: Bool

  var body: some View {
    NavigationLink {
      BoardPage(boardID: board.board ?? "", boardName: board.title ?? board.board ?? "")
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("/\(board.board ?? "")/ - \(board.title ?? "")")
            .font(.headline)
          Spacer()
          if isFavorite {
            Image(systemName: "star.fill")
              .foregroundStyle(.yellow)
          }
        }
        Text(board.metaDescription ?? "")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
        if let boardID = board.board {
          store.toggleFavorite(board: boardID)
        }
      } label: {
        Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
      }
      .tint(.yellow)
    }
  }
}

struct OpenLinkSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var urlText = ""
  @State private var error: String?

  let onOpen: (ThreadLink) -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("4chan Thread URL") {
          TextField("Insert thread URL", text: $urlText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
          if let error {
            Text(error)
              .foregroundStyle(.red)
              .font(.footnote)
          }
        }
      }
      .navigationTitle("Open Link")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Open") {
            guard let link = parseThreadLink(urlText) else {
              error = "This link is not supported"
              return
            }
            onOpen(link)
            dismiss()
          }
        }
      }
    }
  }
}

// MARK: - Board Page

struct BoardPage: View {
  @EnvironmentObject private var store: AppModel
  let boardID: String
  let boardName: String

  @State private var threads: [Post] = []
  @State private var isLoading = true
  @State private var error: ErrorItem?
  @State private var searchText = ""

  private let api = APIClient()

  var body: some View {
    Group {
      if isLoading {
        LoadingView()
      } else if let error {
        ReloadView(message: error.message, action: reload)
      } else {
        ScrollView {
          if store.settings.boardViewMode == .list {
            LazyVStack(spacing: 12) {
              ForEach(threads) { thread in
                ThreadPreviewCard(boardID: boardID, post: thread, isGrid: false)
              }
            }
            .padding()
          } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
              ForEach(threads) { thread in
                ThreadPreviewCard(boardID: boardID, post: thread, isGrid: true)
              }
            }
            .padding()
          }
        }
      }
    }
    .navigationTitle("/\(boardID)/")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "Search threads")
    .onChange(of: searchText) { _, _ in reload() }
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          store.toggleFavorite(board: boardID)
        } label: {
          Image(systemName: store.favoriteBoards.contains(boardID) ? "star.fill" : "star")
            .foregroundStyle(.yellow)
        }

        Button {
          store.setBoardViewMode(store.settings.boardViewMode == .grid ? .list : .grid)
        } label: {
          Image(systemName: store.settings.boardViewMode == .grid ? "list.bullet" : "square.grid.2x2")
        }

        Menu {
          Section("Sort") {
            ForEach(BoardSort.allCases, id: \.self) { sort in
              Button {
                store.setBoardSort(sort)
                reload()
              } label: {
                Label(sort.title, systemImage: store.settings.boardSort == sort ? "checkmark" : "")
              }
            }
          }
          Section("Direction") {
            ForEach(SortDirection.allCases, id: \.self) { direction in
              Button {
                store.setBoardSortDirection(direction)
                reload()
              } label: {
                Label(direction.title, systemImage: store.settings.boardSortDirection == direction ? "checkmark" : "")
              }
            }
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }
      }
    }
    .task { reloadIfNeeded() }
  }

  private func reloadIfNeeded() {
    if threads.isEmpty {
      reload()
    }
  }

  private func reload() {
    isLoading = true
    error = nil
    Task {
      do {
        let fetched = try await api.fetchThreads(
          board: boardID,
          sort: store.settings.boardSort,
          direction: store.settings.boardSortDirection,
          searchValue: searchText
        )
        await MainActor.run {
          threads = fetched
          isLoading = false
        }
      } catch {
        await MainActor.run {
          self.error = ErrorItem(message: error.localizedDescription)
          isLoading = false
        }
      }
    }
  }
}

struct ThreadPreviewCard: View {
  let boardID: String
  let post: Post
  let isGrid: Bool

  var body: some View {
    NavigationLink {
      ThreadPage(
        board: boardID,
        threadID: post.no ?? 0,
        initialPost: post,
        threadTitle: post.sub ?? post.com
      )
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        if let tim = post.tim {
          AsyncRemoteImage(url: boardThumbnailURL(board: boardID, tim: tim), contentMode: .fill)
            .frame(height: isGrid ? 150 : 190)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        Text(firstText(post.sub, post.com, post.name, "No.\(post.no ?? 0)"))
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(isGrid ? 2 : 3)
        Text(firstText(post.com, post.sub))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(isGrid ? 3 : 4)
        RepliesSummaryView(replies: String(post.replies ?? 0), images: String(post.images ?? 0))
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Thread Page

struct ThreadPage: View {
  @EnvironmentObject private var store: AppModel
  @Environment(\.openURL) private var openURL

  let board: String
  let threadID: Int
  let initialPost: Post?
  let threadTitle: String?

  @State private var posts: [Post] = []
  @State private var replyCounts: [Int: Int] = [:]
  @State private var isLoading = true
  @State private var error: ErrorItem?
  @State private var selectedMediaIndex = 0
  @State private var showingMediaViewer = false
  @State private var sharePayload: SharePayload?
  @State private var errorAlert: ErrorItem?

  private let api = APIClient()

  var body: some View {
    Group {
      if isLoading {
        LoadingView()
      } else if let error {
        ReloadView(message: error.message, action: reload)
      } else {
        ScrollViewReader { proxy in
          List {
            ForEach(Array(posts.enumerated()), id: \.element.id) { entry in
              let index = entry.offset
              let post = entry.element
              ThreadPostCard(
                board: board,
                thread: threadID,
                post: post,
                allPosts: posts,
                replyCount: replyCounts[post.no ?? 0] ?? 0,
                onMediaSelected: { currentPost in
                  selectedMediaIndex = mediaPosts.firstIndex(where: { $0.id == currentPost.id }) ?? 0
                  showingMediaViewer = true
                }
              )
              .id(index)
              .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
              .listRowSeparator(.hidden)
              .listRowBackground(Color.clear)
              .onAppear {
                store.markPostWatched(index: index, thread: threadID)
              }
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .task {
            guard store.settings.autoScrollToLastSeen,
                  let watched = store.latestWatchedPost(thread: threadID),
                  watched.postIndex < posts.count
            else {
              return
            }
            try? await Task.sleep(nanoseconds: scrollRestoreDelayNanoseconds)
            withAnimation(.easeInOut(duration: 0.45)) {
              proxy.scrollTo(watched.postIndex, anchor: .top)
            }
          }
          .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
              Button {
                withAnimation(.easeInOut(duration: 0.35)) {
                  proxy.scrollTo(0, anchor: .top)
                }
              } label: {
                Label("Top", systemImage: "arrow.up")
              }
              .buttonStyle(.bordered)

              Button {
                guard let lastIndex = posts.indices.last else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                  proxy.scrollTo(lastIndex, anchor: .bottom)
                }
              } label: {
                Label("Bottom", systemImage: "arrow.down")
              }
              .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
          }
        }
      }
    }
    .navigationTitle(displayTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
    ToolbarItemGroup(placement: .topBarTrailing) {
      Button {
        if let bookmark = posts.first ?? initialPost {
          if let existing = store.bookmarks.first(where: { $0.no == bookmark.no && $0.board == board }) {
            store.removeBookmark(existing)
          } else {
            store.addBookmark(for: bookmark, board: board)
          }
        }
      } label: {
          Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
        }

        Menu {
          ShareLinkItemButton(title: "Share Thread") {
            if let url = URL(string: "https://boards.4chan.org/\(board)/thread/\(threadID)") {
              sharePayload = SharePayload(url: url)
            }
          }
          Button("Open in Browser", systemImage: "globe") {
            if let url = URL(string: "https://boards.4chan.org/\(board)/thread/\(threadID)") {
              openURL(url)
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .task { reloadIfNeeded() }
    .sheet(isPresented: $showingMediaViewer) {
      MediaViewer(
        items: mediaPosts.map { MediaItem.remote(board: board, post: $0) },
        initialIndex: selectedMediaIndex,
        canDelete: false
      )
      .environmentObject(store)
    }
    .sheet(item: $sharePayload) { payload in
      ActivityView(items: [payload.url])
    }
    .alert(item: $errorAlert) { item in
      Alert(title: Text("Error"), message: Text(item.message), dismissButton: .default(Text("OK")))
    }
  }

  private var mediaPosts: [Post] {
    posts.filter(\.hasMedia)
  }

  private var displayTitle: String {
    let title = firstText(threadTitle, posts.first?.sub, posts.first?.com)
    return title.isEmpty ? "/\(board)/ No.\(threadID)" : title
  }

  private var isBookmarked: Bool {
    store.bookmarks.contains { $0.no == threadID && $0.board == board }
  }

  private func reloadIfNeeded() {
    if posts.isEmpty {
      reload()
    }
  }

  private func reload() {
    isLoading = true
    error = nil
    Task {
      do {
        let fetched = try await api.fetchPosts(board: board, thread: threadID)
        await MainActor.run {
          posts = fetched
          replyCounts = buildReplyDescendantCountIndex(posts: fetched)
          isLoading = false
        }
      } catch {
        await MainActor.run {
          self.error = ErrorItem(message: error.localizedDescription)
          isLoading = false
        }
      }
    }
  }
}

struct ThreadPostCard: View {
  let board: String
  let thread: Int
  let post: Post
  let allPosts: [Post]
  let replyCount: Int
  let onMediaSelected: (Post) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        Circle()
          .fill(Color.blue.opacity(0.15))
          .frame(width: 28, height: 28)
          .overlay(
            Text(String((post.name ?? "Anonymous").trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
              .font(.caption.weight(.bold))
              .foregroundStyle(.blue)
          )

        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(post.name ?? "Anonymous")
              .font(.subheadline.weight(.semibold))
            Spacer()
            Text("No.\(post.no ?? 0)")
              .font(.caption)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.secondary.opacity(0.15), in: Capsule())
          }
          Text(formatDate(epochSeconds: post.time))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if !firstText(post.sub).isEmpty {
        Text(firstText(post.sub))
          .font(.headline)
      }

      if post.hasMedia, let tim = post.tim, let ext = post.ext {
        Button {
          onMediaSelected(post)
        } label: {
          Group {
            if post.isVideo, let mediaURL = boardMediaURL(board: board, tim: tim, ext: ext) {
              VideoPlayer(player: AVPlayer(url: mediaURL))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
              AsyncRemoteImage(url: boardThumbnailURL(board: board, tim: tim), contentMode: .fill)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
          }
        }
        .buttonStyle(.plain)
      }

      if let com = post.com, !normalizedCommentText(com).isEmpty {
        CommentRenderer(rawComment: com, board: board, thread: thread, allPosts: allPosts)
      }

      if replyCount > 0 {
        NavigationLink {
          ReplyTreeView(rootPost: post, board: board, thread: thread, allPosts: allPosts)
        } label: {
          RepliesSummaryView(replies: String(replyCount), images: nil)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
      }
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}

struct SinglePostView: View {
  let post: Post
  let board: String
  let thread: Int
  let allPosts: [Post]

  var body: some View {
    ThreadPostCard(
      board: board,
      thread: thread,
      post: post,
      allPosts: allPosts,
      replyCount: 0,
      onMediaSelected: { _ in }
    )
    .padding()
    .navigationTitle("Replies to #\(post.no ?? 0)")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct ReplyTreeView: View {
  let rootPost: Post
  let board: String
  let thread: Int
  let allPosts: [Post]

  @State private var collapsedPostIDs: Set<Int> = []

  private var entries: [ReplyTreeEntry] {
    let repliesByParent = buildReplyChildrenIndex(posts: allPosts)
    var values: [ReplyTreeEntry] = []
    var visited: Set<Int> = [rootPost.no ?? 0]

    func appendChildren(parentID: Int, depth: Int) {
      for child in repliesByParent[parentID] ?? [] {
        guard let childID = child.no, visited.insert(childID).inserted else { continue }
        let isCollapsed = collapsedPostIDs.contains(childID)
        values.append(
          ReplyTreeEntry(
            post: child,
            depth: depth,
            hiddenReplyCount: descendantCounts[childID] ?? 0,
            isCollapsed: isCollapsed
          )
        )
        if !isCollapsed {
          appendChildren(parentID: childID, depth: depth + 1)
        }
      }
    }

    appendChildren(parentID: rootPost.no ?? 0, depth: 0)
    return values
  }

  private var descendantCountIndex: [Int: Int] {
    buildReplyDescendantCountIndex(posts: allPosts)
  }

  var body: some View {
    let descendantCounts = descendantCountIndex
    List {
      if entries.isEmpty {
        EmptyStateView(title: "No threaded replies were found for this post.", subtitle: nil)
      } else {
        ForEach(entries) { entry in
          HStack(alignment: .top, spacing: 12) {
            Color.clear.frame(width: CGFloat(min(entry.depth, 5)) * 16)
            VStack(alignment: .leading, spacing: 10) {
              if entry.isCollapsed {
                Button {
                  toggle(entry)
                } label: {
                  let hiddenReplyTotal = entry.hiddenReplyCount + 1
                  Text("\(hiddenReplyTotal) hidden \(hiddenReplyTotal == 1 ? "reply" : "replies")")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
              } else {
                ThreadPostCard(
                  board: board,
                  thread: thread,
                  post: entry.post,
                  allPosts: allPosts,
                  replyCount: descendantCounts[entry.post.no ?? 0] ?? 0,
                  onMediaSelected: { _ in }
                )
                .onTapGesture {
                  toggle(entry)
                }
              }
            }
          }
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .navigationTitle("Replies to #\(rootPost.no ?? 0)")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func toggle(_ entry: ReplyTreeEntry) {
    guard let id = entry.post.no else { return }
    if collapsedPostIDs.contains(id) {
      collapsedPostIDs.remove(id)
    } else {
      collapsedPostIDs.insert(id)
    }
  }
}

struct ReplyTreeEntry: Identifiable {
  let post: Post
  let depth: Int
  let hiddenReplyCount: Int
  let isCollapsed: Bool

  var id: String { post.id }
}

// MARK: - Media Viewer

enum MediaItem: Identifiable {
  case remote(board: String, post: Post)
  case local(SavedAttachment)

  var id: String {
    switch self {
    case .remote(let board, let post):
      return "remote-\(board)-\(post.id)"
    case .local(let attachment):
      return "local-\(attachment.id)"
    }
  }
}

struct MediaViewer: View {
  @EnvironmentObject private var store: AppModel
  @Environment(\.dismiss) private var dismiss

  let items: [MediaItem]
  let initialIndex: Int
  let canDelete: Bool

  @State private var currentIndex: Int
  @State private var sharePayload: SharePayload?
  @State private var error: ErrorItem?
  @State private var localItems: [MediaItem]

  init(items: [MediaItem], initialIndex: Int, canDelete: Bool) {
    self.items = items
    self.initialIndex = initialIndex
    self.canDelete = canDelete
    _currentIndex = State(initialValue: initialIndex)
    _localItems = State(initialValue: items)
  }

  var body: some View {
    NavigationStack {
      TabView(selection: $currentIndex) {
        ForEach(Array(displayItems.enumerated()), id: \.element.id) { entry in
          let index = entry.offset
          let item = entry.element
          mediaPage(item)
            .tag(index)
            .background(Color.black.ignoresSafeArea())
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .background(Color.black.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
            .tint(.white)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          if case .remote = currentItem {
            Button {
              Task { await saveCurrentRemoteMedia() }
            } label: {
              Image(systemName: isCurrentRemoteSaved ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
            }
            .tint(.white)
          }

          Button {
            Task { await shareCurrentMedia() }
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .tint(.white)

          Button {
            Task { await exportCurrentMedia() }
          } label: {
            Image(systemName: "arrow.down.to.line")
          }
          .tint(.white)

          if canDelete {
            Button(role: .destructive) {
              removeCurrentMedia()
            } label: {
              Image(systemName: "trash")
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Text(currentName)
          .font(.footnote)
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .frame(maxWidth: .infinity)
          .background(.black.opacity(0.6))
      }
      .sheet(item: $sharePayload) { payload in
        ActivityView(items: [payload.url])
      }
      .alert(item: $error) { error in
        Alert(title: Text("Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
      }
    }
  }

  private var displayItems: [MediaItem] {
    canDelete ? localItems : items
  }

  private var currentItem: MediaItem {
    displayItems[max(0, min(currentIndex, displayItems.count - 1))]
  }

  private var currentName: String {
    switch currentItem {
    case .remote(_, let post):
      if let tim = post.tim, let ext = post.ext {
        return "\(tim)\(ext)"
      }
      return "Media"
    case .local(let attachment):
      return attachment.fileName ?? "Media"
    }
  }

  @ViewBuilder
  private func mediaPage(_ item: MediaItem) -> some View {
    switch item {
    case .remote(let board, let post):
      if let tim = post.tim, let ext = post.ext, let mediaURL = boardMediaURL(board: board, tim: tim, ext: ext) {
        if post.isVideo {
          VideoPlayer(player: AVPlayer(url: mediaURL))
            .ignoresSafeArea()
        } else {
          ZoomableRemoteImage(url: mediaURL)
        }
      }
    case .local(let attachment):
      let fileURL = store.localURL(for: attachment)
      if attachment.resolvedType == .video {
        VideoPlayer(player: AVPlayer(url: fileURL))
          .ignoresSafeArea()
      } else {
        ZoomableLocalImage(url: fileURL)
      }
    }
  }

  private func shareCurrentMedia() async {
    do {
      switch currentItem {
      case .remote(let board, let post):
        sharePayload = SharePayload(url: try await store.prepareRemoteMediaForShare(board: board, post: post))
      case .local(let attachment):
        sharePayload = SharePayload(url: store.localURL(for: attachment))
      }
    } catch {
      self.error = ErrorItem(message: error.localizedDescription)
    }
  }

  private var isCurrentRemoteSaved: Bool {
    guard case .remote(_, let post) = currentItem,
          let tim = post.tim
    else {
      return false
    }
    return store.hasSavedAttachment(baseName: String(tim))
  }

  private func saveCurrentRemoteMedia() async {
    guard case .remote(let board, let post) = currentItem else { return }
    do {
      try await store.saveRemoteAttachment(board: board, post: post)
    } catch {
      self.error = ErrorItem(message: error.localizedDescription)
    }
  }

  private func exportCurrentMedia() async {
    do {
      switch currentItem {
      case .remote(let board, let post):
        try await store.exportRemoteMediaToPhotos(board: board, post: post)
      case .local(let attachment):
        try await store.exportSavedMediaToPhotos(attachment)
      }
    } catch {
      self.error = ErrorItem(message: error.localizedDescription)
    }
  }

  private func removeCurrentMedia() {
    guard case .local(let attachment) = currentItem else { return }
    store.removeSavedAttachment(attachment)
    localItems.removeAll { item in
      if case .local(let currentAttachment) = item {
        return currentAttachment.id == attachment.id
      }
      return false
    }
    if localItems.isEmpty {
      dismiss()
    } else if currentIndex >= localItems.count {
      currentIndex = max(0, localItems.count - 1)
    }
  }
}

struct ZoomableRemoteImage: View {
  let url: URL

  var body: some View {
    ScrollView([.horizontal, .vertical]) {
      AsyncRemoteImage(url: url, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color.black)
  }
}

struct ZoomableLocalImage: View {
  let url: URL

  var body: some View {
    ScrollView([.horizontal, .vertical]) {
      LocalFileImage(url: url)
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color.black)
  }
}

struct ShareLinkItemButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(title, systemImage: "square.and.arrow.up", action: action)
  }
}

// MARK: - Saved Attachments

struct SavedAttachmentsRootView: View {
  @EnvironmentObject private var store: AppModel
  @State private var selectedIndex = 0
  @State private var showingViewer = false

  private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

  var body: some View {
    NavigationStack {
      Group {
        if store.savedAttachments.isEmpty {
          EmptyStateView(title: "Save attachments first!", subtitle: nil)
        } else {
          ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
              ForEach(Array(store.savedAttachments.enumerated()), id: \.element.id) { entry in
                let index = entry.offset
                let attachment = entry.element
                Button {
                  selectedIndex = index
                  showingViewer = true
                } label: {
                  ZStack {
                    LocalFileImage(url: store.thumbnailURL(for: attachment))
                      .frame(height: 120)
                      .clipShape(RoundedRectangle(cornerRadius: 8))
                    if attachment.resolvedType == .video {
                      Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                    }
                  }
                }
                .buttonStyle(.plain)
              }
            }
            .padding(4)
          }
        }
      }
      .navigationTitle("Saved Attachments")
      .toolbar {
        if !store.savedAttachments.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
              store.clearSavedAttachments()
            } label: {
              Image(systemName: "trash")
            }
          }
        }
      }
      .sheet(isPresented: $showingViewer) {
        MediaViewer(items: store.savedAttachments.map(MediaItem.local), initialIndex: selectedIndex, canDelete: true)
          .environmentObject(store)
      }
    }
  }
}

// MARK: - Bookmarks

struct BookmarksRootView: View {
  @EnvironmentObject private var store: AppModel
  @State private var sortNewestFirst = true

  var body: some View {
    NavigationStack {
      Group {
        if store.bookmarks.isEmpty {
          EmptyStateView(title: "Add bookmarks first!", subtitle: nil)
        } else {
          List {
            ForEach(sortedBookmarks) { bookmark in
              BookmarkRow(bookmark: bookmark)
            }
            .onDelete { indexes in
              indexes.map { sortedBookmarks[$0] }.forEach(store.removeBookmark)
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Bookmarks")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Menu {
            Button("Newest") { sortNewestFirst = true }
            Button("Oldest") { sortNewestFirst = false }
          } label: {
            Image(systemName: "arrow.up.arrow.down")
          }

          if !store.bookmarks.isEmpty {
            Button(role: .destructive) {
              store.clearBookmarks()
            } label: {
              Image(systemName: "trash")
            }
          }
        }
      }
    }
  }

  private var sortedBookmarks: [Bookmark] {
    sortNewestFirst ? store.bookmarks.reversed() : store.bookmarks
  }
}

struct BookmarkRow: View {
  @EnvironmentObject private var store: AppModel
  let bookmark: Bookmark

  @State private var status: BookmarkStatus?

  var body: some View {
    NavigationLink {
      ThreadPage(board: bookmark.board ?? "", threadID: bookmark.no ?? 0, initialPost: nil, threadTitle: bookmark.sub ?? bookmark.com)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("No.\(bookmark.no ?? 0)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            if let status, status.status != .online {
              Text(status.status == .archived ? "Archived" : "Deleted")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.12), in: Capsule())
                .foregroundStyle(.red)
            }
          }

          let title = firstText(bookmark.sub, bookmark.com)
          if !title.isEmpty {
            Text(title)
              .font(.headline)
              .lineLimit(2)
          }
          let excerpt = bookmark.sub != nil ? firstText(bookmark.com) : ""
          if !excerpt.isEmpty {
            Text(excerpt)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(3)
          }
          RepliesSummaryView(replies: String(status?.replies ?? 0), images: String(status?.images ?? 0))
        }
        Spacer()
        if let image = bookmark.imageUrl, let board = bookmark.board, let tim = Int(image.replacingOccurrences(of: "s.jpg", with: "")) {
          AsyncRemoteImage(url: boardThumbnailURL(board: board, tim: tim), contentMode: .fill)
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }
      .padding(.vertical, 8)
    }
    .task {
      status = await store.fetchBookmarkStatus(bookmark)
    }
  }
}

// MARK: - Settings

struct SettingsRootView: View {
  @EnvironmentObject private var store: AppModel

  var body: some View {
    NavigationStack {
      List {
        Section {
          Link(destination: URL(string: "https://github.com/NekoSurf/NekoSurf")!) {
            HStack(spacing: 12) {
              Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
              VStack(alignment: .leading) {
                Text("NekoSurf")
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        Section("Threads") {
          Picker("Default board view", selection: Binding(
            get: { store.settings.boardViewMode },
            set: { store.setBoardViewMode($0) }
          )) {
            Text("Grid").tag(BoardViewMode.grid)
            Text("List").tag(BoardViewMode.list)
          }

          Picker("Default sort", selection: Binding(
            get: { store.settings.boardSort },
            set: { store.setBoardSort($0) }
          )) {
            ForEach(BoardSort.allCases, id: \.self) { sort in
              Text(sort.title).tag(sort)
            }
          }

          Picker("Sort direction", selection: Binding(
            get: { store.settings.boardSortDirection },
            set: { store.setBoardSortDirection($0) }
          )) {
            ForEach(SortDirection.allCases, id: \.self) { direction in
              Text(direction.title).tag(direction)
            }
          }

          Toggle("Auto-scroll to last seen", isOn: Binding(
            get: { store.settings.autoScrollToLastSeen },
            set: { store.setAutoScrollToLastSeen($0) }
          ))

          Stepper(value: Binding(
            get: { store.settings.watchedPostsRetentionDays },
            set: { store.setWatchedPostsRetentionDays(max(1, $0)) }
          ), in: 1...30) {
            Text("Watched posts retention: \(store.settings.watchedPostsRetentionDays) days")
          }
        }

        Section("Privacy") {
          Toggle("Show NSFW boards", isOn: Binding(
            get: { store.settings.allowNSFW },
            set: { store.setAllowNSFW($0) }
          ))
        }

        Section("Data") {
          HStack {
            Text("Cache size")
            Spacer()
            Text(store.savedCacheUsageDescription())
              .foregroundStyle(.secondary)
          }

          Button("Clear cache") {
            store.clearCache()
          }

          Button("Clear watched posts", role: .destructive) {
            store.clearWatchedPosts()
          }

          Button("Clear saved attachments", role: .destructive) {
            store.clearSavedAttachments()
          }

          Button("Clear bookmarks", role: .destructive) {
            store.clearBookmarks()
          }
        }
      }
      .navigationTitle("Settings")
      .listStyle(.insetGrouped)
    }
  }
}
