import Foundation

/// Watches a file for changes using FSEvents
public actor FSEventsFileWatcher: FileWatcherProtocol {
    private let path: String
    private var stream: FSEventStreamRef?
    private var handler: (@Sendable () -> Void)?
    private var isWatching = false

    public init(path: String) {
        self.path = path
    }

    deinit {
        // Note: Can't call async stopWatching from deinit
        // Stream cleanup should be done by calling stopWatching before releasing
    }

    public func startWatching(handler: @escaping @Sendable () -> Void) async throws {
        guard !isWatching else { return }

        guard FileManager.default.fileExists(atPath: path) else {
            throw FileWatcherError.fileNotFound(path)
        }

        self.handler = handler
        self.isWatching = true

        // Watch the directory containing the file, not just the file itself
        // This is needed for SQLite WAL mode which writes to .db-wal files
        let directoryPath = (path as NSString).deletingLastPathComponent
        serverLog("Starting to watch directory \(directoryPath) for changes to \((path as NSString).lastPathComponent)")

        // Start FSEvents stream on a background queue
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                let pathsToWatch = [directoryPath] as CFArray

                // Create context with pointer to self for callback
                var context = FSEventStreamContext(
                    version: 0,
                    info: Unmanaged.passUnretained(self).toOpaque(),
                    retain: nil,
                    release: nil,
                    copyDescription: nil
                )

                let callback: FSEventStreamCallback = { (
                    streamRef,
                    clientCallBackInfo,
                    numEvents,
                    eventPaths,
                    eventFlags,
                    eventIds
                ) in
                    guard let info = clientCallBackInfo else { return }
                    let watcher = Unmanaged<FSEventsFileWatcher>.fromOpaque(info).takeUnretainedValue()

                    // Notify on main actor
                    Task {
                        await watcher.notifyChange()
                    }
                }

                let stream = FSEventStreamCreate(
                    nil,
                    callback,
                    &context,
                    pathsToWatch,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    0.05, // Latency in seconds (50ms for faster updates)
                    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
                )

                if let stream = stream {
                    FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
                    FSEventStreamStart(stream)

                    Task {
                        await self.setStream(stream)
                    }

                    continuation.resume()

                    // Run the run loop to receive events
                    CFRunLoopRun()
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func stopWatching() async {
        guard isWatching, let stream = stream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        self.stream = nil
        self.handler = nil
        self.isWatching = false
    }

    // MARK: - Private Methods

    private func setStream(_ stream: FSEventStreamRef) {
        self.stream = stream
    }

    private func notifyChange() {
        serverLogDebug("File change detected")
        handler?()
    }
}
