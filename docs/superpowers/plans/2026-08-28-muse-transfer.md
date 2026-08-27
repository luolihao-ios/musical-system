# 暮色互传 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建可在同一局域网内发现、人工确认并安全互传任意文件的 Windows 与 iOS 原生应用，并为音乐内容提供导入暮色音乐的入口。

**Architecture:** 先用版本化协议规范和跨语言测试向量锁定互操作边界，再分别实现 C#/WPF 与 Swift/SwiftUI 客户端。两端采用 mDNS 发现、HTTPS 控制与分块上传、临时目录提交、SHA-256 校验；音乐交接作为传输成功后的显式操作，不侵入播放器数据库。

**Tech Stack:** C# 14、.NET 10、WPF、ASP.NET Core/Kestrel、xUnit、Swift 6、SwiftUI、Network.framework、CryptoKit、XCTest、Bonjour/mDNS、JSON、HTTPS、SHA-256。

**Spec:** `docs/superpowers/specs/2026-08-28-muse-transfer-design.md`

## Global Constraints

- Windows 支持 Windows 10/11 x64，使用 C#、WPF 和 .NET 10。
- iOS 最低支持 iOS 17，使用 Swift 和 SwiftUI。
- 只支持暮色互传 Windows/iOS 客户端互通，不兼容 LocalSend。
- 每批接收都必须由用户确认；不得实现可信设备自动接收。
- 无账号、云存储、互联网中继或 NAT 穿透，断开互联网后仍可使用。
- 接收任意文件；音乐增强只识别和交接，不改变原始目录结构。
- 文件数据不得整体载入内存；最终文件必须在 SHA-256 校验成功后提交。
- iOS 被系统完全挂起后不承诺持续接收。
- 不使用 LocalSend 的名称、图标、文案或素材。

---

## Planned File Map

```text
docs/transfer-protocol/
  v1.md                         # 协议线格式、状态码和安全约束
  vectors/manifest-v1.json      # 两端共享的规范化与摘要测试向量

transfer-windows/
  MuseTransfer.slnx
  src/MuseTransfer.Protocol/    # 纯协议模型、规范化、摘要
  src/MuseTransfer.Core/        # 会话、分块、文件提交、音乐归组
  src/MuseTransfer.App/         # WPF、Kestrel、mDNS、组合根
  tests/MuseTransfer.Tests/     # xUnit 协议、核心与 ViewModel 测试
  scripts/verify.ps1

transfer-ios/
  project.yml                   # XcodeGen 工程定义
  MuseTransfer/
    Protocol/                   # Codable 协议类型和测试向量实现
    Transfer/                   # NWListener/NWConnection、会话和文件写入
    Discovery/                  # NWBrowser Bonjour 发现
    Music/                      # 音乐归组与暮色音乐交接
    Features/                   # SwiftUI 页面与模型
    App/                        # 应用入口和依赖组装
  MuseTransferTests/
  scripts/verify.sh
```

## Task 1: Freeze Protocol v1 and Cross-Language Vectors

**Files:**
- Create: `docs/transfer-protocol/v1.md`
- Create: `docs/transfer-protocol/vectors/manifest-v1.json`
- Create: `transfer-windows/src/MuseTransfer.Protocol/MuseTransfer.Protocol.csproj`
- Create: `transfer-windows/src/MuseTransfer.Protocol/TransferManifest.cs`
- Create: `transfer-windows/src/MuseTransfer.Protocol/ManifestCanonicalizer.cs`
- Create: `transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj`
- Create: `transfer-windows/tests/MuseTransfer.Tests/Protocol/ManifestVectorTests.cs`
- Create: `transfer-windows/MuseTransfer.slnx`

**Interfaces:**
- Produces: `TransferManifest`, `TransferItem`, `MusicGroup`, `ManifestCanonicalizer.Canonicalize(TransferManifest)`, `ManifestCanonicalizer.ComputeSha256(TransferManifest)`.
- Produces wire endpoints: `POST /v1/sessions`, `POST /v1/sessions/{id}/decision`, `PUT /v1/sessions/{id}/files/{fileId}/chunks/{index}`, `POST /v1/sessions/{id}/complete`, `GET /v1/sessions/{id}`.

- [ ] **Step 1: Write the canonicalization vector and failing xUnit test**

Use this vector shape and exact canonical field order:

