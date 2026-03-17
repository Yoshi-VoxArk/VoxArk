import SwiftUI
import AVFoundation
import Translation
import Speech
import Combine

// ==========================================
// 1. リモコン（音量ボタン）の監視役
// ==========================================
@MainActor
class VolumeObserver: ObservableObject {
    @Published var volume: Float = 0.0
    private var observation: NSKeyValueObservation?
    
    init() {
        let session = AVAudioSession.sharedInstance()
        self.volume = session.outputVolume
        do { try session.setActive(true) } catch { print("Audio Session error") }
        
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let newVolume = session.outputVolume
            DispatchQueue.main.async { self?.volume = newVolume }
        }
    }
}

// ==========================================
// 2. 音声認識エンジン
// ==========================================
@MainActor
class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    func startTranscribing(language: String) {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        guard let recognizer = recognizer, recognizer.isAvailable else { return }
        
        task?.cancel()
        task = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { print("Audio setup error: \(error)") }
        
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }
        request.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            self.isRecording = true
            self.transcript = ""
        } catch { return }
        
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil || result?.isFinal == true {
                self.stopTranscribing()
            }
        }
    }
    
    func stopTranscribing() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
    }
}

// ==========================================
// 3. メッセージデータの構造体
// ==========================================
struct SentMessage: Identifiable {
    let id = UUID()
    let originalText: String
    var translatedText: String
    var isTranslating: Bool
    var targetLanguage: String
}

// ==========================================
// 4. メイン画面（ChatView）
// ==========================================
struct ChatView: View {
    @State private var inputText: String = ""
    @State private var messages: [SentMessage] = []
    
    @AppStorage("myLanguage") var myLanguage: String = "system"
    @AppStorage("secondName") var secondName: String = ""
    
    @State private var targetLanguage: String = "en-US"
    @State private var showingSettings = false
    
    let languageList = [
        ("🇺🇸 英語 (米国)", "en-US"), ("🇬🇧 英語 (英国)", "en-GB"),
        ("🇨🇳 中国語", "zh-CN"), ("🇰🇷 韓国語", "ko-KR"),
        ("🇪🇸 スペイン語", "es-ES"), ("🇫🇷 フランス語", "fr-FR"), ("🇹🇭 タイ語", "th-TH"),
        ("🇯🇵 日本語", "ja-JP")
    ]
    
    @State private var isPocketMode: Bool = false
    @State private var birdRotation: Double = 0.0
    @State private var birdOffset: CGFloat = 0.0
    
