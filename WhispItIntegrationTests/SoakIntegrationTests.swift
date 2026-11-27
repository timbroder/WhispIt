import AVFoundation
import Darwin
import Foundation
import Testing
@testable import WhispIt

private typealias Note = WhispItConstants.DarwinNotification

/// Forwards to whichever fixture source the soak test selects next, so one
/// coordinator (and one AudioCaptureService/converter) handles every run.
private final class SwitchableSource: AudioInputSource, @unchecked Sendable {
    var current: FileAudioInputSource?
    let format = FileAudioInputSource.micFormat

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        try current?.start(onBuffer: onBuffer)
    }

    func stop() { current?.stop() }
}

private func physicalFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

/// Phase 5 soak: 20 dictations in a row through one coordinator with the
/// real WhisperKit model and Foundation Models, mixing speech and silence.
/// Checks every start is accepted, every run produces the right outcome,
/// and memory doesn't keep growing.
@Suite("Soak", .serialized, .timeLimit(.minutes(20)))
struct SoakIntegrationTests {
    @Test func twentyDictationsInARow() async throws {
        await FoundationModelsWarmup.shared.ensure()
        let ipc = CapturingIPC()
        let source = SwitchableSource()
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dictionary = DictionaryManager(fileURL: tempDir.appending(path: "dictionary.json"))
        let coordinator = DictationPipelineCoordinator(
            audioCapture: AudioCaptureService(source: source),
            transcription: try await ModelStore.shared.loadedTranscriber(),
            cleanup: CleanupService(),
            dictionary: dictionary,
            learning: DictionaryLearningService(dictionary: dictionary, defaults: UserDefaults(suiteName: UUID().uuidString)),
            ipc: ipc,
            makeDetector: { VoiceActivityDetector(silenceTimeout: 60) }
        )
        coordinator.startObserving()

        let rotation: [Fixture] = [.fillers, .selfCorrection, .properNouns, .silence, .pause]
        var footprints: [Double] = []
        var durations: [Duration] = []
        let clock = ContinuousClock()

        func resultCount() -> Int {
            ipc.posts.filter { $0 == Note.cleanedTextReady as String || $0 == Note.recordingFailed as String }.count
        }

        for run in 0..<20 {
            let fixture = rotation[run % rotation.count]
            source.current = try FileAudioInputSource(url: fixture.url, realTime: false)
            let before = resultCount()
            let textsBefore = ipc.texts.count

            ipc.simulate(Note.recordingStartRequested)
            coordinator.drainQueue()
            try await Task.sleep(for: .milliseconds(800)) // let the file drain into the pipeline
            let started = clock.now
            ipc.simulate(Note.recordingStopRequested)
            coordinator.drainQueue()

            let finished = await waitUntil(timeout: .seconds(60)) { resultCount() > before }
            #expect(finished, "run \(run) (\(fixture.rawValue)) never finished")
            durations.append(clock.now - started)

            if fixture == .silence {
                #expect(ipc.texts.count == textsBefore, "run \(run): silence inserted text")
            } else {
                #expect(ipc.texts.count == textsBefore + 1, "run \(run) (\(fixture.rawValue)) produced no text")
            }

            // Let finalize clear its state before the next start.
            try await Task.sleep(for: .milliseconds(150))
            coordinator.drainQueue()
            footprints.append(physicalFootprintMB())
        }

        let starts = ipc.posts.filter { $0 == Note.recordingStarted as String }.count
        #expect(starts == 20, "only \(starts) of 20 starts were accepted")

        let ms = durations.map(PipelineLog.milliseconds).sorted()
        let growth = footprints.last! - footprints[1]
        print("[soak] stop→result ms p50=\(ms[ms.count / 2]) p90=\(ms[ms.count * 9 / 10]) max=\(ms.last!)")
        print("[soak] footprint MB first=\(Int(footprints[0])) second=\(Int(footprints[1])) last=\(Int(footprints.last!)) growth=\(Int(growth))")
        // Model and session caches settle after the first run; after that a
        // steady pipeline shouldn't keep climbing.
        #expect(growth < 150, "footprint grew \(Int(growth)) MB over 19 dictations")
    }
}
