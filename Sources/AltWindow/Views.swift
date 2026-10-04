import AppKit
import SwiftUI

final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowItem] = []
    @Published var selected = 0
    @Published var columns = 4
    @Published var previewHeight: CGFloat = 168
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var thumbnailStates: [String: ThumbnailState] = [:]
    var choose: (Int) -> Void = { _ in }
    var requestPreview: (String) -> Void = { _ in }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: model.columns), spacing: 12) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, item in
                        card(item, selected: index == model.selected)
                            .id(index)
                            .onTapGesture { model.choose(index) }
                            .onAppear { model.requestPreview(item.id) }
                    }
                }.padding(3)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selected) { _, index in
                if model.windows.indices.contains(index) { model.requestPreview(model.windows[index].id) }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) { proxy.scrollTo(index, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(model.selected, anchor: .center) }
        }
        .padding(13)
    }

    func card(_ item: WindowItem, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(nsImage: item.icon).resizable().frame(width: 16, height: 16)
                Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if item.minimized { Image(systemName: "minus.rectangle").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 10).padding(.vertical, 8)
            ZStack {
                Color.primary.opacity(0.025)
                if let image = model.thumbnails[item.id] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(4)
                } else {
                    VStack(spacing: 8) {
                        Image(nsImage: item.icon).resizable().frame(width: 44, height: 44)
                        let state = model.thumbnailStates[item.id] ?? .loading
                        if state != .demo {
                            Text(state.label).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(height: model.previewHeight).clipped().padding(6)
        }
        .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.appName)、\(item.title)\(selected ? "、選択中" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if let index = model.windows.firstIndex(where: { $0.id == item.id }) { model.choose(index) } }
    }

}

final class PermissionModel: ObservableObject {
    @Published var accessibility = false
    @Published var keyboard = false
    @Published var capture = false
    var enableAX: () -> Void = {}
    var enableKeyboard: () -> Void = {}
    var enableCapture: () -> Void = {}
    var preview: () -> Void = {}
}

struct SettingsView: View {
    @ObservedObject var model: PermissionModel
    @ObservedObject var loginItem: LoginItemController
    @AppStorage("thumbnailSize") private var thumbnailSize = ThumbnailSize.medium.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text("AltWindow").font(.system(size: 28, weight: .bold))
                    Text("いつもの切り替えを、Macでも。").foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("⌥ option").font(.system(size: 22, weight: .medium, design: .rounded))
                Text("+").foregroundStyle(.secondary)
                Text("tab ⇥").font(.system(size: 22, weight: .medium, design: .rounded))
                Spacer()
                Text("押して選択、離して確定").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(20).modifier(GlassControl(active: true))
            Picker("サムネイルの大きさ", selection: $thumbnailSize) {
                ForEach(ThumbnailSize.allCases, id: \.rawValue) { size in
                    Text(size.label).tag(size.rawValue)
                }
            }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 9) {
                Toggle("ログイン時にバックグラウンドで起動", isOn: Binding(
                    get: { loginItem.isRegistered },
                    set: { enabled in Task { await loginItem.setEnabled(enabled) } }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 13, weight: .semibold))
                .disabled(loginItem.isChanging)
                Text("設定画面を開かず、メニューバーに常駐します。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    Text(loginItem.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(loginItem.errorMessage != nil ? Color.red : Color.secondary)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Button("ログイン項目を開く") { loginItem.openSettings() }.controlSize(.small)
                }.frame(height: 30, alignment: .top)
            }
            Divider()
            VStack(spacing: 18) {
                permissionRow("アクセシビリティ", detail: "ウィンドウの一覧取得と切り替えに必要です。", enabled: model.accessibility, action: model.enableAX)
                Divider()
                permissionRow("キーボード入力", detail: "Option＋Tabの検出。必要に応じて入力監視を許可します。", enabled: model.keyboard, action: model.enableKeyboard)
                Divider()
                permissionRow("プレビュー画像（任意）", detail: "画面収録を許可するとウィンドウ画像を表示します。", enabled: model.capture, action: model.enableCapture)
            }
            Text("Shiftで逆順 · 矢印キーで移動 · Escでキャンセル\n最小化したウィンドウも選択できます。画像は保存・送信しません。")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            HStack {
                Circle().fill(model.keyboard && model.accessibility ? .green : .orange).frame(width: 7, height: 7)
                Text(model.keyboard && model.accessibility ? "準備完了 · メニューバーで動作中" : "権限の設定を完了してください").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("デモを表示", action: model.preview)
            }
        }.padding(32).padding(.top, 16).frame(width: 580)
    }
    func permissionRow(_ title: String, detail: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(enabled ? .green : .gray).font(.system(size: 19))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(enabled ? "設定" : "許可", action: action).controlSize(.small)
        }
    }
}
