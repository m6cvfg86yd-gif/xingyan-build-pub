import SwiftUI

struct PayPasswordView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Step { case old, new1, new2 }

    @State private var hasPwd = false
    @State private var loaded = false
    @State private var step: Step = .new1
    @State private var input = ""
    @State private var firstNew = ""
    @State private var oldPwd = ""
    @State private var hint: String?
    @State private var shake = false
    @State private var busy = false
    @FocusState private var focus: Bool

    private var title: String {
        switch step {
        case .old:  return "请输入原支付密码"
        case .new1: return hasPwd ? "请输入新的支付密码" : "请设置 6 位支付密码"
        case .new2: return "请再次输入确认"
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Text(title)
                        .font(.headline)

                    cells

                    if let hint = hint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: 0xE5484D))
                            .multilineTextAlignment(.center)
                    } else {
                        Text(Tr("支付密码是 6 位数字，转账付款时要输它确认"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    TextField("", text: $input)
                        .keyboardType(.numberPad)
                        .focused($focus)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .onChange(of: input) { v in
                            let clean = String(v.filter { $0 >= "0" && $0 <= "9" }.prefix(6))
                            if clean != v { input = clean; return }
                            hint = nil
                            if clean.count == 6 { advance() }
                        }
                        .onAppear { focusSoon() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }

            Section {
                LabeledContent(Tr("当前状态"),
                               value: hasPwd ? Tr("已设置支付密码") : Tr("还没有设置支付密码"))
            } footer: {
                Text(Tr("支付密码只用于转账和付款确认，不会作为登录密码。"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Tr("支付密码"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .hidesTabBar()
        .overlay {
            if busy {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView()
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                        )
                }
            }
        }
        .task {
            guard !loaded else { return }
            hasPwd = await API.shared.hasPayPassword()
            step = hasPwd ? .old : .new1
            loaded = true
        }
    }

    private var cells: some View {
        PayDotField(count: input.count, shake: shake ? -6 : 0,
                    busy: busy, height: 48)
            .contentShape(Rectangle())
            .onTapGesture { focus = true }
    }

    private func focusSoon() {
        Task {
            focus = true
            for delay in [280_000_000, 480_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))
                if Task.isCancelled { return }
                if !focus && input.isEmpty { focus = true }
            }
        }
    }

    private func advance() {
        switch step {
        case .old:
            checkOld()
        case .new1:
            firstNew = input
            input = ""
            step = .new2
            focusSoon()
        case .new2:
            finish()
        }
    }

    private func checkOld() {
        let code = input
        busy = true
        Task {
            do {
                try await API.shared.verifyPayPassword(code)
                oldPwd = code
                input = ""
                step = .new1
                hint = nil
                busy = false
                focusSoon()
            } catch {
                busy = false
                fail((error as? APIError)?.errorDescription ?? "原支付密码不正确")
            }
        }
    }

    private func finish() {
        guard input == firstNew else {
            fail("两次输入不一样，重新输一遍")
            firstNew = ""
            step = .new1
            return
        }
        let code = input
        busy = true
        Task {
            do {
                try await API.shared.setPayPassword(code, current: oldPwd)
                NotificationCenter.default.post(name: .chrisUIPrefsChanged, object: nil)
                busy = false
                app.show(hasPwd ? "支付密码改好了" : "支付密码设好了")
                dismiss()
            } catch {
                busy = false
                fail((error as? APIError)?.errorDescription ?? "设置失败，再试一次")
            }
        }
    }

    private func fail(_ message: String) {
        hint = message
        input = ""
        shake = true
        focus = true
        Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            shake = false
        }
    }
}
