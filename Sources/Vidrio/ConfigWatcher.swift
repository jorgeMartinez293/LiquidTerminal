import Foundation
import CoreServices

/// Recursively watches a directory and fires `onChange` (debounced, on the main queue)
/// with the accumulated set of changed paths whenever anything under it is added,
/// edited, or removed. Ported from bruma's WidgetWatcher.
final class ConfigWatcher {
    private var stream: FSEventStreamRef?
    private let path: String
    private let onChange: ([String]) -> Void
    private var debounce: DispatchWorkItem?
    private var pendingPaths: [String] = []

    init(path: String, onChange: @escaping ([String]) -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<ConfigWatcher>.fromOpaque(info).takeUnretainedValue()
            // With kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArray of CFString.
            let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
                         as? [String]) ?? []
            watcher.fire(paths: paths)
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // latency seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                     | kFSEventStreamCreateFlagNoDefer
                                     | kFSEventStreamCreateFlagUseCFTypes)
        )
        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    private func fire(paths: [String]) {
        pendingPaths.append(contentsOf: paths)
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let paths = self.pendingPaths
            self.pendingPaths = []
            self.onChange(paths)
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    deinit {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
