import Testing
@testable import WhispIt

@Suite("TranscriptionService.removingNonSpeechMarkers")
struct NonSpeechMarkerTests {
    @Test(arguments: [
        ("[BLANK_AUDIO]", ""),
        ("[ Silence ]", ""),
        ("  [MUSIC PLAYING]  ", ""),
        ("(music)", ""),
        ("(upbeat music) Hello there.", "Hello there."),
        ("Hi [inaudible] there", "Hi there"),
        ("Thanks (laughs) a lot", "Thanks a lot"),
        ("Ship it on Friday.", "Ship it on Friday."),
        ("Meet me there (around noon) okay", "Meet me there (around noon) okay"),
        ("one\n\ntwo   three", "one two three"),
    ])
    func strips(_ input: String, _ expected: String) {
        #expect(TranscriptionService.removingNonSpeechMarkers(input) == expected)
    }
}
