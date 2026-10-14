#if canImport(KSPlayer)
import AngelLiveCore
import Foundation
import KSPlayer
import Libavformat
import Libavutil
import os

/// Runs synchronously on the player's dedicated opening/reading thread. The returned
/// context transfers to KSMEPlayer, whose demux loop serializes read, seek and close.
enum MediaTransformContextFactory {
    /// Captures only the synchronized error state before the context transfers to
    /// KSMEPlayer. UI callbacks never inspect mutable FFmpeg state to read errors.
    static func failureReader(for context: FormatContext) -> @Sendable () -> Error? {
        let state = (context.ioContext as? MediaTransformIOOwner)?.failures
        return { state?.failure }
    }

    static func make(url: URL, options: KSOptions, transform: LiveMediaTransform, interrupt: IOInterruptContext) throws -> FormatContext {
        let owner = try MediaTransformIOOwner(url: url, transform: transform.validated(), interrupt: interrupt)
        var context = avformat_alloc_context()
        guard let allocated = context else { throw MediaTransformIOError.allocation }
        allocated.pointee.opaque = Unmanaged.passUnretained(owner).toOpaque()
        allocated.pointee.interrupt_callback = owner.interruptCallback
        allocated.pointee.io_open = { context, output, name, flags, options in
            guard let context, let output, let name, let owner = MediaTransformIOOwner.from(context) else { return -22 }
            return owner.open(url: String(cString: name), output: output, flags: flags, options: options)
        }
        allocated.pointee.io_close2 = { context, input in
            guard let context, let input, let owner = MediaTransformIOOwner.from(context) else { return -22 }
            return owner.close(input)
        }
        var dictionary: OpaquePointer?
        for (key, value) in options.formatContextOptions {
            av_dict_set(&dictionary, key, String(describing: value), 0)
        }
        // HLS's persistent HTTP path casts AVIO internals to its private HTTP
        // implementation. Each wrapped request must use the public io_open path.
        av_dict_set(&dictionary, "http_persistent", "0", 0)
        av_dict_set(&dictionary, "http_multiple", "0", 0)
        defer { av_dict_free(&dictionary) }
        let name = url.isFileURL ? url.path : url.absoluteString
        let openResult = avformat_open_input(&context, name, av_find_input_format("hls"), &dictionary)
        guard openResult >= 0, let opened = context else {
            avformat_close_input(&context)
            throw owner.failure ?? MediaTransformIOError.ffmpeg(operation: "open", code: openResult)
        }
        let findResult = avformat_find_stream_info(opened, nil)
        guard findResult >= 0, owner.failure == nil else {
            avformat_close_input(&context)
            throw owner.failure ?? MediaTransformIOError.ffmpeg(operation: "probe", code: findResult)
        }
        opened.pointee.pb?.pointee.eof_reached = 0
        return FormatContext(formatCtx: opened, fileSize: 0, interrupt: interrupt,
                             ioContext: owner,
                             audioOutputType: options.audioOutputType)
    }
}

/// FFmpeg writes on its serial IO thread; the player reads on MainActor when HLS
/// reports EOF. HLS may turn a failed segment into EOF, so this state crosses that
/// boundary independently of AVFormatContext/AVIO pointer lifetimes.
final class MediaTransformFailureState: Sendable {
    private struct State: Sendable {
        var fatal: Error?
        var transport: Error?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var failure: Error? { state.withLock { $0.fatal ?? $0.transport } }
    var hasFatalFailure: Bool { state.withLock { $0.fatal != nil } }

    func record(_ error: Error) {
        state.withLock {
            if case MediaTransformIOError.ffmpeg = error { $0.transport = error }
            else if $0.fatal == nil { $0.fatal = error }
        }
    }

