import SwiftUI
import Foundation
import AppKit

// PlayCap - parent control panel
// Reads via ctl.sh status --raw (no privileges needed).
// Changes run through "do shell script ... with administrator privileges",
// so macOS shows an admin auth dialog = standard users (kids) cannot change settings.

// Overridable for development/screenshots (PLAYCAP_CTL / PLAYCAP_USAGE_LOG)
let ctlPath = ProcessInfo.processInfo.environment["PLAYCAP_CTL"]
    ?? "/usr/local/libexec/playcap/ctl.sh"
let usageLogPath = ProcessInfo.processInfo.environment["PLAYCAP_USAGE_LOG"]
    ?? "/Library/Application Support/PlayCap/usage.log"

// ---- localization ----
let isJa = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false

struct T {
    static var todayStatus: String { isJa ? "今日の使用状況" : "Today" }
    static var running: String { isJa ? "ゲーム起動中" : "Game running" }
    static var notRunning: String { isJa ? "ゲーム停止中" : "No game running" }
    static var limitsOn: String { isJa ? "制限 ON" : "Limits ON" }
    static var limitsOff: String { isJa ? "制限 OFF" : "Limits OFF" }
    static func usage(_ used: String, _ limit: Int, _ remain: String) -> String {
        isJa ? "使用 \(used) / 上限 \(limit)分（残り \(remain)）"
             : "\(used) used / \(limit) min limit (\(remain) left)"
    }
    static func bonus(_ b: String) -> String { isJa ? "今日のボーナス +\(b)" : "Today's bonus +\(b)" }
    static var settings: String { isJa ? "設定（変更には管理者パスワードが必要）" : "Settings (admin password required to change)" }
    static var enableLimits: String { isJa ? "制限を有効にする" : "Enable limits" }
    static var weekdayLimit: String { isJa ? "平日の上限" : "Weekday limit" }
    static var weekendLimit: String { isJa ? "休日（土日）の上限" : "Weekend limit" }
    static var allowedHours: String { isJa ? "利用できる時間帯" : "Allowed hours" }
    static var monitoredApps: String { isJa ? "監視するアプリ" : "Monitored apps" }
    static var monitoredAppsHint: String {
        isJa ? "プロセス名をカンマ区切りで（例: roblox,minecraft）"
             : "Comma-separated process names (e.g. roblox,minecraft)"
    }
    static var monitoredUser: String { isJa ? "対象アカウント" : "Monitored account" }
    static var save: String { isJa ? "設定を保存" : "Save settings" }
    static var bonusButton: String { isJa ? "今日だけ +30分" : "+30 min today" }
    static var history: String { isJa ? "最近7日の使用" : "Last 7 days" }
    static var minUnit: String { isJa ? "分" : "min" }
    static var notInstalled: String {
        isJa ? "PlayCap が未インストールです。\nInstall.command を先に実行してください。"
             : "PlayCap is not installed.\nPlease run Install.command first."
    }
    static var loading: String { isJa ? "読み込み中…" : "Loading…" }
    static var errorTitle: String { isJa ? "エラー" : "Error" }
    static var invalidTime: String {
        isJa ? "時間帯は HH:MM 形式で入力してください（例: 07:00）"
             : "Please enter times in HH:MM format (e.g. 07:00)"
    }
    static var invalidTargets: String {
        isJa ? "監視アプリは英数字・カンマで入力してください（例: roblox,minecraft）"
             : "Monitored apps must be letters/digits separated by commas (e.g. roblox,minecraft)"
    }
    static func saveFailed(_ e: String) -> String { isJa ? "設定の保存に失敗しました: \(e)" : "Failed to save settings: \(e)" }
    static func bonusFailed(_ e: String) -> String { isJa ? "延長に失敗しました: \(e)" : "Failed to add bonus: \(e)" }
    static var saved: String { isJa ? "保存しました" : "Saved" }
    static func bonusAdded(_ m: Int) -> String { isJa ? "+\(m)分 延長しました" : "Added \(m) min" }
}

func fmtMin(_ sec: Int) -> String { "\(sec / 60)\(T.minUnit)" }

// ---- data access ----
struct RawStatus {
    var enabled = true
    var weekdayMin = 120
    var weekendMin = 180
    var allowedStart = "07:00"
    var allowedEnd = "21:00"
    var targetUser = ""
    var targets = "roblox"
    var usedSec = 0
    var bonusSec = 0
    var limitTodayMin = 0
    var remainSec = 0
    var running = false
}