```json
{
  "manifest": {
    "protocolVersion": 1,
    "senderId": "sender-a",
    "items": [
      {"id":"f1","relativePath":"Album/song.mp3","size":3,"sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}
    ],
    "musicGroups": []
  },
  "canonicalUtf8": "{\"protocolVersion\":1,\"senderId\":\"sender-a\",\"items\":[{\"id\":\"f1\",\"relativePath\":\"Album/song.mp3\",\"size\":3,\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}],\"musicGroups\":[]}",
  "canonicalSha256": "7990c2d1e1d48a2c724041fd490a3d23df966a589b5000dc48c993a6197ef7d6"
}
```

The test must load the repository vector, deserialize it, assert byte-for-byte canonical UTF-8 equality, then assert the canonical SHA-256.

- [ ] **Step 2: Run the focused test and verify the missing protocol types fail compilation**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj --filter ManifestVectorTests`

Expected: FAIL because `TransferManifest` and `ManifestCanonicalizer` do not exist.

- [ ] **Step 3: Implement immutable protocol records and deterministic JSON writing**

Use `Utf8JsonWriter`; write properties explicitly in the vector order, preserve item array order, emit UTF-8 without indentation, and reject protocol versions other than `1`. Do not use dictionary enumeration for canonical output.

```csharp
public sealed record TransferItem(string Id, string RelativePath, long Size, string Sha256);
public sealed record MusicGroup(string Id, IReadOnlyList<string> ItemIds);
public sealed record TransferManifest(int ProtocolVersion, string SenderId,
    IReadOnlyList<TransferItem> Items, IReadOnlyList<MusicGroup> MusicGroups);

public static class ManifestCanonicalizer
{
    public static byte[] Canonicalize(TransferManifest manifest);
    public static string ComputeSha256(TransferManifest manifest);
}
```

Document request/response JSON, status lifecycle (`pending`, `accepted`, `rejected`, `transferring`, `completed`, `failed`, `cancelled`), `X-Muse-Session-Token`, maximum default limits, chunk `Content-Range`, and error envelope `{ "code": "...", "message": "..." }` in `v1.md`.

- [ ] **Step 4: Run protocol tests and repository formatting checks**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj --filter ManifestVectorTests`

Expected: PASS.

- [ ] **Step 5: Commit the protocol baseline**

```powershell
git add docs/transfer-protocol transfer-windows/MuseTransfer.slnx transfer-windows/src/MuseTransfer.Protocol transfer-windows/tests/MuseTransfer.Tests
git commit -m "feat: define muse transfer protocol v1"
```

## Task 2: Secure Paths, Duplicate Names, and Atomic File Commit

**Files:**
- Create: `transfer-windows/src/MuseTransfer.Core/MuseTransfer.Core.csproj`
- Create: `transfer-windows/src/MuseTransfer.Core/Files/SafeRelativePath.cs`
- Create: `transfer-windows/src/MuseTransfer.Core/Files/DuplicateNameResolver.cs`
- Create: `transfer-windows/src/MuseTransfer.Core/Files/IncomingFileStore.cs`
- Create: `transfer-windows/tests/MuseTransfer.Tests/Files/IncomingFileStoreTests.cs`
- Modify: `transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj`

**Interfaces:**
- Consumes: `TransferItem` from Task 1.
- Produces: `SafeRelativePath.Parse(string)`, `DuplicateNameResolver.Resolve(string)`, `IncomingFileStore.OpenChunkAsync(...)`, `IncomingFileStore.CommitAsync(...)`.

- [ ] **Step 1: Write failing tests for traversal, duplicate names, streaming, and failed hashes**

Cover `../song.mp3`, `/root/song.mp3`, `C:\\song.mp3`, reserved Windows names, and normalized separators. Pre-create `song.mp3` and assert the resolver chooses `song (2).mp3`. Write a 2 MiB fixture in 256 KiB chunks, assert the temporary file is outside the final tree, and assert a wrong hash never creates the final file.

```csharp
await Assert.ThrowsAsync<UnsafePathException>(() => store.BeginAsync(item with { RelativePath = "../escape.mp3" }, ct));
Assert.Equal("song (2).mp3", resolver.Resolve("song.mp3"));
Assert.False(File.Exists(finalPathAfterBadHash));
```

