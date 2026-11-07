import SwiftUI
import UIKit

struct SwitchAccountView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var growth = GrowthStore.shared

    @State private var adding = false
    @State private var busy = ""
    @State private var note = ""

    private var me: String { app.me?.username ?? "" }

    var body: some View {
        nativeBody
    }

    private var nativeBody: some View {
        List {
            Section {
                ForEach(app.accounts) { account in
                    let current = account.username == me
                    Button {
                        guard !current else { return }
                        tap(account, current: current)
                    } label: {
                        nativeAccountRow(account)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !current {
                            Button(role: .destructive) {
                                remove(account)
                            } label: {
                                Label(Tr("从本机移除"), systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text(Tr("已登录账号"))
            } footer: {
                Text(Tr("每个账号的聊天和资料相互独立，切换后会恢复到对应账号。"))
            }

            Section {
                Button {
                    adding = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Tr("添加新账号"))
                                .font(pfStyled(size: 17))
                                .foregroundStyle(C.label)
                            Text(addSubtitle)
                                .font(pfStyled(size: 13))
                                .foregroundStyle(C.subLabel)
                        }
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(OrbitTheme.jade)
                    }
                }
                .buttonStyle(.plain)
            }

            if !note.isEmpty {
                Section {
                    Label(note, systemImage: "exclamationmark.circle.fill")
                        .font(pfStyled(size: 13))
                        .foregroundStyle(C.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(C.pageBg)
        .navigationTitle(Tr("切换账号"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(app.accounts.count)/\(AccountStore.maxCount)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .background(C.pageBg.ignoresSafeArea())
        .hidesTabBar()
        .fullScreenCover(isPresented: $adding) {
            HarmonyLoginView()
                .environmentObject(app)
        }
        .onChange(of: app.accounts.count) { _ in
            if !note.isEmpty { note = "" }
        }
    }

    private func nativeAccountRow(_ account: SavedAccount) -> some View {
        let current = account.username == me
        let loading = busy == account.username
        let tokenReady = !AccountStore.token(for: account.username).isEmpty

        return HStack(spacing: 12) {
            Avatar(path: account.avatar, size: 40, radius: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(account))
                    .font(pfStyled(size: 17))
                    .foregroundStyle(C.label)
                    .lineLimit(1)

                Text("@" + account.username)
                    .font(pfStyled(size: 13))
                    .foregroundStyle(C.subLabel)
                    .lineLimit(1)

                if !tokenReady && !current {
                    Text(Tr("登录状态已失效，点击重新登录"))
                        .font(pfStyled(size: 11))
                        .foregroundStyle(C.red.opacity(0.86))
                }
            }

            Spacer(minLength: 8)

            if loading {
                ProgressView()
                    .tint(OrbitTheme.jade)
                    .scaleEffect(0.82)
            } else if current {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OrbitTheme.jade)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.subLabel.opacity(0.72))
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private var legacyBody: some View {
        ZStack {
            StarRouteBackdrop()

            VStack(spacing: 0) {
                NavBar(title: Tr("切换账号"), back: { dismiss() }) {
                    Text("\(app.accounts.count)/\(AccountStore.maxCount)")
                        .font(pfStyled(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OrbitTheme.jade)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(Capsule().fill(OrbitTheme.jadeSoft))
                        .overlay(Capsule().stroke(OrbitTheme.jade.opacity(0.22), lineWidth: 0.7))
                        .padding(.trailing, 2)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        identityHero

                        VStack(alignment: .leading, spacing: 10) {
                            OrbitSectionLabel(text: Tr("本机账号"), count: app.accounts.count)

                            ForEach(Array(app.accounts.enumerated()), id: \.element.id) { index, account in
                                accountCard(account, index: index)
                            }

                            addCard
                        }

                        if !note.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(C.red)
                                    .padding(.top, 1)
                                Text(note)
                                    .font(pfStyled(size: 12.5))
                                    .foregroundStyle(C.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(C.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        securityNote
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, max(28, L.safeBottom))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .fullScreenCover(isPresented: $adding) {
            HarmonyLoginView()
                .environmentObject(app)
        }
        .onChange(of: app.accounts.count) { _ in
            if !note.isEmpty { note = "" }
        }
    }

    private var identityHero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.dyn(0x116C4C, 0x092B20),
                            Color.dyn(0x2DCB86, 0x155E43)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GeometryReader { geo in
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.14),
                                style: StrokeStyle(lineWidth: 0.8, dash: [2, 7]))
                        .frame(width: 180, height: 180)
                        .position(x: geo.size.width - 2, y: 6)
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.9)
                        .frame(width: 112, height: 112)
                        .position(x: geo.size.width - 4, y: 14)
                    Circle()
                        .fill(Color.white.opacity(0.60))
                        .frame(width: 4, height: 4)
                        .position(x: geo.size.width - 64, y: 32)
                }
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("IDENTITY ORBIT")
                        .font(pfStyled(size: 9.5, weight: .bold))
                        .tracking(1.25)
                    Spacer(minLength: 10)
                    Text(Tr("安全切换"))
                        .font(pfStyled(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .foregroundStyle(Color.white.opacity(0.74))

                HStack(spacing: 13) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.13))
                            .frame(width: 68, height: 68)
                        brandLogo(size: 54)
                        Circle()
                            .trim(from: 0.04, to: 0.78)
                            .stroke(Color.white.opacity(0.48),
                                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                            .frame(width: 78, height: 78)
                            .rotationEffect(.degrees(-28))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(Tr("选择你的星言身份"))
                            .font(pfStyled(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(Tr("切换后，会话和资料会回到对应账号"))
                            .font(pfStyled(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.69))
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 7) {
                    ForEach(0..<AccountStore.maxCount, id: \.self) { index in
                        Capsule()
                            .fill(index < app.accounts.count
                                  ? Color.white.opacity(index == 0 ? 0.88 : 0.46)
                                  : Color.white.opacity(0.13))
                            .frame(width: index == 0 ? 23 : 9, height: 4)
                    }
                    Text(app.accounts.isEmpty ? Tr("还没有保存账号") : Tr("左右滑动也可以切换"))
                        .font(pfStyled(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .padding(.leading, 3)
                }
            }
            .padding(16)
        }
        .frame(height: 182)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 0.8)
        }
        .shadow(color: OrbitTheme.jade.opacity(0.13), radius: 18, y: 8)
    }

    private func accountCard(_ account: SavedAccount, index: Int) -> some View {
        let current = account.username == me
        let loading = busy == account.username
        let accent = accountAccent(index)
        let tokenReady = !AccountStore.token(for: account.username).isEmpty

        return Button {
            guard !current else {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                return
            }
            tap(account, current: current)
        } label: {
            ZStack(alignment: .topTrailing) {
                if current {
                    LinearGradient(
                        colors: [
                            OrbitTheme.jade.opacity(0.22),
                            OrbitTheme.jadeDeep.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    accent.opacity(0.035)
                }

                if current {
                    Circle()
                        .stroke(Color.white.opacity(0.13),
                                style: StrokeStyle(lineWidth: 0.8, dash: [2, 5]))
                        .frame(width: 104, height: 104)
                        .offset(x: 27, y: -45)
                }

                HStack(spacing: 13) {
                    Avatar(path: account.avatar,
                           size: 54,
                           radius: 17,
                           level: levelOf(account))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(current ? OrbitTheme.jade.opacity(0.75)
                                                : OrbitTheme.divider,
                                        lineWidth: current ? 1.1 : 0.7)
                        }
                        .shadow(color: current ? OrbitTheme.jade.opacity(0.20) : .clear,
                                radius: 8,
                                y: 3)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(displayName(account))
                                .font(pfStyled(size: 16.5, weight: .semibold))
                                .foregroundStyle(OrbitTheme.ink)
                                .lineLimit(1)
                            if current {
                                Text(Tr("当前使用"))
                                    .font(pfStyled(size: 9, weight: .bold))
                                    .foregroundStyle(OrbitTheme.jade)
                                    .padding(.horizontal, 7)
                                    .frame(height: 18)
                                    .background(Capsule().fill(OrbitTheme.jadeSoft))
                                    .overlay(Capsule().stroke(OrbitTheme.jade.opacity(0.24),
                                                              lineWidth: 0.6))
                            }
                        }

                        Text("@" + account.username)
                            .font(pfStyled(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(OrbitTheme.secondary)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(current ? OrbitTheme.jade
                                      : (tokenReady ? accent : OrbitTheme.tertiary))
                                .frame(width: 5, height: 5)
                            Text(statusText(current: current,
                                            loading: loading,
                                            tokenReady: tokenReady))
                                .font(pfStyled(size: 10.5, weight: .medium))
                                .foregroundStyle(current ? OrbitTheme.jade
                                                 : (tokenReady ? OrbitTheme.secondary : C.red.opacity(0.82)))
                        }
                    }

                    Spacer(minLength: 8)

                    if loading {
                        ProgressView()
                            .tint(OrbitTheme.jade)
                            .scaleEffect(0.82)
                            .frame(width: 30, height: 30)
                    } else {
                        ZStack {
                            Circle()
                                .fill(current ? OrbitTheme.jade : OrbitTheme.field)
                                .frame(width: 31, height: 31)
                            Image(systemName: current ? "checkmark" : "arrow.up.right")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(current ? .white : OrbitTheme.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 92)
            }
            .background(OrbitTheme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(current ? OrbitTheme.jade.opacity(0.34) : OrbitTheme.divider,
                            lineWidth: current ? 1 : 0.7)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 10, y: 3)
            .opacity(busy.isEmpty || loading ? 1 : 0.58)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(StarAccountPressStyle())
        .disabled(!busy.isEmpty)
        .contextMenu {
            if !current {
                Button(role: .destructive) {
                    remove(account)
                } label: {
                    Label(Tr("从这台设备移除"), systemImage: "trash")
                }
            }
        }
    }

    private var addCard: some View {
        Button {
            adding = true
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(OrbitTheme.jadeSoft)
                        .frame(width: 54, height: 54)
                    Circle()
                        .stroke(OrbitTheme.jade.opacity(0.20),
                                style: StrokeStyle(lineWidth: 0.8, dash: [2, 4]))
                        .frame(width: 42, height: 42)
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(OrbitTheme.jade)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(Tr("添加一个星言身份"))
                        .font(pfStyled(size: 15.5, weight: .semibold))
                        .foregroundStyle(OrbitTheme.ink)
                    Text(addSubtitle)
                        .font(pfStyled(size: 11))
                        .foregroundStyle(OrbitTheme.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(OrbitTheme.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 78)
            .background(OrbitTheme.raised.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(OrbitTheme.jade.opacity(0.28),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(StarAccountPressStyle())
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OrbitTheme.jade)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(Tr("账号只保存在这台设备"))
                    .font(pfStyled(size: 11.5, weight: .semibold))
                    .foregroundStyle(OrbitTheme.secondary)
                Text(Tr("登录凭证放入本机钥匙串，切换时会先结束旧账号通话"))
                    .font(pfStyled(size: 10.5))
                    .foregroundStyle(OrbitTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(OrbitTheme.field.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OrbitTheme.divider, lineWidth: 0.6)
        }
    }

    private var addSubtitle: String {
        let left = max(0, AccountStore.maxCount - app.accounts.count)
        if left == 0 { return Tr("已保存满 3 个身份，新增时请先移除旧账号") }
        return Tr("本机还可保存") + " \(left) " + Tr("个身份")
    }

    private func accountAccent(_ index: Int) -> Color {
        switch index % 3 {
        case 1: return Color.dyn(0x3E7E98, 0x79B8D2)
        case 2: return OrbitTheme.gold
        default: return OrbitTheme.jade
        }
    }

    private func displayName(_ account: SavedAccount) -> String {
        let name = account.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? account.username : name
    }

    private func statusText(current: Bool, loading: Bool, tokenReady: Bool) -> String {
        if loading { return Tr("正在切换…") }
        if current { return Tr("消息与资料已同步") }
        if tokenReady { return Tr("登录状态已保存") }
        return Tr("需要重新登录")
    }

    @ViewBuilder
    private func brandLogo(size: CGFloat) -> some View {
        if let image = UIImage(named: "AppIcon60x60@3x")
            ?? UIImage(named: "AppIcon60x60@2x") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(OrbitTheme.jadeDeep)
                .frame(width: size, height: size)
                .overlay {
                    Text("星")
                        .font(pfStyled(size: size * 0.48, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
    }

    private func levelOf(_ account: SavedAccount) -> Int {
        if account.username == me { return max(1, growth.shownLevel) }
        if let level = app.contacts.first(where: { $0.username == account.username })?.qqLevel,
           level > 0 {
            return level
        }
        return 0
    }

    private func tap(_ account: SavedAccount, current: Bool) {
        guard !current, busy.isEmpty else { return }
        switchTo(account)
    }

    private func switchTo(_ account: SavedAccount) {
        note = ""
        busy = account.username
        Task {
            let saved = AccountStore.token(for: account.username)
            guard !saved.isEmpty else {
                busy = ""
                note = Tr("这个账号的登录状态过期了，重新输一次密码就行")
                adding = true
                return
            }
            let ok = await app.quickLogin(token: saved,
                                          username: account.username,
                                          switchingAccount: true)
            busy = ""
            if ok {
                dismiss()
            } else {
                note = Tr("这个账号的登录状态过期了，重新输一次密码就行")
                adding = true
            }
        }
    }

    private func remove(_ account: SavedAccount) {
        AccountStore.remove(username: account.username)
        app.accounts = AccountStore.load()
        app.show(Tr("已移除") + "「" + displayName(account) + "」")
    }
}

private struct StarAccountPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