func runProcess(_ exe: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard p.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}

func fetchStatus() -> RawStatus? {
    guard let out = runProcess("/bin/bash", [ctlPath, "status", "--raw"]) else { return nil }
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
        case "targets":           s.targets = v
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

func fetchLocalUsers() -> [String] {
    guard let out = runProcess("/usr/bin/dscl", [".", "-list", "/Users"]) else { return [] }
    let system = Set(["root", "daemon", "nobody"])
    return out.split(separator: "\n").map(String.init)
        .filter { !$0.hasPrefix("_") && !system.contains($0) }
        .sorted()
}

struct DayUsage: Identifiable {
    let id: String   // date
    let minutes: Int
}

func fetchHistory() -> [DayUsage] {
    guard let text = try? String(contentsOfFile: usageLogPath, encoding: .utf8) else { return [] }
    var rows: [DayUsage] = []
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: " ")
        guard parts.count == 2, parts[1].hasPrefix("used_min="),
              let m = Int(parts[1].dropFirst("used_min=".count)) else { continue }
        rows.append(DayUsage(id: String(parts[0]), minutes: m))
    }
    return Array(rows.suffix(7))
}

// Run a command with admin authentication. Returns nil on success, error text on failure.
func runAsAdmin(_ command: String) -> String? {
    let escaped = command
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let src = "do shell script \"\(escaped)\" with administrator privileges"
    var err: NSDictionary?
    NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err = err {
        let num = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
        if num == -128 { return nil }  // user cancelled the auth dialog: not an error
        return (err["NSAppleScriptErrorMessage"] as? String) ?? "unknown error"
    }
    return nil
}

// Development helper: with PLAYCAP_SNAPSHOT=<path> set, the app renders its own
// window to a PNG and exits (used to produce store/README screenshots; needs no
// screen-recording permission because it draws its own view hierarchy).
func saveSnapshotAndExit(_ path: String) {
    guard let window = NSApp.windows.first, let view = window.contentView,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { exit(1) }
    exit(0)
}

// ---- UI ----
struct ContentView: View {
    @State private var status: RawStatus? = nil
    @State private var loadFailed = false
    @State private var users: [String] = []
    @State private var history: [DayUsage] = []

    // editable fields
    @State private var enabled = true
    @State private var weekdayMin = 120
    @State private var weekendMin = 180
    @State private var allowedStart = "07:00"
    @State private var allowedEnd = "21:00"
    @State private var targets = "roblox"
    @State private var selectedUser = ""