- [ ] **Step 2: Run file-store tests and verify they fail**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj --filter IncomingFileStoreTests`

Expected: FAIL because the file-store classes do not exist.

- [ ] **Step 3: Implement safe path parsing and atomic commit**

`SafeRelativePath` must normalize `/`, reject rooted and empty paths, reject `.`/`..` segments and Windows device names, then confirm `Path.GetFullPath(candidate)` remains below `Path.GetFullPath(root)`. `IncomingFileStore` writes random-named `.part` files under an application temp root, records completed chunk indexes, flushes before hash calculation, and calls `File.Move(temp, final, overwrite: false)` only after size and SHA-256 match.

```csharp
public Task<ChunkWriteResult> WriteChunkAsync(string sessionId, TransferItem item,
    int chunkIndex, long offset, Stream content, CancellationToken cancellationToken);
public Task<CommittedFile> CommitAsync(string sessionId, TransferItem item,
    string destinationRoot, CancellationToken cancellationToken);
```

- [ ] **Step 4: Run all protocol and file tests**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj`

Expected: PASS with no temporary final files after failure cases.

- [ ] **Step 5: Commit file safety**

```powershell
git add transfer-windows/src/MuseTransfer.Core transfer-windows/tests/MuseTransfer.Tests
git commit -m "feat: add safe incoming file storage"
```

## Task 3: Session Approval, Expiry, Limits, and Resume State

**Files:**
- Create: `transfer-windows/src/MuseTransfer.Core/Sessions/TransferSession.cs`
- Create: `transfer-windows/src/MuseTransfer.Core/Sessions/SessionManager.cs`
- Create: `transfer-windows/src/MuseTransfer.Core/Sessions/SessionTokenService.cs`
- Create: `transfer-windows/tests/MuseTransfer.Tests/Sessions/SessionManagerTests.cs`

**Interfaces:**
- Consumes: manifest digest from Task 1 and file chunk status from Task 2.
- Produces: `SessionManager.Propose`, `Accept`, `Reject`, `Cancel`, `AuthorizeChunk`, `GetResumeMap`; `SessionTokenService.Issue` and `Validate`.

- [ ] **Step 1: Write state-machine tests with a fake clock**

Assert that pending sessions reject chunks, rejected sessions can never be accepted, accepted sessions issue a token bound to sender ID and manifest digest, a token expires after five minutes, application restart does not restore tokens, and resume maps contain only chunks already persisted and verified.

```csharp
var proposal = manager.Propose(manifest, remoteEndpoint);
Assert.Equal(TransferSessionStatus.Pending, proposal.Status);
Assert.Throws<SessionNotAcceptedException>(() => manager.AuthorizeChunk(proposal.Id, "bad", "f1", 0));
```

- [ ] **Step 2: Run session tests and verify failure**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj --filter SessionManagerTests`

Expected: FAIL because session types are missing.

- [ ] **Step 3: Implement the explicit transition table and HMAC token**

Allow only `pending → accepted|rejected|cancelled`, `accepted → transferring|cancelled|failed`, `transferring → completed|cancelled|failed`. Generate the six-digit code with `RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6")`. Sign a compact token payload containing session ID, sender ID, manifest digest, expiry and random nonce with an in-memory 256-bit HMAC key regenerated at each launch.

- [ ] **Step 4: Run complete core tests**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj`

Expected: PASS.

- [ ] **Step 5: Commit session security**

```powershell
git add transfer-windows/src/MuseTransfer.Core/Sessions transfer-windows/tests/MuseTransfer.Tests/Sessions
git commit -m "feat: require approval for transfer sessions"
```

## Task 4: Windows HTTPS Receiver and Local Discovery

**Files:**
- Create: `transfer-windows/src/MuseTransfer.App/MuseTransfer.App.csproj`
- Create: `transfer-windows/src/MuseTransfer.App/Networking/ReceiverHost.cs`
- Create: `transfer-windows/src/MuseTransfer.App/Networking/TransferEndpoints.cs`
- Create: `transfer-windows/src/MuseTransfer.App/Discovery/MdnsAdvertiser.cs`
- Create: `transfer-windows/src/MuseTransfer.App/Composition/AppServices.cs`
- Create: `transfer-windows/tests/MuseTransfer.Tests/Networking/ReceiverHostTests.cs`

**Interfaces:**
- Consumes: Task 1 endpoints and Task 3 session authorization.
- Produces: `IReceiverHost.StartAsync`, `StopAsync`, `BoundPort`; mDNS service `_musetransfer._tcp` with TXT keys `id`, `name`, `platform`, `v`.

- [ ] **Step 1: Write in-process HTTP integration tests**

Start the receiver on loopback port `0`. Assert proposal returns `202` without uploading data, rejected sessions return `403`, accepted sessions reject a changed manifest or invalid token, valid chunks return `204`, and complete returns `200` only after every file commits.

- [ ] **Step 2: Run receiver tests and verify failure**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj --filter ReceiverHostTests`