    private let synthesizer = AVSpeechSynthesizer()
    @StateObject private var volumeObserver = VolumeObserver()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    // ★ ダブルクリック検知のための新しい変数
    @State private var clickCount: Int = 0
    @State private var clickTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            VStack {
                // ーーー ヘッダー ーーー
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("相手の言語").font(.caption).foregroundColor(.secondary)
                        Picker("相手の言語", selection: $targetLanguage) {
                            ForEach(languageList, id: \.1) { language in Text(language.0).tag(language.1) }
                        }
                        .pickerStyle(MenuPickerStyle()).tint(.green).background(Color.green.opacity(0.1)).cornerRadius(8)
                    }
                    Spacer()
                    Button(action: { isPocketMode = true }) {
                        Image(systemName: "lock.fill").padding(10).background(Color.gray.opacity(0.2)).cornerRadius(20).foregroundColor(.primary)
                    }
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill").padding(10).background(Color.blue.opacity(0.1)).cornerRadius(20).foregroundColor(.blue)
                    }
                }.padding()
                
                // ーーー 履歴表示 ーーー
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            ForEach($messages) { $message in
                                SentMessageRow(message: $message, synthesizer: synthesizer).id(message.id)
                            }
                        }.padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastId = messages.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                }
                
                Spacer()
                
                // ーーー 入力エリア ーーー
                VStack(spacing: 15) {
                    if speechRecognizer.isRecording {
                        ScrollView {
                            Text(speechRecognizer.transcript.isEmpty ? "お話しください..." : speechRecognizer.transcript)
                                .foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading).padding()
                        }
                        .frame(height: 80).background(Color.red.opacity(0.1)).cornerRadius(12)
                    } else {
                        TextField("手動で入力...", text: $inputText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit { if !inputText.isEmpty { sendMessage(text: inputText); inputText = "" } }
                    }
                    
                    // ★ ボタンを押した時の動作を handleActionPress に変更
                    Button(action: { handleActionPress() }) {
                        HStack {
                            Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                            Text(speechRecognizer.isRecording ? "録音完了 (送信)" : "音声入力").fontWeight(.bold)
                        }.foregroundColor(.white).frame(maxWidth: .infinity).padding().background(speechRecognizer.isRecording ? Color.red : Color.blue).cornerRadius(12)
                    }
                }.padding().background(Color(UIColor.systemGray6))
            }
            // ★ リモコンを押した時の動作も handleActionPress に変更
            .onChange(of: volumeObserver.volume) { _, _ in handleActionPress() }
            .sheet(isPresented: $showingSettings) { ProfileSettingsView() }
            
            if isPocketMode { pocketOverlay }
        }
    }
    
    // ==========================================
    // ★ スマート・クリック検知システム（0.3秒の魔法）
    // ==========================================
    func handleActionPress() {
        clickCount += 1
        clickTask?.cancel() // 前のタイマーをキャンセル
        
        clickTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3秒間だけ待つ
                if Task.isCancelled { return } // キャンセルされたら何もしない
                
                let currentClicks = clickCount
                clickCount = 0 // 回数をリセット
                
                await MainActor.run {
                    if currentClicks == 1 {
                        // 【シングルクリックの処理】
                        if speechRecognizer.isRecording {
                            finishAndSend() // 録音中なら完了＆送信
                        } else {
                            startRecording() // 待機中なら録音開始
                        }
                    } else if currentClicks >= 2 {
                        // 【ダブルクリックの処理】
                        if speechRecognizer.isRecording {
                            cancelRecording() // 録音中ならボイクリ（キャンセル）
                        } else {
                            print("待機中のダブルクリック（将来の機能用）")
                        }
                    }
                }
            } catch { }
        }
    }
    
    // ーーー 個別の動作関数 ーーー
    
    func startRecording() {
        AudioServicesPlaySystemSound(1113) // ピッ♪
        let actualLanguage = (myLanguage == "system") ? Locale.current.identifier : myLanguage
        speechRecognizer.startTranscribing(language: actualLanguage)
    }
    
    func finishAndSend() {
        speechRecognizer.stopTranscribing()
        let finalTranscript = speechRecognizer.transcript
        
        // 念のため音声で「ボイクリ」と言った場合もキャンセルする
        if finalTranscript.contains("ボイクリ") {
            cancelRecording()
            return
        }
        
        AudioServicesPlaySystemSound(1052) // ピピッ♪
        if !finalTranscript.isEmpty {
            sendMessage(text: finalTranscript)
        }
        speechRecognizer.transcript = ""
    }
    
    func cancelRecording() {
        speechRecognizer.stopTranscribing()
        AudioServicesPlaySystemSound(1053) // キャンセル音
        
        // Siriにシステムガイドとして「ボイクリしました」と喋らせる
        let utterance = AVSpeechUtterance(string: "ボイクリしました")
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP") // ガイド音声なので常に日本語
        synthesizer.speak(utterance)
        
        speechRecognizer.transcript = "" // テキストを破棄
    }
    
    func sendMessage(text: String) {
        let actualMyLanguage = (myLanguage == "system") ? Locale.current.identifier : myLanguage
        let isSameLanguage = (actualMyLanguage.prefix(2) == targetLanguage.prefix(2))
        
        let newMessage = SentMessage(
            originalText: text,
            translatedText: isSameLanguage ? text : "翻訳中...",
            isTranslating: !isSameLanguage,
            targetLanguage: targetLanguage
        )
        messages.append(newMessage)
    }
    
    // ポケットモード表示部分
    var pocketOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 40) {
                Spacer()
                VStack(spacing: 10) {
                    Text("VoxArk").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(Color(white: 0.3))
                    Text("ポケットモード動作中...").font(.headline).foregroundColor(Color(white: 0.4))
                }
                Image(systemName: "bird.fill").resizable().scaledToFit().frame(width: 60, height: 60).foregroundColor(Color(white: 0.3)).rotation3DEffect(.degrees(birdRotation), axis: (x: 0, y: 1, z: 0)).offset(y: birdOffset).onAppear { startBirdAnimation() }
                Spacer()
                VStack(spacing: 5) {
                    Image(systemName: "hand.tap.fill").foregroundColor(Color(white: 0.4))
                    Text("解除するには画面を3秒間長押ししてください").font(.footnote).foregroundColor(Color(white: 0.4))
                }.padding(.bottom, 50)
            }
        }.onLongPressGesture(minimumDuration: 3.0) {
            AudioServicesPlaySystemSound(1052)
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            isPocketMode = false
        }
    }
    func startBirdAnimation() {
        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { birdRotation = 40.0 }
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            if isPocketMode {
                withAnimation(.interpolatingSpring(stiffness: 100, damping: 10)) { birdOffset = -20 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.interpolatingSpring(stiffness: 100, damping: 10)) { birdOffset = 0 }
                }
            }
        }
    }
}

