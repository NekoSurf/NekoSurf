import CloudKit
import Flutter
import UIKit

/// iCloud sync (lib/sync/cloud_sync.dart): what's kept the same on every
/// device with it on, as one CloudKit record per item, in a zone of the
/// user's private database. CKSyncEngine sends and fetches them, and hears
/// of changes by push.
///
/// Dart says what changed here ("save", "delete"); what changed elsewhere
/// waits in an inbox on disk until Dart has applied it ("takeInbox",
/// "ackInbox"), so none of it is lost if the app is killed meanwhile.
enum CloudSyncChannel {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "nekosurf/cloudsync", binaryMessenger: registrar.messenger())
    let sync = CloudSync { method, arguments in
      DispatchQueue.main.async { channel.invokeMethod(method, arguments: arguments) }
    }
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments
      Task {
        let answer: Any?
        do {
          answer = try await sync.handle(call.method, arguments)
        } catch {
          answer = FlutterError(
            code: CloudSync.code(of: error), message: error.localizedDescription,
            details: nil)
        }
        DispatchQueue.main.async { result(answer) }
      }
    }
  }
}

/// A change made on this device, waiting to be sent.
private struct Outgoing: Codable {
  var kind: String
  var key: String
  var data: String
  var modifiedAt: Double
  var media: String?
  var thumbnail: String?
  var version: Int
}

/// A change made elsewhere (or something that happened to sync), waiting
/// for Dart.
private struct Incoming: Codable {
  var seq: Int
  var id: String?
  var deleted: Bool = false
  var kind: String?
  var key: String?
  var data: String?
  var modifiedAt: Double?
  var media: String?
  var thumbnail: String?
  /// "zoneDeleted", "signedOut" or "signedIn", instead of a change.
  var event: String?

  var asMap: [String: Any] {
    var map: [String: Any] = ["seq": seq, "deleted": deleted]
    map["id"] = id
    map["kind"] = kind
    map["key"] = key
    map["data"] = data
    map["modifiedAt"] = modifiedAt
    map["media"] = media
    map["thumbnail"] = thumbnail
    map["event"] = event
    return map
  }
}

struct NotEntitled: LocalizedError {
  var errorDescription: String? { "This build of NekoSurf can't use iCloud." }
}

/// Time iOS gives to finish sending once the app is left; ended when it's
/// done, or when that time's up, as iOS would otherwise end the app.
@MainActor
private final class BackgroundTask {
  private var id: UIBackgroundTaskIdentifier = .invalid

  init(named name: String) {
    id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      self?.end()
    }
  }

  func end() {
    guard id != .invalid else { return }
    UIApplication.shared.endBackgroundTask(id)
    id = .invalid
  }
}