Expected: FAIL because the receiver project is absent.

- [ ] **Step 3: Implement Kestrel endpoints and mDNS lifecycle**

Use a per-install self-signed certificate stored in the current-user application data directory. Bind only private/local interfaces plus loopback. Enforce JSON body, file-count and total-size limits before creating a session. Stream request bodies directly to `IncomingFileStore`; never call `ReadToEndAsync` or buffer full files.

Register `_musetransfer._tcp.local` after Kestrel binds and unregister before host disposal. Keep discovery behind `IMdnsAdvertiser` so tests use a fake.

- [ ] **Step 4: Run networking and core tests**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj`

Expected: PASS.

- [ ] **Step 5: Commit the Windows receiver**

```powershell
git add transfer-windows/src/MuseTransfer.App transfer-windows/tests/MuseTransfer.Tests/Networking
git commit -m "feat: host secure windows transfer receiver"
```

## Task 5: Windows Sender, Music Grouping, and Desktop UI

**Files:**
- Create: `transfer-windows/src/MuseTransfer.Core/Music/MusicGrouper.cs`
- Create: `transfer-windows/src/MuseTransfer.App/Networking/TransferClient.cs`
- Create: `transfer-windows/src/MuseTransfer.App/ViewModels/TransferViewModel.cs`
- Create: `transfer-windows/src/MuseTransfer.App/Views/TransferView.xaml`
- Create: `transfer-windows/src/MuseTransfer.App/Views/ReceiveRequestDialog.xaml`
- Create: `transfer-windows/src/MuseTransfer.App/MainWindow.xaml`
- Create: `transfer-windows/src/MuseTransfer.App/App.xaml`
- Create: `transfer-windows/tests/MuseTransfer.Tests/Music/MusicGrouperTests.cs`
- Create: `transfer-windows/tests/MuseTransfer.Tests/ViewModels/TransferViewModelTests.cs`

**Interfaces:**
- Consumes: protocol endpoints and `_musetransfer._tcp` discoveries.
- Produces: `MusicGrouper.Group(IReadOnlyList<SelectedFile>)`, `ITransferClient.SendAsync`, `TransferViewModel.NearbyDevices`, `SendAsync`, `AcceptAsync`, `RejectAsync`, `CancelAsync`.

- [ ] **Step 1: Write failing grouping and ViewModel tests**

Assert `song.mp3`, `song.lrc`, `cover.jpg` in one album folder form one music group; unrelated images remain ordinary files; `.m3u8` references link tracks without changing paths. Assert send is disabled with no device/files, receive requests always expose Accept and Reject, rejection calls the session API before closing, and progress uses bytes transferred divided by total bytes.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj --filter "MusicGrouperTests|TransferViewModelTests"`

Expected: FAIL because grouping/client/ViewModel types are absent.

- [ ] **Step 3: Implement streamed sender and WPF three-column shell**

Hash selected files before proposal using `FileStream` with asynchronous sequential scan. Upload fixed 1 MiB chunks with bounded concurrency of two files, publish immutable progress snapshots, and honor cancellation between reads and HTTP writes. On resume, request the receiver map and skip only confirmed chunks.

Build the WPF shell with left navigation, center device/task lists and right task detail. Add file/folder pickers, file-drop handlers, manual address entry, progress/speed/remaining-time text, explicit receive confirmation, and accessible automation names. Do not nest buttons inside clickable buttons.

- [ ] **Step 4: Run tests and launch a two-instance smoke test**

