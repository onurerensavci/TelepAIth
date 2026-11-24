import AVFoundation

/// Robotun önemli anlarda (bitti, seni bekliyor, güncelleme) sesli konuşması.
enum Speech {
    private static let synthesizer = AVSpeechSynthesizer()

    static func say(_ text: String) {
        guard Preferences.speak, !Preferences.muted else { return }
        // Emojileri ve fazla boşlukları at
        let clean = text.unicodeScalars
            .filter { !($0.properties.isEmojiPresentation || $0.properties.generalCategory == .otherSymbol) }
            .map(String.init).joined()
            .replacingOccurrences(of: "\n", with: ". ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: Language.current == .tr ? "tr-TR" : "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
        synthesizer.speak(utterance)
    }
}
