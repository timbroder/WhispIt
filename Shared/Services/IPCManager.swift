import Foundation

final class IPCManager {
    static let shared = IPCManager()

    enum IPCError: Error {
        case appGroupContainerUnavailable
    }

    private var observers: [String: () -> Void] = [:]
    private let lock = NSLock()

    private init() {}

    func post(_ name: CFString) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name), nil, nil, true)
    }

    func observe(_ name: CFString, handler: @escaping () -> Void) {
        lock.lock()
        observers[name as String] = handler
        lock.unlock()

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observerRef = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observerRef,
            { _, opaqueObserver, opaqueName, _, _ in
                guard let opaqueObserver, let opaqueName else { return }
                let manager = Unmanaged<IPCManager>.fromOpaque(opaqueObserver).takeUnretainedValue()
                manager.dispatch(name: opaqueName.rawValue as String)
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    private func dispatch(name: String) {
        lock.lock()
        let handler = observers[name]
        lock.unlock()
        handler?()
    }

    func removeObserver(_ name: CFString) {
        lock.lock()
        observers.removeValue(forKey: name as String)
        lock.unlock()

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observerRef = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observerRef, CFNotificationName(name), nil)
    }

    func removeAllObservers() {
        lock.lock()
        observers.removeAll()
        lock.unlock()

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observerRef = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(center, observerRef)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func write<T: Encodable>(_ value: T, to file: WhispItConstants.SharedFile) throws {
        guard let url = WhispItConstants.sharedFileURL(file) else {
            throw IPCError.appGroupContainerUnavailable
        }
        let data = try Self.encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    func read<T: Decodable>(_ type: T.Type, from file: WhispItConstants.SharedFile) throws -> T {
        guard let url = WhispItConstants.sharedFileURL(file) else {
            throw IPCError.appGroupContainerUnavailable
        }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(type, from: data)
    }

    func writeText(_ text: String, to file: WhispItConstants.SharedFile) throws {
        guard let url = WhispItConstants.sharedFileURL(file) else {
            throw IPCError.appGroupContainerUnavailable
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func readText(from file: WhispItConstants.SharedFile) throws -> String {
        guard let url = WhispItConstants.sharedFileURL(file) else {
            throw IPCError.appGroupContainerUnavailable
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