Run: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj`

Then start one instance with `--profile receiver-smoke` and another with `--profile sender-smoke`; send a fixture directory containing text, MP3-shaped bytes and LRC. Verify rejection writes zero final files, acceptance preserves directories, and cancel leaves no final partial file.

Expected: tests PASS and the accepted fixture hashes match.

- [ ] **Step 5: Commit the Windows vertical slice**

```powershell
git add transfer-windows
git commit -m "feat: complete windows local transfer flow"
```

## Task 6: Swift Protocol Parity and Safe Incoming Storage

**Files:**
- Create: `transfer-ios/project.yml`
- Create: `transfer-ios/MuseTransfer/Protocol/TransferManifest.swift`
- Create: `transfer-ios/MuseTransfer/Protocol/ManifestCanonicalizer.swift`
- Create: `transfer-ios/MuseTransfer/Transfer/SafeRelativePath.swift`
- Create: `transfer-ios/MuseTransfer/Transfer/IncomingFileStore.swift`
- Create: `transfer-ios/MuseTransferTests/ProtocolVectorTests.swift`
- Create: `transfer-ios/MuseTransferTests/IncomingFileStoreTests.swift`

**Interfaces:**
- Consumes: `docs/transfer-protocol/vectors/manifest-v1.json` and Task 1 wire format.
- Produces: Swift `TransferManifest`, `TransferItem`, `MusicGroup`, `ManifestCanonicalizer.canonicalData`, `IncomingFileStore.writeChunk`, `commit`.

- [ ] **Step 1: Write XCTest parity and path-security tests**

Load the shared vector from a test resource, compare exact `Data`, and compare SHA-256. Test the same traversal and duplicate cases as C#. Verify wrong hashes never place a file in the Documents-visible final directory.

- [ ] **Step 2: Generate the project and verify tests fail**

Run on macOS: `cd transfer-ios && xcodegen generate && xcodebuild test -scheme MuseTransfer -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: FAIL because production protocol/storage types are absent.

- [ ] **Step 3: Implement deterministic encoding and actor-isolated storage**

Write canonical JSON fields manually to UTF-8 data in the same order as C#. Use `CryptoKit.SHA256`. Implement storage as an `actor`; stream chunks through `FileHandle`, store resume metadata in Application Support, and replace the temporary URL only after size and hash validation.

```swift
actor IncomingFileStore {
    func writeChunk(sessionID: String, item: TransferItem, index: Int,
                    offset: Int64, bytes: AsyncThrowingStream<Data, Error>) async throws
    func commit(sessionID: String, item: TransferItem,
                destination: URL) async throws -> URL
}
```

- [ ] **Step 4: Run iOS unit tests**

Run: `cd transfer-ios && xcodebuild test -scheme MuseTransfer -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: PASS.

- [ ] **Step 5: Commit Swift protocol parity**

```bash
git add transfer-ios
git commit -m "feat: add ios transfer protocol core"
```

## Task 7: iOS Bonjour, Receiver, and Sender

**Files:**
- Create: `transfer-ios/MuseTransfer/Discovery/NearbyDeviceBrowser.swift`
- Create: `transfer-ios/MuseTransfer/Discovery/ServiceAdvertiser.swift`
- Create: `transfer-ios/MuseTransfer/Transfer/TransferSession.swift`
- Create: `transfer-ios/MuseTransfer/Transfer/ReceiverServer.swift`
- Create: `transfer-ios/MuseTransfer/Transfer/TransferClient.swift`
- Create: `transfer-ios/MuseTransferTests/TransferSessionTests.swift`
- Create: `transfer-ios/MuseTransferTests/TransferClientTests.swift`
- Modify: `transfer-ios/project.yml`

**Interfaces:**
- Consumes: Task 1 HTTP contract and Task 6 storage.
- Produces: `NearbyDeviceBrowser.devices`, `ReceiverServer.requests`, `accept`, `reject`, `TransferClient.send`, `cancel`, `resume`.

- [ ] **Step 1: Write transport-independent tests with in-memory connections**

Test session transitions, five-minute expiry via injected clock, manifest-bound token validation, reject-before-body, chunk resume, cancellation, and stale callback suppression. Test manual host/port connection separately from Bonjour discovery.

- [ ] **Step 2: Run iOS tests and verify failure**

Run: `cd transfer-ios && xcodebuild test -scheme MuseTransfer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MuseTransferTests/TransferSessionTests -only-testing:MuseTransferTests/TransferClientTests`

Expected: FAIL because discovery and transport types do not exist.

- [ ] **Step 3: Implement Network.framework transport**

Use `NWBrowser` and `NWListener` for `_musetransfer._tcp`, and `NWConnection` with TLS for requests. Expose transport events through `AsyncStream`. Parse headers with strict size caps, stream bodies to the actor store, cancel work when background time expires, and restart listening when the app returns active. Validate the receiver certificate fingerprint shown by discovery/session metadata for the current connection.

- [ ] **Step 4: Run complete iOS tests**

Run: `cd transfer-ios && xcodebuild test -scheme MuseTransfer -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: PASS.

