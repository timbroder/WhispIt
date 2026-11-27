import AVFoundation
import Foundation
import Testing
@testable import WhispIt

/// Parses the system's interruption and route-change notifications into
/// the callbacks the coordinator uses to stop recording and restart the
/// keep-alive session (H3).
@Suite("AudioInterruptionHandler", .serialized)
@MainActor
struct AudioInterruptionHandlerTests {
    final class Recorder: @unchecked Sendable {
        var began = 0
        var ended: [Bool] = []
        var routes: [AVAudioSession.RouteChangeReason] = []
    }

    func makeHandler() -> (AudioInterruptionHandler, Recorder) {
        let handler = AudioInterruptionHandler()
        let recorder = Recorder()
        handler.onInterruptionBegan = { recorder.began += 1 }
        handler.onInterruptionEnded = { recorder.ended.append($0) }
        handler.onRouteChanged = { recorder.routes.append($0) }
        handler.start()
        return (handler, recorder)
    }

    func postInterruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions? = nil) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if let options { info[AVAudioSessionInterruptionOptionKey] = options.rawValue }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: info)
    }

    func postRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
    }

    @Test func interruptionBeganIsReported() async {
        let (handler, recorder) = makeHandler()
        defer { handler.stop() }
        postInterruption(.began)
        #expect(await waitUntil { recorder.began == 1 })
    }

    @Test func interruptionEndedReportsShouldResume() async {
        let (handler, recorder) = makeHandler()
        defer { handler.stop() }
        postInterruption(.ended, options: .shouldResume)
        postInterruption(.ended)
        #expect(await waitUntil { recorder.ended == [true, false] })
    }

    @Test func routeChangeReasonIsForwarded() async {
        let (handler, recorder) = makeHandler()
        defer { handler.stop() }
        postRouteChange(.oldDeviceUnavailable)
        #expect(await waitUntil { recorder.routes == [.oldDeviceUnavailable] })
    }

    @Test func malformedNotificationsAreIgnored() async throws {
        let (handler, recorder) = makeHandler()
        defer { handler.stop() }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: nil)
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: ["junk": 1])
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.began == 0 && recorder.ended.isEmpty && recorder.routes.isEmpty)
    }

    @Test func stopRemovesObservers() async throws {
        let (handler, recorder) = makeHandler()
        handler.stop()
        postInterruption(.began)
        postRouteChange(.newDeviceAvailable)
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.began == 0 && recorder.routes.isEmpty)
    }

    @Test func startingTwiceDoesNotDoubleReport() async {
        let (handler, recorder) = makeHandler()
        defer { handler.stop() }
        handler.start()
        postInterruption(.began)
        #expect(await waitUntil { recorder.began >= 1 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(recorder.began == 1)
    }
}
