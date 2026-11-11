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
    switch method {
    case "available":
      return await available()
    case "start":
      try start()
      return nil
    case "stop":
      let delete = (arguments as? [String: Any])?["delete"] as? Bool ?? false
      if delete { try await deleteZone() }
      reset(keepingInbox: false)
      return nil
    case "deleteCloud":
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
      try await engineOrThrow().sendChanges()
      return nil
    case "flush":
      await flush()
      return nil
    case "takeInbox":
      return inbox.map(\.asMap)
    case "ackInbox":
      ack(upTo: arguments as? Int ?? -1)
      return nil
    case "status":
      return status()
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
    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
  }

  /// Adds what's in the outbox to what [engine] is to send, where it's not.
  private func requeueOutbox(_ engine: CKSyncEngine) {
    let pending = Set(engine.state.pendingRecordZoneChanges)
    let missing = outbox.keys.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID($0)) }
      .filter { !pending.contains($0) }
    engine.state.add(pendingRecordZoneChanges: missing)
  }

  /// Forgets everything about syncing on this device: the engine, what was
  /// waiting to go, and (unless [keepingInbox]) what came in.
  private func reset(keepingInbox: Bool) {
    engine = nil
    outbox = [:]
    inFlight = [:]
    serverRecords = [:]
    problem = nil
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
  }

  private func delete(_ ids: [String]) {
    guard let engine = try? engineOrThrow() else { return }
    for id in ids { outbox[id] = nil }
    persistOutbox()
    let recordIDs = ids.map(Self.recordID)
    engine.state.remove(pendingRecordZoneChanges: recordIDs.map { .saveRecord($0) })
    engine.state.add(pendingRecordZoneChanges: recordIDs.map { .deleteRecord($0) })
  }

  /// Sends what's waiting, with the time iOS gives an app that's just been
  /// left.
  private func flush() async {
    guard let engine, !engine.state.pendingRecordZoneChanges.isEmpty else { return }
    let task = await MainActor.run { BackgroundTask(named: "iCloud sync") }
    try? await engine.sendChanges()
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
      "pending": engine?.state.pendingRecordZoneChanges.count ?? 0,
    ]
    map["problem"] = problem
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
        // The engine starts over, dropping what it was to send: the zone,
        // and what's waiting, go again.
        syncEngine.state.add(
          pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        requeueOutbox(syncEngine)
        receive([Incoming(seq: 0, event: "signedIn")])
      case .signOut, .switchAccounts:
        reset(keepingInbox: true)
        receive([Incoming(seq: 0, event: "signedOut")])
      @unknown default:
        break
      }
    case .fetchedDatabaseChanges(let event):
      if event.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
        reset(keepingInbox: true)
        receive([Incoming(seq: 0, event: "zoneDeleted")])
      }
    case .fetchedRecordZoneChanges(let event):
      fetched(event, engine: syncEngine)
    case .sentRecordZoneChanges(let event):
      sent(event, engine: syncEngine)
    case .willFetchChanges, .willSendChanges:
      busy += 1
      sendStatus()
    case .didFetchChanges, .didSendChanges:
      busy = max(0, busy - 1)
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
    // A batch takes up to 250 of them: each record is built as it's taken,
    // not all that are waiting, for every batch.
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
      await self.batchRecord(for: recordID, engine: syncEngine)
    }
  }

  /// The record [recordID] is to be sent as; nil, and no longer waiting to
  /// go, if it's not to be sent any more.
  private func batchRecord(for recordID: CKRecord.ID, engine: CKSyncEngine) -> CKRecord? {
    if let record = record(for: recordID.recordName) { return record }
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
    receive(received)
  }

  private func sent(_ event: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
    var retry: [CKSyncEngine.PendingRecordZoneChange] = []
    var zones: [CKSyncEngine.PendingDatabaseChange] = []
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
    if !event.savedRecords.isEmpty, problem == "quotaExceeded" {
      problem = nil
    }
    for failure in event.failedRecordSaves {
      let recordID = failure.record.recordID
      let id = recordID.recordName
      inFlight[id] = nil
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
        // Kept in the outbox, and tried again from start().
        problem = "quotaExceeded"
      default:
        // The engine tries again by itself after network trouble.
        break
      }
    }
    for (recordID, _) in event.failedRecordDeletes {
      serverRecords[recordID.recordName] = nil
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