- [ ] **Step 5: Commit iOS networking**

```bash
git add transfer-ios
git commit -m "feat: add ios local transfer networking"
```

## Task 8: iOS UI, Share Extension, and History

**Files:**
- Create: `transfer-ios/MuseTransfer/App/MuseTransferApp.swift`
- Create: `transfer-ios/MuseTransfer/App/AppContainer.swift`
- Create: `transfer-ios/MuseTransfer/Features/Transfer/TransferModel.swift`
- Create: `transfer-ios/MuseTransfer/Features/Transfer/TransferView.swift`
- Create: `transfer-ios/MuseTransfer/Features/Transfer/ReceiveRequestSheet.swift`
- Create: `transfer-ios/MuseTransfer/Features/History/TransferHistoryStore.swift`
- Create: `transfer-ios/MuseTransfer/Features/History/HistoryView.swift`
- Create: `transfer-ios/MuseTransfer/Features/Settings/SettingsView.swift`
- Create: `transfer-ios/MuseTransferShare/ShareViewController.swift`
- Create: `transfer-ios/MuseTransferTests/TransferModelTests.swift`
- Modify: `transfer-ios/project.yml`

**Interfaces:**
- Consumes: Task 7 device/session streams.
- Produces: user-visible Transfer/History/Settings tabs and share-extension inbox.

- [ ] **Step 1: Write MainActor model tests**

Assert every request creates a sheet even for a previously accepted sender, dismissal without action rejects, accepted requests show progress, background pause shows waiting state, history excludes token/code/key data, and clearing history removes records but not received files.

- [ ] **Step 2: Run model tests and verify failure**

Run: `cd transfer-ios && xcodebuild test -scheme MuseTransfer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MuseTransferTests/TransferModelTests`

Expected: FAIL because UI model/history types are absent.

- [ ] **Step 3: Implement SwiftUI tabs and share inbox**

Use Transfer/History/Settings tabs, a nearby-device grid, file importer, manual address form, mandatory receive sheet, per-task progress, and explicit cancel. Respect Dynamic Type, VoiceOver labels, high contrast and Reduce Motion. The share extension copies security-scoped inputs into an App Group inbox and opens the main app; it must release every security-scoped resource.

Persist history as versioned Codable records containing device display name, timestamp, relative file name, size, result and destination bookmark only. Exclude session tokens, verification codes and certificate private material.

- [ ] **Step 4: Run iOS tests and static verification**

Run: `cd transfer-ios && ./scripts/verify.sh`

Expected: Xcode project generation succeeds, all XCTest cases pass, required Bonjour/local-network usage descriptions and App Group entitlements exist.

- [ ] **Step 5: Commit the iOS vertical slice**

```bash
git add transfer-ios
git commit -m "feat: complete ios local transfer flow"
```

## Task 9: Music Grouping and Explicit Player Handoff

**Files:**
- Create: `transfer-ios/MuseTransfer/Music/MusicGrouper.swift`
- Create: `transfer-ios/MuseTransfer/Music/MuseMusicHandoff.swift`
- Create: `transfer-windows/src/MuseTransfer.App/Music/MuseMusicHandoff.cs`
- Create: `docs/transfer-protocol/music-handoff-v1.md`
- Create: `transfer-ios/MuseTransferTests/MusicHandoffTests.swift`
- Create: `transfer-windows/tests/MuseTransfer.Tests/Music/MuseMusicHandoffTests.cs`
- Modify: `ios-app/LocalMusicPlayer/Info.plist`
- Create: `ios-app/LocalMusicPlayer/Import/TransferHandoffImporter.swift`
- Modify: `windows-app/src/LocalMusicPlayer/App.xaml.cs`
- Create: `windows-app/src/LocalMusicPlayer/Import/TransferHandoffImporter.cs`

**Interfaces:**
- Consumes: completed `MusicGroup` values.
- Produces: versioned `music-handoff-v1.json` with `handoffId`, item relative paths, hashes and group relationships; idempotent player import keyed by `handoffId`.

- [ ] **Step 1: Write failing handoff validation and idempotency tests on both platforms**

Assert ordinary files never show the handoff action, handoff occurs only after explicit user selection, paths outside the handoff root are rejected, hashes are rechecked by the player, and processing the same `handoffId` twice creates no duplicate tracks. Assert the fallback action is save/open when the player is unavailable.