final actor CloudSync: CKSyncEngineDelegate {
  static let containerID = "iCloud.com.wrngwrld.Chanyan"
  static let zoneID = CKRecordZone.ID(zoneName: "NekoSurf")
  static let recordType = "Item"

  private let notify: @Sendable (String, Any?) -> Void
  private var engine: CKSyncEngine?

  private var outbox: [String: Outgoing] = [:]
  private var inFlight: [String: Int] = [:]
  private var serverRecords: [String: Data] = [:]
  private var inbox: [Incoming] = []
  private var nextVersion = 0

  private var busy = 0
  private var problem: String?
  /// What iCloud said, when it took a change from here but wouldn't save
  /// it (problem "failed"), and which changes those are, till they're
  /// saved or no longer to be.
  private var lastError: String?
  private var refusedIDs = Set<String>()

  init(notify: @escaping @Sendable (String, Any?) -> Void) {
    self.notify = notify
  }

  /// Whether this build is signed to use the iCloud container: App Store
  /// and TestFlight builds are; sideloaded ones, re-signed with a profile
  /// of their own, aren't, and CloudKit would crash the app there.
  static let entitled: Bool = {
    guard
      let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
    else { return true }
    guard let data = try? Data(contentsOf: url),
      let text = String(data: data, encoding: .isoLatin1),
      let start = text.range(of: "<?xml"),
      let end = text.range(of: "</plist>")
    else { return false }
    let xml = Data(text[start.lowerBound..<end.upperBound].utf8)
    guard
      let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil)
        as? [String: Any],
      let entitlements = plist["Entitlements"] as? [String: Any]
    else { return false }
    func list(_ key: String) -> [String] {
      if let many = entitlements[key] as? [String] { return many }
      if let one = entitlements[key] as? String { return [one] }
      return []
    }
    let services = list("com.apple.developer.icloud-services")
    let containers = list("com.apple.developer.icloud-container-identifiers")
    return (services.contains("CloudKit") || services.contains("*"))
      && (containers.contains(containerID) || containers.contains("*"))
  }()

  private lazy var container = CKContainer(identifier: Self.containerID)

  /// Errors CKSyncEngine sends the change again after, by itself.
  static func retriedByEngine(_ code: CKError.Code) -> Bool {
    switch code {
    case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited,
      .zoneBusy, .notAuthenticated, .operationCancelled, .accountTemporarilyUnavailable:
      return true
    default:
      return false
    }
  }

  static func code(of error: Error) -> String {
    if error is NotEntitled { return "notEntitled" }
    switch (error as? CKError)?.code {
    case .notAuthenticated: return "noAccount"
    case .quotaExceeded: return "quotaExceeded"
    case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited,
      .zoneBusy:
      return "offline"
    default: return "failed"
    }
  }

  // MARK: Calls from Dart

  func handle(_ method: String, _ arguments: Any?) async throws -> Any? {
    do {
      return try await perform(method, arguments)
    } catch {
      log("\(method) failed: \(Self.describe(error))")
      throw error
    }
  }

  private func perform(_ method: String, _ arguments: Any?) async throws -> Any? {
    switch method {
    case "available":
      return await available()
    case "start":
      try start()
      return nil
    case "stop":
      let delete = (arguments as? [String: Any])?["delete"] as? Bool ?? false
      log(delete ? "Turned off, deleting NekoSurf's data from iCloud" : "Turned off")
      if delete { try await deleteZone() }
      reset(keepingInbox: false)
      return nil
    case "deleteCloud":
      log("Deleting NekoSurf's data from iCloud")
      try await deleteZone()
      return nil
    case "hasCloudData":
      return await hasCloudData()
    case "save":
      save(arguments as? [[String: Any]] ?? [])
      return nil
    case "delete":
      delete(arguments as? [String] ?? [])
      return nil
    case "fetch":
      try await engineOrThrow().fetchChanges()
      return nil
    case "send":
      // What failed before goes again too ("Sync now").
      let engine = try engineOrThrow()
      requeueOutbox(engine)
      log("Sync now: \(waitingSummary(engine))")
      try await engine.sendChanges()
      return nil
    case "flush":
      await flush()
      return nil
    case "takeInbox":
      return inbox.map(\.asMap)
    case "ackInbox":
      let seq = arguments as? Int ?? -1
      let applied = inbox.filter { $0.seq <= seq }.count
      ack(upTo: seq)
      if applied > 0 { log("Applied \(applied) from elsewhere") }
      return nil
    case "status":
      return status()
    case "log":
      return logText()
    default:
      return FlutterMethodNotImplemented
    }
  }

  private func available() async -> [String: Any] {
    guard Self.entitled else { return ["entitled": false, "account": "none"] }
    let account: String
    switch try? await container.accountStatus() {
    case .available: account = "available"
    case .noAccount: account = "noAccount"
    case .restricted: account = "restricted"
    case .temporarilyUnavailable: account = "temporarilyUnavailable"
    default: account = "unknown"
    }
    return ["entitled": true, "account": account]
  }

  private func engineOrThrow() throws -> CKSyncEngine {
    if let engine { return engine }
    try start()
    return engine!
  }

  private func start() throws {
    guard Self.entitled else { throw NotEntitled() }
    if engine != nil { return }
    load()
    var state: CKSyncEngine.State.Serialization?
    if let data = try? Data(contentsOf: Self.file("state.json")) {
      state = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }
    let engine = CKSyncEngine(
      CKSyncEngine.Configuration(
        database: container.privateCloudDatabase, stateSerialization: state, delegate: self))
    self.engine = engine
    if state == nil {
      engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
    }
    // Whatever's waiting to go, in case it was dropped (see sent).
    requeueOutbox(engine)
    log("Started, \(state == nil ? "new" : "from saved state"); \(waitingSummary(engine))")
    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
  }

  /// Adds what's in the outbox to what [engine] is to send, where it's not,
  /// and isn't on its way already.
  private func requeueOutbox(_ engine: CKSyncEngine) {
    let pending = Set(engine.state.pendingRecordZoneChanges)
    let missing = outbox.keys.filter { inFlight[$0] == nil }
      .map { CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID($0)) }
      .filter { !pending.contains($0) }
    engine.state.add(pendingRecordZoneChanges: missing)
  }

  /// Forgets everything about syncing on this device: the engine, what was
  /// waiting to go, and (unless [keepingInbox]) what came in.
  private func reset(keepingInbox: Bool) {
    log("Reset: \(outbox.count) waiting to go dropped")
    engine = nil
    // The old engine's events are ignored from now, its "did" ones too.
    busy = 0
    outbox = [:]
    inFlight = [:]
    serverRecords = [:]
    problem = nil
    lastError = nil
    refusedIDs = []
    for name in ["state.json", "outbox.json", "records.plist"] {
      try? FileManager.default.removeItem(at: Self.file(name))
    }
    if !keepingInbox {
      inbox = []
      try? FileManager.default.removeItem(at: Self.file("inbox.json"))
      try? FileManager.default.removeItem(at: Self.file("incoming"))
    }
    sendStatus()
  }

  private func deleteZone() async throws {
    guard Self.entitled else { throw NotEntitled() }
    do {
      _ = try await container.privateCloudDatabase.deleteRecordZone(withID: Self.zoneID)
    } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
      // Nothing there.
    }
  }

  private func hasCloudData() async -> Bool? {
    guard Self.entitled else { return false }
    do {
      _ = try await container.privateCloudDatabase.recordZone(for: Self.zoneID)
      return true
    } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
      return false
    } catch {
      return nil
    }
  }

  private func save(_ items: [[String: Any]]) {
    guard let engine = try? engineOrThrow() else { return }
    var changes: [CKSyncEngine.PendingRecordZoneChange] = []
    for item in items {
      guard let id = item["id"] as? String, let kind = item["kind"] as? String,
        let key = item["key"] as? String, let data = item["data"] as? String
      else { continue }
      nextVersion += 1
      outbox[id] = Outgoing(
        kind: kind, key: key, data: data,
        modifiedAt: (item["modifiedAt"] as? NSNumber)?.doubleValue
          ?? Date().timeIntervalSince1970 * 1000,
        media: item["media"] as? String, thumbnail: item["thumbnail"] as? String,
        version: nextVersion)
      changes.append(.saveRecord(Self.recordID(id)))
    }
    persistOutbox()
    engine.state.add(pendingRecordZoneChanges: changes)
    log("Changed here: \(Self.kinds(items.compactMap { $0["id"] as? String }))")
    sendStatus()
  }

  private func delete(_ ids: [String]) {
    guard let engine = try? engineOrThrow() else { return }
    for id in ids { outbox[id] = nil }
    persistOutbox()
    let recordIDs = ids.map(Self.recordID)
    engine.state.remove(pendingRecordZoneChanges: recordIDs.map { .saveRecord($0) })
    engine.state.add(pendingRecordZoneChanges: recordIDs.map { .deleteRecord($0) })
    log("Removed here: \(Self.kinds(ids))")
    sendStatus()
  }

  /// Sends what's waiting, with the time iOS gives an app that's just been
  /// left.
  private func flush() async {
    guard let engine, !engine.state.pendingRecordZoneChanges.isEmpty else { return }
    let task = await MainActor.run { BackgroundTask(named: "iCloud sync") }
    log("App left: sending what's waiting; \(waitingSummary(engine))")
    do {
      try await engine.sendChanges()
    } catch {
      log("Sending on leaving stopped: \(Self.describe(error))")
    }
    await MainActor.run { task.end() }
  }

  private func ack(upTo seq: Int) {
    let done = inbox.filter { $0.seq <= seq }
    inbox.removeAll { $0.seq <= seq }
    persistInbox()
    // What Dart didn't move into place isn't needed any more.
    for item in done {
      for path in [item.media, item.thumbnail].compactMap({ $0 }) {
        try? FileManager.default.removeItem(atPath: path)
      }
    }
  }

  private func status() -> [String: Any] {
    var map: [String: Any] = [
      "syncing": busy > 0,
      // What changed here and iCloud hasn't confirmed yet: the outbox, as
      // the engine drops what failed and start() or "send" adds it back.
      "pending": outbox.count,
      "pendingMedia": outbox.values.filter { $0.media != nil }.count,
    ]
    map["problem"] = problem
    map["error"] = lastError
    let last = UserDefaults.standard.double(forKey: "cloudSync.lastSynced")
    if last > 0 { map["lastSynced"] = last }
    return map
  }

  private func sendStatus() {
    notify("status", status())
  }

  // MARK: CKSyncEngineDelegate

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard syncEngine === engine else { return }
    switch event {
    case .stateUpdate(let event):
      if let data = try? JSONEncoder().encode(event.stateSerialization) {
        try? data.write(to: Self.file("state.json"), options: .atomic)
      }
    case .accountChange(let event):
      switch event.changeType {
      case .signIn:
        log("Account: signed in")
        // The engine starts over, dropping what it was to send: the zone,
        // and what's waiting, go again.
        syncEngine.state.add(
          pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        requeueOutbox(syncEngine)
        receive([Incoming(seq: 0, event: "signedIn")])
      case .signOut, .switchAccounts:
        log("Account: signed out or switched")
        reset(keepingInbox: true)
        receive([Incoming(seq: 0, event: "signedOut")])
      @unknown default:
        break
      }
    case .fetchedDatabaseChanges(let event):
      if !event.modifications.isEmpty || !event.deletions.isEmpty {
        log("Zones changed: \(event.modifications.count), deleted: \(event.deletions.count)")
      }
      if event.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
        reset(keepingInbox: true)
        receive([Incoming(seq: 0, event: "zoneDeleted")])
      }
    case .fetchedRecordZoneChanges(let event):
      fetched(event, engine: syncEngine)
    case .sentRecordZoneChanges(let event):
      sent(event, engine: syncEngine)
    case .sentDatabaseChanges(let event):
      for zone in event.savedZones { log("Zone saved: \(zone.zoneID.zoneName)") }
      for failure in event.failedZoneSaves {
        log("Zone save failed: \(Self.describe(failure.error))")
      }
    case .willFetchChanges, .willSendChanges:
      busy += 1
      if case .willSendChanges = event, let engine {
        log("Sending; \(waitingSummary(engine))")
      }
      sendStatus()
    case .didFetchChanges, .didSendChanges:
      busy = max(0, busy - 1)
      if case .didSendChanges = event { log("Sending done; \(outbox.count) not in iCloud yet") }
      UserDefaults.standard.set(
        Date().timeIntervalSince1970 * 1000, forKey: "cloudSync.lastSynced")
      sendStatus()
    default:
      break
    }
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let changes = syncEngine.state.pendingRecordZoneChanges.filter {
      context.options.scope.contains($0)
    }
    // A batch's records are saved once all its files are up, so the small
    // changes (a bookmark, a setting) go first, on their own; then saved
    // files, a few at a time, so each is in iCloud as soon as it's up.
    let small = changes.filter { mediaPath(of: $0) == nil }
    let batch = small.isEmpty ? mediaBatch(changes) : small
    if !batch.isEmpty {
      log(
        small.isEmpty
          ? "Batch: \(batch.count) saved file(s), \(Self.megabytes(batch.compactMap(mediaPath(of:)))) (\(changes.count) waiting)"
          : "Batch: up to 250 of \(small.count) change(s) without a file (\(changes.count) waiting)")
    }
    // A batch takes up to 250 of them: each record is built as it's taken,
    // not all that are waiting, for every batch.
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batch) { recordID in
      await self.batchRecord(for: recordID, engine: syncEngine)
    }
  }

  /// Bytes of saved files to send in one batch: at least one file, more
  /// only while they come to this together.
  private static let mediaBatchBytes: Int64 = 20 * 1024 * 1024

  /// The saved file [change] sends, if it sends one.
  private func mediaPath(of change: CKSyncEngine.PendingRecordZoneChange) -> String? {
    guard case .saveRecord(let recordID) = change else { return nil }
    return outbox[recordID.recordName]?.media
  }

  /// The first of [changes] (all with a saved file), up to mediaBatchBytes.
  private func mediaBatch(
    _ changes: [CKSyncEngine.PendingRecordZoneChange]
  ) -> [CKSyncEngine.PendingRecordZoneChange] {
    var batch: [CKSyncEngine.PendingRecordZoneChange] = []
    var bytes: Int64 = 0
    for change in changes {
      let path = mediaPath(of: change) ?? ""
      let size =
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
        .int64Value ?? 0
      if !batch.isEmpty && bytes + size > Self.mediaBatchBytes { break }
      batch.append(change)
      bytes += size
    }
    return batch
  }

  /// The record [recordID] is to be sent as; nil, and no longer waiting to
  /// go, if it's not to be sent any more.
  private func batchRecord(for recordID: CKRecord.ID, engine: CKSyncEngine) -> CKRecord? {
    if let record = record(for: recordID.recordName) { return record }
    log("Not sent, no longer to be: \(Self.tag(recordID.recordName))")
    engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
    return nil
  }

  /// The record [id] is to be sent as, or nil if it's no longer to be sent
  /// (it's not saved here any more, or its saved file is gone).
  private func record(for id: String) -> CKRecord? {
    guard let item = outbox[id] else { return nil }
    let fileManager = FileManager.default
    if let media = item.media, !fileManager.fileExists(atPath: media) {
      outbox[id] = nil
      persistOutbox()
      return nil
    }
    let record =
      serverRecords[id].flatMap(Self.decodeRecord)
      ?? CKRecord(recordType: Self.recordType, recordID: Self.recordID(id))
    record["kind"] = item.kind
    record["key"] = item.key
    record["data"] = item.data
    record["modifiedAt"] = Date(timeIntervalSince1970: item.modifiedAt / 1000)
    record["media"] = item.media.map { CKAsset(fileURL: URL(fileURLWithPath: $0)) }
    record["thumbnail"] = item.thumbnail.flatMap {
      fileManager.fileExists(atPath: $0) ? CKAsset(fileURL: URL(fileURLWithPath: $0)) : nil
    }
    inFlight[id] = item.version
    return record
  }

  private func fetched(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges, engine: CKSyncEngine) {
    // What's changed here and not sent yet wins over what came in.
    let pending = Set(
      engine.state.pendingRecordZoneChanges.map { change -> String in
        switch change {
        case .saveRecord(let id), .deleteRecord(let id): return id.recordName
        @unknown default: return ""
        }
      })
    var received: [Incoming] = []
    for modification in event.modifications {
      let record = modification.record
      let id = record.recordID.recordName
      serverRecords[id] = Self.encodeSystemFields(record)
      if pending.contains(id) { continue }
      received.append(
        Incoming(
          seq: 0, id: id, kind: record["kind"] as? String, key: record["key"] as? String,
          data: record["data"] as? String,
          modifiedAt: (record["modifiedAt"] as? Date).map { $0.timeIntervalSince1970 * 1000 },
          media: Self.keep(record["media"] as? CKAsset),
          thumbnail: Self.keep(record["thumbnail"] as? CKAsset)))
    }
    for deletion in event.deletions {
      let id = deletion.recordID.recordName
      serverRecords[id] = nil
      if pending.contains(id) { continue }
      received.append(Incoming(seq: 0, id: id, deleted: true))
    }
    persistRecords()
    let skipped = event.modifications.count + event.deletions.count - received.count
    log(
      "Fetched: \(event.modifications.count) changed, \(event.deletions.count) deleted"
        + (skipped > 0 ? ", \(skipped) changed here since, kept" : "")
        + (received.isEmpty ? "" : "; \(Self.kinds(received.compactMap(\.id)))"))
    receive(received)
  }

  private func sent(_ event: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
    var retry: [CKSyncEngine.PendingRecordZoneChange] = []
    var zones: [CKSyncEngine.PendingDatabaseChange] = []
    if !event.savedRecords.isEmpty {
      log("Saved in iCloud: \(Self.kinds(event.savedRecords.map(\.recordID.recordName)))")
    }
    if !event.deletedRecordIDs.isEmpty {
      log("Deleted in iCloud: \(Self.kinds(event.deletedRecordIDs.map(\.recordName)))")
    }
    for record in event.savedRecords {
      let id = record.recordID.recordName
      serverRecords[id] = Self.encodeSystemFields(record)
      // Changed again while it was on its way: that goes too.
      if let sentVersion = inFlight.removeValue(forKey: id), outbox[id]?.version == sentVersion {
        outbox[id] = nil
      } else if outbox[id] != nil {
        retry.append(.saveRecord(record.recordID))
      }
    }
    var refused: CKError?
    var full = false
    for failure in event.failedRecordSaves {
      let recordID = failure.record.recordID
      let id = recordID.recordName
      inFlight[id] = nil
      log("Not saved: \(Self.tag(id)): \(Self.describe(failure.error))")
      switch failure.error.code {
      case .serverRecordChanged:
        // Changed elsewhere since: what changed here is newer.
        if let server = failure.error.serverRecord {
          serverRecords[id] = Self.encodeSystemFields(server)
        }
        retry.append(.saveRecord(recordID))
      case .zoneNotFound:
        zones.append(.saveZone(CKRecordZone(zoneID: recordID.zoneID)))
        serverRecords[id] = nil
        retry.append(.saveRecord(recordID))
      case .unknownItem:
        serverRecords[id] = nil
        retry.append(.saveRecord(recordID))
      case .quotaExceeded:
        // Kept in the outbox, and tried again from start() or "send".
        full = true
      case let code where Self.retriedByEngine(code):
        break
      default:
        // Kept in the outbox too; said, not dropped.
        refused = failure.error
        refusedIDs.insert(id)
      }
    }
    for (recordID, error) in event.failedRecordDeletes {
      log("Not deleted: \(Self.tag(recordID.recordName)): \(Self.describe(error))")
      serverRecords[recordID.recordName] = nil
      if !Self.retriedByEngine(error.code) { refused = error }
    }
    if let refused {
      lastError = "\(refused.localizedDescription) (CloudKit error \(refused.code.rawValue))"
    }
    // Refused ones that were saved since, or are no longer to be.
    refusedIDs = refusedIDs.filter { outbox[$0] != nil }
    if refused == nil, refusedIDs.isEmpty {
      lastError = nil
    }
    if refused != nil || !refusedIDs.isEmpty {
      problem = "failed"
    } else if full {
      problem = "quotaExceeded"
    } else if problem == "failed" || (problem == "quotaExceeded" && !event.savedRecords.isEmpty) {
      problem = nil
    }
    for recordID in event.deletedRecordIDs {
      serverRecords[recordID.recordName] = nil
    }
    persistOutbox()
    persistRecords()
    engine.state.add(pendingDatabaseChanges: zones)
    engine.state.add(pendingRecordZoneChanges: retry)
    sendStatus()
  }

  // MARK: Log

  /// What sync did lately, for the Sync log in Settings: kinds, counts and
  /// errors, each item as its kind and a short code, never what it is.
  private var logLines: [String]?
  private static let logLimit = 400
  private static let timeStyle = Date.ISO8601FormatStyle(
    includingFractionalSeconds: true, timeZone: .current)

  private func log(_ message: String) {
    var lines = logLines ?? Self.loadLog()
    lines.append("\(Self.timeStyle.format(Date())) \(message)")
    if lines.count > Self.logLimit { lines.removeFirst(lines.count - Self.logLimit) }
    logLines = lines
    try? lines.joined(separator: "\n").write(
      to: Self.file("log.txt"), atomically: true, encoding: .utf8)
  }

  private static func loadLog() -> [String] {
    guard let text = try? String(contentsOf: file("log.txt"), encoding: .utf8) else { return [] }
    return text.split(separator: "\n").map(String.init)
  }

  /// The log, after how things stand now.
  private func logText() -> String {
    load()
    var head = [
      "NekoSurf iCloud sync log, \(Self.timeStyle.format(Date()))",
      "Signed for iCloud: \(Self.entitled ? "yes" : "no")",
      engine.map { "Engine: running; \(waitingSummary($0))" }
        ?? "Engine: not running; \(outbox.count) not in iCloud yet",
      "Running sends and fetches: \(busy)",
      "Waiting to be applied here: \(inbox.count)",
    ]
    if let problem { head.append("Problem: \(problem)") }
    if let lastError { head.append("iCloud said: \(lastError)") }
    if !refusedIDs.isEmpty { head.append("Refused: \(Self.kinds(Array(refusedIDs)))") }
    return (head + ["", "Newest last:"] + (logLines ?? Self.loadLog())).joined(separator: "\n")
  }

  /// What's waiting to go, as the outbox and [engine] each see it.
  private func waitingSummary(_ engine: CKSyncEngine) -> String {
    var saves = 0
    var deletes = 0
    for change in engine.state.pendingRecordZoneChanges {
      if case .saveRecord = change { saves += 1 } else { deletes += 1 }
    }
    let files = outbox.values.filter { $0.media != nil }.count
    return "\(outbox.count) not in iCloud yet (\(files) with a file); engine to send: "
      + "\(saves) save(s), \(deletes) delete(s), "
      + "\(engine.state.pendingDatabaseChanges.count) zone change(s); on the way: \(inFlight.count)"
  }

  static func describe(_ error: Error) -> String {
    if let error = error as? CKError {
      return "CloudKit error \(error.code.rawValue): \(error.localizedDescription)"
    }
    return "\(error.localizedDescription)"
  }

  /// [id]'s kind and a short code for it, the same each time.
  static func tag(_ id: String) -> String {
    var hash: UInt32 = 2_166_136_261
    for byte in id.utf8 {
      hash = (hash ^ UInt32(byte)) &* 16_777_619
    }
    return "\(kind(of: id))#\(String(format: "%06x", hash & 0xFFFFFF))"
  }

  private static func kind(of id: String) -> String {
    String(id.prefix { $0 != "." && $0 != ":" })
  }

  /// How many of each kind [ids] are, as "2 saved, 1 bookmark".
  static func kinds(_ ids: [String]) -> String {
    var counts: [String: Int] = [:]
    for id in ids { counts[kind(of: id), default: 0] += 1 }
    if counts.isEmpty { return "nothing" }
    return counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
      .joined(separator: ", ")
  }

  static func megabytes(_ paths: [String]) -> String {
    let bytes = paths.reduce(Int64(0)) { sum, path in
      sum
        + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
          .int64Value ?? 0)
    }
    return String(format: "%.1f MB", Double(bytes) / 1_048_576)
  }

  // MARK: Storage

  private func receive(_ items: [Incoming]) {
    if items.isEmpty { return }
    var seq = (inbox.last?.seq ?? UserDefaults.standard.integer(forKey: "cloudSync.seq"))
    for var item in items {
      seq += 1
      item.seq = seq
      inbox.append(item)
    }
    UserDefaults.standard.set(seq, forKey: "cloudSync.seq")
    persistInbox()
    notify("inbox", nil)
  }

  /// A copy of [asset]'s file, which CloudKit may clear out of its cache.
  private static func keep(_ asset: CKAsset?) -> String? {
    guard let url = asset?.fileURL else { return nil }
    let folder = file("incoming")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let copy = folder.appendingPathComponent(UUID().uuidString)
    do {
      try FileManager.default.copyItem(at: url, to: copy)
      return copy.path
    } catch {
      return nil
    }
  }

  private var loaded = false

  private func load() {
    if loaded { return }
    loaded = true
    let decoder = JSONDecoder()
    if let data = try? Data(contentsOf: Self.file("outbox.json")) {
      outbox = (try? decoder.decode([String: Outgoing].self, from: data)) ?? [:]
      nextVersion = outbox.values.map(\.version).max() ?? 0
    }
    if let data = try? Data(contentsOf: Self.file("inbox.json")) {
      inbox = (try? decoder.decode([Incoming].self, from: data)) ?? []
    }
    if let data = try? Data(contentsOf: Self.file("records.plist")) {
      serverRecords =
        (try? PropertyListDecoder().decode([String: Data].self, from: data)) ?? [:]
    }
  }

  private func persistOutbox() {
    if let data = try? JSONEncoder().encode(outbox) {
      try? data.write(to: Self.file("outbox.json"), options: .atomic)
    }
  }

  private func persistInbox() {
    if let data = try? JSONEncoder().encode(inbox) {
      try? data.write(to: Self.file("inbox.json"), options: .atomic)
    }
  }

  private func persistRecords() {
    if let data = try? PropertyListEncoder().encode(serverRecords) {
      try? data.write(to: Self.file("records.plist"), options: .atomic)
    }
  }

  private static let folder: URL = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let folder = support.appendingPathComponent("CloudSync", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }()

  private static func file(_ name: String) -> URL {
    folder.appendingPathComponent(name)
  }

  private static func recordID(_ id: String) -> CKRecord.ID {
    CKRecord.ID(recordName: id, zoneID: zoneID)
  }

  private static func encodeSystemFields(_ record: CKRecord) -> Data {
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: coder)
    coder.finishEncoding()
    return coder.encodedData
  }

  private static func decodeRecord(_ data: Data) -> CKRecord? {
    guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
    coder.requiresSecureCoding = true
    defer { coder.finishDecoding() }
    return CKRecord(coder: coder)
  }
}
