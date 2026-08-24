import AVFoundation
import Foundation
import Speech

enum SpeechSessionError: LocalizedError {
    case formatUnavailable
    case converterFailed
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .formatUnavailable:
            return "No compatible speech audio format."
        case .converterFailed:
            return "Could not convert microphone audio."
        case .engineFailed(let message):
            return message
        }
    }
}

/// One hold-to-talk pass: mic → SpeechAnalyzer → transcript.
final class SpeechSession: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var resultTask: Task<Void, Never>?
    private var finals: [String] = []
    private var volatile = ""
    private var onPartial: (@MainActor (String) -> Void)?

    var currentText: String {
        let parts = finals + (volatile.isEmpty ? [] : [volatile])
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start(onPartial: @escaping @MainActor (String) -> Void) async throws {
        try await stopWithoutReturning()
        self.onPartial = onPartial
        finals = []
        volatile = ""

        let locale = Locale.current
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechSessionError.formatUnavailable
        }

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation

        let analyzer = SpeechAnalyzer(inputSequence: stream, modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        let converter = AudioBufferConverter(from: hardwareFormat, to: analyzerFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { buffer, _ in
            let output: AVAudioPCMBuffer
            if hardwareFormat == analyzerFormat {
                output = buffer
            } else if let converter, let converted = converter.convert(buffer) {
                output = converted
            } else {
                return
            }
            continuation.yield(AnalyzerInput(buffer: output))
        }

        do {
            try engine.start()
        } catch {
            throw SpeechSessionError.engineFailed(error.localizedDescription)
        }

        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        if !text.isEmpty {
                            self.finals.append(text)
                        }
                        self.volatile = ""
                    } else {
                        self.volatile = text
                    }
                    let snapshot = self.currentText
                    await onPartial(snapshot)
                }
            } catch {
                // Stream cancellation on stop is expected.
            }
        }
    }

    func stop() async -> String {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        inputContinuation?.finish()
        inputContinuation = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil

        resultTask?.cancel()
        resultTask = nil
        onPartial = nil

        return currentText
    }

    private func stopWithoutReturning() async throws {
        _ = await stop()
        finals = []
        volatile = ""
    }
}