- [ ] **Step 2: Run focused Windows and iOS tests**

Run Windows: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj --filter MuseMusicHandoffTests`

Run iOS on macOS: `cd transfer-ios && xcodebuild test -scheme MuseTransfer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MuseTransferTests/MusicHandoffTests`

Expected: both FAIL because handoff services are missing.

- [ ] **Step 3: Implement versioned, explicit handoff**

On Windows, write the manifest to a restricted temp handoff directory and launch the registered `musemusic://import?manifest=<escaped-path>` URI. On iOS, copy selected items into the App Group handoff directory, atomically write the manifest, then open `musemusic://import?handoff=<id>`. Both player importers re-normalize paths, re-hash every file, record processed IDs, import through existing file import services, and clean the handoff after a terminal result.

Document ownership, schema, cleanup, result file, and compatibility rules in `music-handoff-v1.md`.

- [ ] **Step 4: Run both application test suites**

Run Windows: `dotnet test transfer-windows/tests/MuseTransfer.Tests/MuseTransfer.Tests.csproj && dotnet test windows-app/tests/LocalMusicPlayer.Tests/LocalMusicPlayer.Tests.csproj`

Run iOS on macOS: `cd transfer-ios && ./scripts/verify.sh && cd ../ios-app && ./scripts/verify.sh`

Expected: all suites PASS.

- [ ] **Step 5: Commit music ecosystem integration**

```powershell
git add docs/transfer-protocol/music-handoff-v1.md transfer-windows transfer-ios windows-app/src/LocalMusicPlayer ios-app/LocalMusicPlayer
git commit -m "feat: hand received music to muse player"
```

## Task 10: Packaging, CI, and Cross-Device Acceptance

**Files:**
- Create: `transfer-windows/scripts/verify.ps1`
- Create: `transfer-windows/scripts/package.ps1`
- Create: `transfer-windows/installer/MuseTransfer.iss`
- Create: `transfer-ios/scripts/verify.sh`
- Create: `.github/workflows/muse-transfer-windows.yml`
- Create: `.github/workflows/muse-transfer-ios.yml`
- Create: `docs/transfer-protocol/acceptance-checklist.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: completed Windows and iOS applications.
- Produces: Windows self-contained x64 build/installer, unsigned iOS test artifact, repeatable CI, recorded manual cross-device acceptance.

- [ ] **Step 1: Add verification scripts that fail on missing tests or required metadata**

Windows verification must restore, build Release, run all transfer tests, publish self-contained `win-x64`, and confirm the executable exists. iOS verification must generate the project, run XCTest, inspect Info.plist for local-network/Bonjour descriptions, inspect App Group entitlements, and build the simulator app.

- [ ] **Step 2: Run scripts before packaging and fix only surfaced configuration failures**

Run Windows: `./transfer-windows/scripts/verify.ps1`

Run iOS on macOS: `cd transfer-ios && ./scripts/verify.sh`

Expected: both PASS; if a script fails, preserve its exact failure as the next test-first input rather than bypassing the check.

- [ ] **Step 3: Add current-user installer and CI workflows**

Package Windows per-user without elevation, allow install-directory choice, register/unregister firewall and `muse-transfer` URI entries at user scope, and preserve received files on uninstall. CI must upload test logs and artifacts, use pinned major action versions, and never embed signing secrets in the unsigned iOS workflow.

- [ ] **Step 4: Execute the cross-device acceptance checklist**

On a real Windows 10/11 machine and iOS 17+ iPhone on the same Wi-Fi, record PASS/FAIL for discovery, manual address, reject-before-upload, single file, multi-file, nested folder, 2+ GiB streamed file when storage permits, cancel, reconnect/resume with renewed confirmation, duplicate naming, bad-hash rejection, background pause/resume, share extension, music grouping and player handoff. Verify operation with WAN access disabled.

- [ ] **Step 5: Run final repository verification and commit release infrastructure**

Run Windows: `./transfer-windows/scripts/verify.ps1; ./windows-app/scripts/verify.ps1`

Run macOS CI: both transfer iOS and existing music iOS verification workflows.

Expected: all automated checks PASS; the acceptance checklist contains actual device/OS versions and observed results, with no unchecked success claims.

```powershell
git add transfer-windows transfer-ios .github/workflows docs/transfer-protocol/acceptance-checklist.md README.md
git commit -m "build: verify and package muse transfer apps"
```
