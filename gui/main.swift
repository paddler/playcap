import SwiftUI
import Foundation

// Roblox Limit - 親用設定パネル
// 参照は ctl.sh status --raw を直接実行（権限不要）。
// 変更は "do shell script ... with administrator privileges" 経由で
// macOS の管理者認証ダイアログを挟む = 標準ユーザー（子供）は変更不可。

let ctlPath = "/usr/local/libexec/roblox-limit/ctl.sh"

struct RawStatus {
    var enabled = true
    var weekdayMin = 120
    var weekendMin = 180
    var allowedStart = "07:00"
    var allowedEnd = "21:00"
    var targetUser = ""
    var usedSec = 0
    var bonusSec = 0
    var limitTodayMin = 0
    var remainSec = 0
    var running = false
}

func fetchStatus() -> RawStatus? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [ctlPath, "status", "--raw"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard p.terminationStatus == 0, let out = String(data: data, encoding: .utf8) else { return nil }

    var s = RawStatus()
    for line in out.split(separator: "\n") {
        let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard kv.count == 2 else { continue }
        let v = kv[1]
        switch kv[0] {
        case "enabled":           s.enabled = (v == "1")
        case "weekday_limit_min": s.weekdayMin = Int(v) ?? s.weekdayMin
        case "weekend_limit_min": s.weekendMin = Int(v) ?? s.weekendMin
        case "allowed_start":     s.allowedStart = v
        case "allowed_end":       s.allowedEnd = v
        case "target_user":       s.targetUser = v
        case "used_sec":          s.usedSec = Int(v) ?? 0
        case "bonus_sec":         s.bonusSec = Int(v) ?? 0
        case "limit_today_min":   s.limitTodayMin = Int(v) ?? 0
        case "remain_sec":        s.remainSec = Int(v) ?? 0
        case "running":           s.running = (v == "1")
        default: break
        }
    }
    return s
}

// 管理者認証つきでコマンドを実行。成功なら nil、失敗ならエラーメッセージを返す
func runAsAdmin(_ command: String) -> String? {
    let escaped = command
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let src = "do shell script \"\(escaped)\" with administrator privileges"
    var err: NSDictionary?
    NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err = err {
        let num = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
        if num == -128 { return nil }  // ユーザーがダイアログをキャンセル → エラー扱いにしない
        return (err["NSAppleScriptErrorMessage"] as? String) ?? "不明なエラー"
    }
    return nil
}

func fmtMin(_ sec: Int) -> String { "\(sec / 60)分" }

struct ContentView: View {
    @State private var status: RawStatus? = nil
    @State private var loadFailed = false

    // 編集用フィールド
    @State private var enabled = true
    @State private var weekdayMin = 120
    @State private var weekendMin = 180
    @State private var allowedStart = "07:00"
    @State private var allowedEnd = "21:00"

    @State private var message = ""
    @State private var errorMessage = ""

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = status {
                GroupBox(label: Label("今日の使用状況", systemImage: "clock")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(s.running ? Color.green : Color.gray)
                                .frame(width: 9, height: 9)
                            Text(s.running ? "Roblox 起動中" : "Roblox 停止中")
                            Spacer()
                            Text(s.enabled ? "制限 ON" : "制限 OFF")
                                .font(.caption).bold()
                                .foregroundColor(s.enabled ? .green : .orange)
                        }
                        ProgressView(value: Double(min(s.usedSec, s.limitTodayMin * 60)),
                                     total: Double(max(s.limitTodayMin * 60, 1)))
                        Text("使用 \(fmtMin(s.usedSec)) / 上限 \(s.limitTodayMin)分（残り \(fmtMin(s.remainSec))）")
                            .font(.callout)
                        if s.bonusSec > 0 {
                            Text("今日のボーナス +\(fmtMin(s.bonusSec))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Label("設定（変更には管理者パスワードが必要）", systemImage: "lock")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("制限を有効にする", isOn: $enabled)
                        HStack {
                            Text("平日の上限")
                            Spacer()
                            Stepper("\(weekdayMin)分", value: $weekdayMin, in: 0...720, step: 15)
                                .frame(width: 140)
                        }
                        HStack {
                            Text("休日（土日）の上限")
                            Spacer()
                            Stepper("\(weekendMin)分", value: $weekendMin, in: 0...720, step: 15)
                                .frame(width: 140)
                        }
                        HStack {
                            Text("利用できる時間帯")
                            Spacer()
                            TextField("07:00", text: $allowedStart)
                                .frame(width: 60).multilineTextAlignment(.center)
                            Text("〜")
                            TextField("21:00", text: $allowedEnd)
                                .frame(width: 60).multilineTextAlignment(.center)
                        }
                        HStack {
                            Button("設定を保存") { saveSettings() }
                                .keyboardShortcut(.defaultAction)
                            Spacer()
                            Button("今日だけ +30分") { addBonus(30) }
                        }
                    }
                    .padding(6)
                }

                HStack {
                    Text("対象アカウント: \(s.targetUser)")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundColor(.green)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text(loadFailed
                         ? "Roblox Limit が未インストールです。\nsudo ./install.sh を先に実行してください。"
                         : "読み込み中…")
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(16)
        .frame(width: 400)
        .onAppear { reload(applyToForm: true) }
        .onReceive(timer) { _ in reload(applyToForm: false) }
        .alert("エラー", isPresented: .constant(!errorMessage.isEmpty)) {
            Button("OK") { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

    func reload(applyToForm: Bool) {
        if let s = fetchStatus() {
            status = s
            loadFailed = false
            if applyToForm {
                enabled = s.enabled
                weekdayMin = s.weekdayMin
                weekendMin = s.weekendMin
                allowedStart = s.allowedStart
                allowedEnd = s.allowedEnd
            }
        } else {
            status = nil
            loadFailed = true
        }
    }

    func validHHMM(_ t: String) -> Bool {
        let parts = t.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return h >= 0 && h <= 23 && m >= 0 && m <= 59
    }

    func saveSettings() {
        guard validHHMM(allowedStart), validHHMM(allowedEnd) else {
            errorMessage = "時間帯は HH:MM 形式で入力してください（例: 07:00）"
            return
        }
        let cmd = [
            "'\(ctlPath)' \(enabled ? "enable" : "disable")",
            "'\(ctlPath)' set-weekday \(weekdayMin)",
            "'\(ctlPath)' set-weekend \(weekendMin)",
            "'\(ctlPath)' set-curfew \(allowedStart) \(allowedEnd)",
        ].joined(separator: " && ")
        if let err = runAsAdmin(cmd) {
            errorMessage = "設定の保存に失敗しました: \(err)"
        } else {
            flashMessage("保存しました")
        }
        reload(applyToForm: true)
    }

    func addBonus(_ min: Int) {
        if let err = runAsAdmin("'\(ctlPath)' add-bonus \(min)") {
            errorMessage = "延長に失敗しました: \(err)"
        } else {
            flashMessage("+\(min)分 延長しました")
        }
        reload(applyToForm: false)
    }

    func flashMessage(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { message = "" }
    }
}

@main
struct RobloxLimitApp: App {
    var body: some Scene {
        WindowGroup("Roblox Limit") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
