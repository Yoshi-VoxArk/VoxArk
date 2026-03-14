import SwiftUI
import AVFoundation
import Combine
import Speech

// 単語ごとの判定結果を持つための型
struct WordResult: Identifiable {
    let id = UUID()
    let text: String
    let isCorrect: Bool
}

class VoiceManager: ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    @Published var soundLevel: CGFloat = 1.0
    @Published var isPlaying = false
    @Published var pronunciationScore: Int = 0
    @Published var wordResults: [WordResult] = [] // 単語ごとの結果

    private var recordingURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("latest_voice.m4a")
    }

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try session.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            DispatchQueue.main.async {
                self.pronunciationScore = 0
                self.wordResults = []
            }

            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                self.audioRecorder?.updateMeters()
                let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                let level = CGFloat(max(0, (power + 50) / 50))
                withAnimation(.linear(duration: 0.05)) {
                    self.soundLevel = 1.0 + (level * 2.5)
                }
            }
        } catch { print("Recording error") }
    }

    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        soundLevel = 1.0
        performTranscription()
    }

    private func performTranscription() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            let request = SFSpeechURLRecognitionRequest(url: self.recordingURL)
            
            recognizer?.recognitionTask(with: request) { result, error in
                if let result = result {
                    DispatchQueue.main.async {
                        let text = result.bestTranscription.formattedString
                        let confidence = result.bestTranscription.segments.map { $0.confidence }.reduce(0, +) / Float(result.bestTranscription.segments.count)
                        self.analyzeSpeech(userText: text, confidence: confidence)
                    }
                }
            }
        }
    }

    // 単語レベルで分析してスコアを出す
    private func analyzeSpeech(userText: String, confidence: Float) {
        let modelText = "My dog is dancing at the entrance"
        
        // 記号を取り除いて小文字化
        let cleanUser = userText.lowercased().components(separatedBy: .punctuationCharacters).joined()
        let cleanModel = modelText.lowercased().components(separatedBy: .punctuationCharacters).joined()
        
        let userWords = cleanUser.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let modelWords = cleanModel.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var results: [WordResult] = []
        var matchCount = 0
        
        // 単語ごとに判定（お手本に含まれているか）
        for word in userWords {
            let isMatch = modelWords.contains(word)
            if isMatch { matchCount += 1 }
            results.append(WordResult(text: word, isCorrect: isMatch))
        }
        
        let matchRatio = Float(matchCount) / Float(modelWords.count)
        let finalScore = (matchRatio * 0.7 + confidence * 0.3) * 100
        
        DispatchQueue.main.async {
            self.wordResults = results
            self.pronunciationScore = Int(min(100, finalScore))
        }
    }

    func playLastRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            audioPlayer = try AVAudioPlayer(contentsOf: recordingURL)
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 0)) {
                self.isPlaying = false
            }
        } catch { print("Playback error") }
    }
}

struct ContentView: View {
    @State private var isShowingOriginal = false
    @State private var isRecording = false
    @StateObject private var voiceManager = VoiceManager()
    
    let synthesizer = AVSpeechSynthesizer()
    @State private var audioPlayer: AVAudioPlayer?
    
    let translatedText = "うちの犬が玄関でダンスしています。"
    let originalText = "My dog is dancing at the entrance."
    
    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 25) {
                // ヘッダー
                HStack {
                    Image(systemName: "bird.fill").font(.system(size: 24))
                    Text("VoxArk").font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    Text("Phase 4").font(.caption).padding(6)
                        .background(Color.green.opacity(0.2)).cornerRadius(8)
                }
                .foregroundColor(.white.opacity(0.9)).padding(.horizontal)

                // メッセージカード
                VStack(alignment: .leading, spacing: 15) {
                    Text(translatedText).font(.system(size: 20, weight: .medium)).foregroundColor(.white)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { isShowingOriginal.toggle() }
                        if isShowingOriginal { playPigeonAndVoice() }
                    }) {
                        HStack {
                            Image(systemName: isShowingOriginal ? "speaker.wave.2.fill" : "text.magnifyingglass")
                            Text(isShowingOriginal ? "原文を隠す" : "原文を表示して声を聴く")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .background(isShowingOriginal ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                        .cornerRadius(20).foregroundColor(isShowingOriginal ? .blue : .gray)
                    }

                    if isShowingOriginal {
                        VStack(alignment: .leading, spacing: 8) {
                            Divider().background(Color.gray.opacity(0.3))
                            Text(originalText).font(.system(size: 18, design: .serif)).italic().foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .padding(20).background(RoundedRectangle(cornerRadius: 24).fill(Color(white: 0.12))).padding(.horizontal)

                // --- 1. あなたの発音スコア ---
                VStack(spacing: 5) {
                    Text("あなたの発音スコア")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
                    Text("\(voiceManager.pronunciationScore)")
                        .font(.system(size: 64, weight: .black, design: .rounded)).foregroundColor(scoreColor)
                }
                .frame(maxWidth: .infinity)

                // --- 2. 視覚的フィードバック（単語ハイライト） ---
                if !voiceManager.wordResults.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("解析詳細:").font(.caption).foregroundColor(.gray)
                        // 単語を横に並べて表示
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(voiceManager.wordResults) { result in
                                    Text(result.text)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(result.isCorrect ? .green : .red)
                                        .padding(.horizontal, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // --- 3. 再生ボタン ---
                Button(action: { voiceManager.playLastRecording() }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("自分の声を再生して確認する")
                    }
                    .font(.headline).foregroundColor(.orange).padding().frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1)).cornerRadius(12)
                }
                .padding(.horizontal).opacity(voiceManager.pronunciationScore > 0 ? 1 : 0.3)

                Spacer()
                
                // マイクボタン
                HStack {
                    Spacer()
                    ZStack {
                        if isRecording {
                            Circle().fill(Color.red.opacity(0.3)).frame(width: 80, height: 80)
                                .scaleEffect(voiceManager.soundLevel)
                        }
                        Button(action: {
                            isRecording.toggle()
                            if isRecording { voiceManager.startRecording() }
                            else { voiceManager.stopRecording() }
                        }) {
                            Circle()
                                .fill(LinearGradient(colors: isRecording ? [.red, .orange] : [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 70, height: 70)
                                .overlay(Image(systemName: isRecording ? "stop.fill" : "mic.fill").font(.title).foregroundColor(.white))
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 30)
            }
            .padding(.top, 20)
        }
    }

    var scoreColor: Color {
        if voiceManager.pronunciationScore >= 90 { return .green }
        if voiceManager.pronunciationScore >= 70 { return .yellow }
        if voiceManager.pronunciationScore > 0 { return .orange }
        return .gray.opacity(0.3)
    }

    func playPigeonAndVoice() {
        if let soundURL = Bundle.main.url(forResource: "pigeon", withExtension: "mp3") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.play()
            } catch { print("Sound error") }
        }
        let utterance = AVSpeechUtterance(string: originalText)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.stopSpeaking(at: .immediate)
        DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 1.5)) { synthesizer.speak(utterance) }
    }
}