    @State private var message = ""
    @State private var errorMessage = ""

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = status {
                statusBox(s)
                settingsBox
                if !history.isEmpty { historyBox }
                HStack {
                    Text("\(T.monitoredUser): \(s.targetUser)")
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
                    Text(loadFailed ? T.notInstalled : T.loading)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            users = fetchLocalUsers()
            reload(applyToForm: true)
            if let snap = ProcessInfo.processInfo.environment["PLAYCAP_SNAPSHOT"] {
                // Fixed appearance so store screenshots don't depend on the host's dark mode
                let ap = ProcessInfo.processInfo.environment["PLAYCAP_APPEARANCE"] ?? "light"
                NSApp.appearance = NSAppearance(named: ap == "dark" ? .darkAqua : .aqua)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveSnapshotAndExit(snap) }
            }
        }
        .onReceive(timer) { _ in reload(applyToForm: false) }
        .alert(T.errorTitle, isPresented: .constant(!errorMessage.isEmpty)) {
            Button("OK") { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

    func statusBox(_ s: RawStatus) -> some View {
        GroupBox(label: Label(T.todayStatus, systemImage: "clock")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(s.running ? Color.green : Color.gray)
                        .frame(width: 9, height: 9)
                    Text(s.running ? T.running : T.notRunning)
                    Spacer()
                    Text(s.enabled ? T.limitsOn : T.limitsOff)
                        .font(.caption).bold()
                        .foregroundColor(s.enabled ? .green : .orange)
                }
                ProgressView(value: Double(min(s.usedSec, s.limitTodayMin * 60)),
                             total: Double(max(s.limitTodayMin * 60, 1)))
                Text(T.usage(fmtMin(s.usedSec), s.limitTodayMin, fmtMin(s.remainSec)))
                    .font(.callout)
                if s.bonusSec > 0 {
                    Text(T.bonus(fmtMin(s.bonusSec)))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var settingsBox: some View {
        GroupBox(label: Label(T.settings, systemImage: "lock")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(T.enableLimits, isOn: $enabled)
                HStack {
                    Text(T.weekdayLimit)
                    Spacer()
                    Stepper("\(weekdayMin)\(T.minUnit)", value: $weekdayMin, in: 0...720, step: 15)
                        .frame(width: 150)
                }
                HStack {
                    Text(T.weekendLimit)
                    Spacer()
                    Stepper("\(weekendMin)\(T.minUnit)", value: $weekendMin, in: 0...720, step: 15)
                        .frame(width: 150)
                }
                HStack {
                    Text(T.allowedHours)
                    Spacer()
                    TextField("07:00", text: $allowedStart)
                        .frame(width: 60).multilineTextAlignment(.center)
                    Text("-")
                    TextField("21:00", text: $allowedEnd)
                        .frame(width: 60).multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(T.monitoredApps)
                        Spacer()
                        TextField("roblox", text: $targets)
                            .frame(width: 200)
                    }
                    Text(T.monitoredAppsHint)
                        .font(.caption2).foregroundColor(.secondary)
                }
                if !users.isEmpty {
                    HStack {
                        Text(T.monitoredUser)
                        Spacer()
                        Picker("", selection: $selectedUser) {
                            ForEach(users, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
                HStack {
                    Button(T.save) { saveSettings() }
                        .keyboardShortcut(.defaultAction)
                    Spacer()
                    Button(T.bonusButton) { addBonus(30) }
                }
            }
            .padding(6)
        }
    }

    var historyBox: some View {
        GroupBox(label: Label(T.history, systemImage: "chart.bar")) {
            let maxMin = max(history.map(\.minutes).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(history) { day in
                    HStack(spacing: 8) {
                        Text(day.id).font(.caption.monospaced())
                        ProgressView(value: Double(day.minutes), total: Double(maxMin))
                        Text("\(day.minutes)\(T.minUnit)")
                            .font(.caption.monospaced())
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .padding(6)
        }
    }

    func reload(applyToForm: Bool) {
        history = fetchHistory()
        if let s = fetchStatus() {
            status = s
            loadFailed = false
            if applyToForm {
                enabled = s.enabled
                weekdayMin = s.weekdayMin
                weekendMin = s.weekendMin
                allowedStart = s.allowedStart
                allowedEnd = s.allowedEnd
                targets = s.targets
                selectedUser = s.targetUser
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

    func validTargets(_ t: String) -> Bool {
        !t.isEmpty && t.range(of: "^[A-Za-z0-9_,.-]+$", options: .regularExpression) != nil
    }

    func saveSettings() {
        guard validHHMM(allowedStart), validHHMM(allowedEnd) else {
            errorMessage = T.invalidTime
            return
        }
        guard validTargets(targets) else {
            errorMessage = T.invalidTargets
            return
        }
        var parts = [
            "'\(ctlPath)' \(enabled ? "enable" : "disable")",
            "'\(ctlPath)' set-weekday \(weekdayMin)",
            "'\(ctlPath)' set-weekend \(weekendMin)",
            "'\(ctlPath)' set-curfew \(allowedStart) \(allowedEnd)",
            "'\(ctlPath)' set-targets \(targets)",
        ]
        if !selectedUser.isEmpty && selectedUser != status?.targetUser {
            parts.append("'\(ctlPath)' set-user \(selectedUser)")
        }
        if let err = runAsAdmin(parts.joined(separator: " && ")) {
            errorMessage = T.saveFailed(err)
        } else {
            flashMessage(T.saved)
        }
        reload(applyToForm: true)
    }

    func addBonus(_ min: Int) {
        if let err = runAsAdmin("'\(ctlPath)' add-bonus \(min)") {
            errorMessage = T.bonusFailed(err)
        } else {
            flashMessage(T.bonusAdded(min))
        }
        reload(applyToForm: false)
    }

    func flashMessage(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { message = "" }
    }
}

@main
struct PlayCapApp: App {
    var body: some Scene {
        WindowGroup("PlayCap") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
