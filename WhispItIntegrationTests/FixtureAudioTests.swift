import AVFoundation
import Foundation
import Testing
@testable import WhispIt

enum Fixture: String, CaseIterable {
    case fillers, properNouns = "proper-nouns", selfCorrection = "self-correction"
    case silence, pause, longPassage = "long-passage"

    var url: URL {
        get throws {
            try #require(Bundle(for: BundleToken.self).url(forResource: rawValue, withExtension: "wav"),
                         "Missing fixture \(rawValue).wav — run Scripts/make-audio-fixtures.sh")
        }
    }
}

private final class BundleToken {}

@Suite("Audio fixtures")
struct FixtureAudioTests {
    @Test(arguments: Fixture.allCases)
    func fixtureLoadsAsMicShapedAudio(_ fixture: Fixture) throws {
        let source = try FileAudioInputSource(url: fixture.url, realTime: false)
        #expect(source.format.sampleRate == 48_000)
        #expect(source.format.channelCount == 2)
        #expect(source.duration > 1)
    }

    @Test func silenceFixtureIsSilentAndSpeechIsNot() throws {
        let silence = try FileAudioInputSource.load(url: Fixture.silence.url, as: FileAudioInputSource.micFormat)
        let speech = try FileAudioInputSource.load(url: Fixture.fillers.url, as: FileAudioInputSource.micFormat)
        #expect(VoiceActivityDetector.rms(of: silence) < 0.001)
        #expect(VoiceActivityDetector.rms(of: speech) > 0.01)
    }
}