// ーーー メッセージの吹き出し ーーー
struct SentMessageRow: View {
    @Binding var message: SentMessage
    let synthesizer: AVSpeechSynthesizer
    @State private var translationConfig: TranslationSession.Configuration?
    
    // 設定画面からデータを読み込む
    @AppStorage("myGender") var myGender: String = "female"
    @AppStorage("secondName") var secondName: String = "" // ★ 第2ネームを読み込む
    
    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                
                // ★ 1. 吹き出しの上に自分の名前（第2ネーム）を表示
                Text(secondName)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.trailing, 4)
                
                // 原文
                Text(message.originalText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                HStack(alignment: .bottom, spacing: 10) {
                    if !message.isTranslating {
                        Button(action: { speak(text: message.translatedText, language: message.targetLanguage) }) {
                            Image(systemName: "speaker.wave.2.circle.fill").resizable().frame(width: 24, height: 24).foregroundColor(.green)
                        }.padding(.bottom, 4)
                    }
                    
                    Text(message.translatedText)
                        .font(.body)
                        .padding(12)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(12)
                        // ★ 2. 長押しでコピーできるメニューを追加
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = message.originalText
                            }) {
                                Text("原文をコピー")
                                Image(systemName: "doc.on.doc")
                            }
                            
                            Button(action: {
                                UIPasteboard.general.string = message.translatedText
                            }) {
                                Text("翻訳をコピー")
                                Image(systemName: "doc.on.doc.fill")
                            }
                        }
                }
            }.padding(.leading, 50)
        }
        .onAppear {
            if message.isTranslating {
                let targetLocale = Locale.Language(identifier: message.targetLanguage)
                translationConfig = TranslationSession.Configuration(target: targetLocale)
            } else {
                speak(text: message.originalText, language: message.targetLanguage)
            }
        }
        .translationTask(translationConfig) { session in
            do {
                let response = try await session.translate(message.originalText)
                DispatchQueue.main.async {
                    message.translatedText = response.targetText
                    message.isTranslating = false
                    speak(text: response.targetText, language: message.targetLanguage)
                }
            } catch {
                DispatchQueue.main.async {
                    message.translatedText = "翻訳エラー"
                    message.isTranslating = false
                }
            }
        }
    }
    
    func speak(text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        let targetGender: AVSpeechSynthesisVoiceGender = (myGender == "male") ? .male : .female
        
        if let premiumVoice = allVoices.first(where: { $0.language == language && $0.gender == targetGender && $0.quality == .premium }) {
            utterance.voice = premiumVoice
        } else if let enhancedVoice = allVoices.first(where: { $0.language == language && $0.gender == targetGender && $0.quality == .enhanced }) {
            utterance.voice = enhancedVoice
        } else if let defaultVoice = allVoices.first(where: { $0.language == language && $0.gender == targetGender }) {
            utterance.voice = defaultVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        
        synthesizer.speak(utterance)
    }
}