    func didRead() { state.withLock { $0.transport = nil } }
}

/// The superclass requires Sendable. All mutable members below are confined to the
/// serial FFmpeg demux lifecycle (opening, reading/seeking, then closing); no UI or
/// cancellation thread accesses them. Only KSPlayer's existing interrupt object
/// crosses that boundary. `close()` deliberately does not destroy active children.
private final class MediaTransformIOOwner: AbstractAVIOContext, @unchecked Sendable {
    private let transform: LiveMediaTransform
    private let interrupt: IOInterruptContext
    private let rootURL: URL
    private var roles: [URL: MediaTransformPlaylist.Role]
    private struct PlaylistSnapshot {
        let effectiveURL: URL
        let references: [URL: MediaTransformPlaylist.Role]
    }
    private var playlists: [URL: PlaylistSnapshot] = [:]
    private var children: [UnsafeMutablePointer<AVIOContext>: MediaTransformInput] = [:]
    let failures = MediaTransformFailureState()
    var failure: Error? { failures.failure }

    init(url: URL, transform: LiveMediaTransform, interrupt: IOInterruptContext) throws {
        self.transform = transform
        self.interrupt = interrupt
        rootURL = url.absoluteURL
        roles = [url.absoluteURL: .playlist]
        super.init()
    }

    var interruptCallback: AVIOInterruptCB {
        AVIOInterruptCB(callback: { opaque in
            guard let opaque else { return 1 }
            return Unmanaged<IOInterruptContext>.fromOpaque(opaque).takeUnretainedValue().interrupt ? 1 : 0
        }, opaque: Unmanaged.passUnretained(interrupt).toOpaque())
    }

    static func from(_ context: UnsafeMutablePointer<AVFormatContext>) -> MediaTransformIOOwner? {
        guard let opaque = context.pointee.opaque else { return nil }
        let object = Unmanaged<AnyObject>.fromOpaque(opaque).takeUnretainedValue()
        if let owner = object as? MediaTransformIOOwner { return owner }
        // FormatContext replaces opaque and wraps our callbacks after probing.
        // Nested HLS contexts inherit that opaque as required by libavformat.
        return (object as? FormatContext)?.ioContext as? MediaTransformIOOwner
    }

    func open(url name: String, output: UnsafeMutablePointer<UnsafeMutablePointer<AVIOContext>?>,
              flags: Int32, options: UnsafeMutablePointer<OpaquePointer?>?) -> Int32 {
        var native: UnsafeMutablePointer<AVIOContext>?
        do {
            guard !failures.hasFatalFailure else { return -22 }
            guard flags & AVIO_FLAG_WRITE == 0 else { throw MediaTransformIOError.unknownResource }
            let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : URL(string: name)
            guard let url, let role = roles[url.absoluteURL] else { throw MediaTransformIOError.unknownResource }
            var callback = interruptCallback
            let result = avio_open2(&native, name, flags, &callback, options)
            guard result >= 0, let opened = native else {
                throw MediaTransformIOError.ffmpeg(operation: "request", code: result)
            }
            let baseURL = Self.effectiveURL(opened, fallback: url)
            var playlist: Data?
            if role == .playlist {
                let data = try Self.readPlaylist(opened)
                let parsed = try MediaTransformPlaylist(data: data, baseURL: baseURL)
                let source = playlists.first(where: { $0.value.effectiveURL == url })?.key ?? url
                playlists[source] = PlaylistSnapshot(effectiveURL: baseURL, references: parsed.references)
                try rebuildRoles()
                playlist = data
            }
            let input = MediaTransformInput(native: opened, playlist: playlist,
                                           transform: role == .segment ? transform : nil,
                                           onFailure: { [failures] in failures.record($0) },
                                           onRead: { [failures] in failures.didRead() })
            guard let wrapper = input.getContext() else { throw MediaTransformIOError.allocation }
            wrapper.pointee.seekable = playlist == nil ? opened.pointee.seekable : AVIO_SEEKABLE_NORMAL
            children[wrapper] = input
            output.pointee = wrapper
            native = nil // The child now owns the native AVIO handle.
            return 0
        } catch {
            failures.record(error)
            avio_closep(&native)
            if case let MediaTransformIOError.ffmpeg(_, code) = error { return code }
            return -22
        }
    }

