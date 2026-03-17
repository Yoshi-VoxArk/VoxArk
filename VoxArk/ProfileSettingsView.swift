import SwiftUI

struct ProfileSettingsView: View {
    // チャット画面に戻るための機能
    @Environment(\.dismiss) var dismiss
    
    // アプリ内に自動保存されるメタデータ（初期値も設定）
    @AppStorage("firstName") var firstName: String = ""
    @AppStorage("secondName") var secondName: String = ""
    @AppStorage("myGender") var myGender: String = "female" // 初期値は女性
    @AppStorage("myLanguage") var myLanguage: String = "system" // 初期値はシステム言語
    
    let languageList = [
        ("⚙️ システム言語", "system"),
        ("🇯🇵 日本語", "ja-JP"),
        ("🇺🇸 英語 (米国)", "en-US"),
        ("🇬🇧 英語 (英国)", "en-GB"),
        ("🇨🇳 中国語", "zh-CN"),
        ("🇰🇷 韓国語", "ko-KR"),
        ("🇪🇸 スペイン語", "es-ES"),
        ("🇫🇷 フランス語", "fr-FR"),
        ("🇹🇭 タイ語", "th-TH")
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("プロフィール設定"), footer: Text("第2ネームは、まだ友達承認していない相手に表示される匿名ネームです。")) {
                    TextField("第1ネーム (友達用 / 実名など)", text: $firstName)
                    TextField("第2ネーム (捨て垢用)", text: $secondName)
                }
                
                Section(header: Text("音声と言語のメタデータ")) {
                    Picker("あなたの性別 (Siri音声用)", selection: $myGender) {
                        Text("女性").tag("female")
                        Text("男性").tag("male")
                    }
                    
                    Picker("あなたの使用言語", selection: $myLanguage) {
                        ForEach(languageList, id: \.1) { lang in
                            Text(lang.0).tag(lang.1)
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("チャットへ戻る") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                // 初回起動時、第2ネームが空っぽなら「動物＋4桁」を自動生成する
                if secondName.isEmpty {
                    secondName = generateRandomSecondName()
                }
            }
        }
    }
    
    // ランダムな第2ネームを生成する関数
    func generateRandomSecondName() -> String {
        let animals = ["ネコ", "イヌ", "ウサギ", "クマ", "キツネ", "パンダ", "ペンギン", "フクロウ"]
        let randomAnimal = animals.randomElement() ?? "ネコ"
        let randomNumber = Int.random(in: 1000...9999)
        return "\(randomAnimal)\(randomNumber)"
    }
}

#Preview {
    ProfileSettingsView()
}