    func close(_ pointer: UnsafeMutablePointer<AVIOContext>) -> Int32 {
        guard let input = children.removeValue(forKey: pointer) else { return -22 }
        input.close()
        var pointer: UnsafeMutablePointer<AVIOContext>? = pointer
        av_freep(&pointer!.pointee.buffer)
        avio_context_free(&pointer)
        return 0
    }

    // FormatContext calls this BEFORE avformat_close_input. The demuxer still owns
    // each AVIO pointer until its io_close2 callback; releasing here would be a UAF.
    override func close() {}

    /// Retain the current graph, not every historical live-playlist segment URL.
    /// Active inputs own their native handles independently of this lookup table.
    private func rebuildRoles() throws {
        var current: [URL: MediaTransformPlaylist.Role] = [rootURL: .playlist]
        var pending = [rootURL]
        var visited: Set<URL> = []
        var retained: Set<URL> = []
        while let url = pending.popLast() {
            guard visited.insert(url).inserted else { continue }
            let source = playlists[url] != nil ? url : playlists.first(where: { $0.value.effectiveURL == url })?.key
            guard let source, let snapshot = playlists[source] else { continue }
            retained.insert(source)
            if let previous = current[snapshot.effectiveURL], previous != .playlist {
                throw MediaTransformIOError.ambiguousResource
            }
            current[snapshot.effectiveURL] = .playlist
            for (resource, role) in snapshot.references {
                if let previous = current[resource], previous != role { throw MediaTransformIOError.ambiguousResource }
                current[resource] = role
                if role == .playlist { pending.append(resource) }
            }
        }
        roles = current
        playlists = playlists.filter { retained.contains($0.key) }
    }

    deinit {
        // Failed avformat_open_input can leave a custom input outside its cleanup
        // path. Only handles still registered here remain ours to release.
        for (pointer, input) in children {
            input.close()
            var pointer: UnsafeMutablePointer<AVIOContext>? = pointer
            av_freep(&pointer!.pointee.buffer)
            avio_context_free(&pointer)
        }
    }

    private static func effectiveURL(_ context: UnsafeMutablePointer<AVIOContext>, fallback: URL) -> URL {
        var value: UnsafeMutablePointer<UInt8>?
        defer { av_free(value) }
        guard av_opt_get(context, "location", AV_OPT_SEARCH_CHILDREN, &value) >= 0,
              let value, let url = URL(string: String(cString: value)) else { return fallback }
        return url.absoluteURL
    }

    private static func readPlaylist(_ input: UnsafeMutablePointer<AVIOContext>) throws -> Data {
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = avio_read(input, &bytes, Int32(bytes.count))
            if count == mediaTransformEOF { return data }
            guard count > 0 else { throw MediaTransformIOError.ffmpeg(operation: "playlist read", code: count) }
            guard data.count + Int(count) <= 4 * 1024 * 1024 else { throw MediaTransformIOError.playlistTooLarge }
            data.append(contentsOf: bytes.prefix(Int(count)))
        }
    }
}

private let mediaTransformEOF: Int32 = -541478725

/// Same serial demux confinement as MediaTransformIOOwner. The native input is
/// retained for AVOptions traversal, including redirect location and HTTP metadata.
final class MediaTransformInput: AbstractAVIOContext, @unchecked Sendable {
    private var native: UnsafeMutablePointer<AVIOContext>?
    private let playlist: Data?
    private let transform: LiveMediaTransform?
    private var position: Int64 = 0
    private var prefix: [UInt8] = []
    private var failed = false
    private let onFailure: ((Error) -> Void)?
    private let onRead: (() -> Void)?

    init(native: UnsafeMutablePointer<AVIOContext>, playlist: Data?, transform: LiveMediaTransform?,
         onFailure: ((Error) -> Void)? = nil, onRead: (() -> Void)? = nil) {
        self.native = native
        self.playlist = playlist
        self.transform = transform
        self.onFailure = onFailure
        self.onRead = onRead
        super.init()
    }

    override func read(buffer: UnsafeMutablePointer<UInt8>?, size: Int32) -> Int32 {
        guard !failed, let native, let buffer, size > 0 else { return -22 }
        if let playlist {
            let count = min(Int(size), playlist.count - Int(position))
            guard count > 0 else { return mediaTransformEOF }
            playlist.copyBytes(to: buffer, from: Int(position)..<(Int(position) + count))
            position += Int64(count)
            onRead?()
            return Int32(count)
        }
        do {
            if position == 0, prefix.isEmpty, transform != nil {
                var bytes = [UInt8](repeating: 0, count: 188 * 3)
                let count = avio_read(native, &bytes, Int32(bytes.count))
                guard count > 0 else { return readFailure(count) }
                bytes.removeLast(bytes.count - Int(count))
                try transform?.apply(to: &bytes, at: 0)
                guard bytes.count >= 188,
                      stride(from: 0, to: bytes.count, by: 188).allSatisfy({ bytes[$0] == 0x47 }) else {
                    throw MediaTransformIOError.unsupportedMediaContainer
                }
                prefix = bytes
            }
            if position < prefix.count {
                let count = min(Int(size), prefix.count - Int(position))
                prefix.withUnsafeBufferPointer {
                    buffer.update(from: $0.baseAddress!.advanced(by: Int(position)), count: count)
                }
                position += Int64(count)
                onRead?()
                return Int32(count)
            }
            let count = avio_read(native, buffer, size)
            guard count > 0 else { return readFailure(count) }
            try transform?.apply(to: UnsafeMutableBufferPointer(start: buffer, count: Int(count)), at: position)
            position += Int64(count)
            onRead?()
            return count
        } catch {
            failed = true
            onFailure?(error)
            return -22
        }
    }

    private func readFailure(_ code: Int32) -> Int32 {
        if code < 0, code != mediaTransformEOF {
            onFailure?(MediaTransformIOError.ffmpeg(operation: "segment read", code: code))
        }
        return code == 0 ? mediaTransformEOF : code
    }

    override func seek(offset: Int64, whence: Int32) -> Int64 {
        guard let native else { return -22 }
        let mode = whence & ~AVSEEK_FORCE
        if mode == AVSEEK_SIZE { return fileSize() }
        if let playlist {
            let base: Int64
            switch mode {
            case SEEK_SET: base = 0
            case SEEK_CUR: base = position
            case SEEK_END: base = Int64(playlist.count)
            default: return -22
            }
            let (target, overflow) = base.addingReportingOverflow(offset)
            guard !overflow, target >= 0, target <= playlist.count else { return -22 }
            position = target
            return target
        }
        let result: Int64
        if mode == SEEK_CUR || mode == SEEK_END {
            // The native handle may be ahead while the validated prefix is
            // buffered. SEEK_CUR is relative to bytes delivered to the caller.
            let base = mode == SEEK_CUR ? position : avio_size(native)
            guard base >= 0 else { return base }
            let (target, overflow) = base.addingReportingOverflow(offset)
            guard !overflow, target >= 0 else { return -22 }
            result = avio_seek(native, target, SEEK_SET | (whence & AVSEEK_FORCE))
        } else {
            result = avio_seek(native, offset, whence)
        }
        if result >= 0 {
            position = result
            prefix.removeAll(keepingCapacity: true)
        }
        return result
    }

    override func fileSize() -> Int64 {
        guard let native else { return -22 }
        if let playlist { return Int64(playlist.count) }
        return avio_size(native)
    }

    override func nextAVOptions() -> UnsafeMutableRawPointer? { native.map(UnsafeMutableRawPointer.init) }
    override func close() { avio_closep(&native) }
}
#endif
