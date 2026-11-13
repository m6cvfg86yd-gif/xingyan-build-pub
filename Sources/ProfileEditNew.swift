import SwiftUI

struct ProfileEditView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var growth = GrowthStore.shared

    @State private var nickname = ""
    @ObservedObject private var ring = Ringtone.shared
    @State private var showRingtone = false
    @State private var bio = ""
    @State private var region = ""
    @State private var gender = "male"
    @State private var phone = ""
    @State private var birthday = ""
    @State private var showBirthday = false
    @State private var showRegion = false

    @State private var showGender = false
    @State private var showPhone = false
    @State private var showPhoto = false
    @State private var busy = false
    @State private var cropImage: UIImage?

    @State private var patText = ""
    @State private var showMyQR = false

    @State private var showUsername = false

    @State private var baselineProfile: [String: String] = [:]

    private let gold = Color(hex: 0xF0C24B)

    var body: some View {
        Form {
            Section {
                Button { showPhoto = true } label: {
                    HStack(spacing: 12) {
                        Text(Tr("头像"))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        Avatar(path: app.me?.avatarPath ?? "", size: 44, radius: 8,
                               circle: false, level: growth.shownLevel)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                LabeledContent(Tr("昵称")) {
                    TextField("", text: $nickname)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                }

                nativeValueRow(Tr("星言号"),
                               (app.me?.username?.isEmpty == false) ? (app.me?.username ?? "—") : "—") {
                    showUsername = true
                }
                nativeValueRow(Tr("性别"), gender == "female" ? Tr("女") : Tr("男")) {
                    showGender = true
                }
                nativeValueRow(Tr("地区"), region.isEmpty ? Tr("未设置") : region) {
                    showRegion = true
                }
                nativeValueRow(Tr("生日"), birthday.isEmpty ? Tr("未设置") : birthday) {
                    showBirthday = true
                }
            } header: {
                Text(Tr("基本资料"))
            } footer: {
                Text(Tr("昵称最多 16 个字符；星言号一年最多修改 2 次。"))
            }

            Section {
                LabeledContent(Tr("星语提示")) {
                    TextField(Tr("收到一束星光"), text: $patText)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: patText) { v in
                            if v.count > 10 { patText = String(v.prefix(10)) }
                        }
                }

                LabeledContent(Tr("个性签名")) {
                    TextField(Tr("写一句介绍自己"), text: $bio)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text(Tr("个人介绍"))
            } footer: {
                Text(Tr("好友向你发送星语时显示这句提示，最多 10 个字；留空显示「你收到一束星光」。"))
            }

            Section {
                nativeValueRow(Tr("手机号"), phone.isEmpty ? Tr("未绑定") : maskPhone(phone)) {
                    showPhone = true
                }
                nativeValueRow(Tr("来电铃声"), ring.currentName) {
                    showRingtone = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Tr("个人信息"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(busy ? Tr("保存中…") : Tr("保存")) { save() }
                    .disabled(busy)
            }
        }
        .hidesTabBar()
        .onAppear { fillFromMe(force: true) }

        .onChange(of: app.me) { _ in fillFromMe(force: false) }
        .sheet(isPresented: $showPhoto) { PhotoPicker { image in cropImage = image } }
        .sheet(isPresented: Binding(get: { cropImage != nil },
                                    set: { if !$0 { cropImage = nil } })) {
            if let img = cropImage {
                AvatarCropSheet(image: img) { cropped in
                    changeAvatar(cropped)
                    cropImage = nil
                }
            }
        }

        .navigationDestination(isPresented: $showRegion) {
            RegionPickerSheet { r in region = r }
        }
        .navigationDestination(isPresented: $showBirthday) {
            BirthdayPickerSheet(birthday: $birthday)
        }
        .navigationDestination(isPresented: $showPhone) {
            PhoneChangeSheet().environmentObject(app)
        }
        .navigationDestination(isPresented: $showRingtone) {
            RingtonePicker()
        }
        .navigationDestination(isPresented: $showMyQR) {
            MyQRView()
        }
        .navigationDestination(isPresented: $showUsername) {
            UsernameChangeSheet().environmentObject(app)
        }

        .confirmationDialog(Tr("性别"), isPresented: $showGender, titleVisibility: .visible) {
            Button(Tr("男")) { gender = "male"; saveNow(["gender": "male"]) }
            Button(Tr("女")) { gender = "female"; saveNow(["gender": "female"]) }
            Button(Tr("取消"), role: .cancel) { }
        }

        .onChange(of: region) { v in
            if v != (app.me?.region ?? "") { saveNow(["region": v]) }
        }
        .onChange(of: birthday) { v in
            if v != (app.me?.birthday ?? "") { saveNow(["birthday": v]) }
        }
    }

    private func nativeValueRow(_ title: String, _ value: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func fillFromMe(force: Bool) {
        guard let me = app.me else { return }
        let remote = [
            "nickname": me.nickname ?? "",
            "bio": me.bio ?? "",
            "region": me.region ?? "",
            "gender": me.gender == "female" ? "female" : "male",
            "phone": me.phone ?? "",
            "birthday": me.birthday ?? "",
            "patText": me.patText ?? ""
        ]
        if !force, !baselineProfile.isEmpty {
            let untouched = nickname == (baselineProfile["nickname"] ?? "")
                && bio == (baselineProfile["bio"] ?? "")
                && region == (baselineProfile["region"] ?? "")
                && gender == (baselineProfile["gender"] ?? "")
                && phone == (baselineProfile["phone"] ?? "")
                && birthday == (baselineProfile["birthday"] ?? "")
                && patText == (baselineProfile["patText"] ?? "")
            guard untouched else { return }
        }
        baselineProfile = remote
        nickname = remote["nickname"] ?? ""
        bio = remote["bio"] ?? ""
        region = remote["region"] ?? ""
        gender = remote["gender"] ?? "male"
        phone = remote["phone"] ?? ""
        birthday = remote["birthday"] ?? ""
        patText = remote["patText"] ?? ""
    }

    private func saveNow(_ fields: [String: Any]) {
        Task {
            do {
                if let updated = try await API.shared.updateMeChecked(fields) {
                    app.applyMyProfileUser(updated)
                } else {
                    app.applyMyProfileFields(fields)
                }
            } catch {
                app.show(error.localizedDescription)
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Button { showPhoto = true } label: {
                    Avatar(path: app.me?.avatarPath ?? "", size: 84, radius: 42, circle: true, level: growth.shownLevel)
                        .overlay(Circle().stroke(gold.opacity(0.9), lineWidth: 1.6))
                        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                Button { showPhoto = true } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 27, height: 27)
                        .background(Circle().fill(LinearGradient(colors: [C.green, C.green.opacity(0.78)],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Text(app.me?.name ?? "")
                    .font(pf(19, .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if growth.shownLevel > 0 {
                    QQLevelBadge(level: growth.shownLevel, size: 14, maxIcons: 3).fixedSize()
                }
            }
            HStack(spacing: 10) {
                Text(Tr("星言号") + "：" + (app.me?.username ?? "-"))
                    .font(pf(13))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)

                Button { showMyQR = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "qrcode").font(.system(size: 11, weight: .semibold))
                        Text(Tr("二维码")).font(pf(12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1C2130), Color(hex: 0x2B2233), Color(hex: 0x14111A)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [gold.opacity(0.22), Color.clear],
                               center: .topTrailing, startRadius: 2, endRadius: 220)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            field(Tr("昵称"), $nickname)
            HStack(spacing: 8) {
                Text(Tr("最多 16 个字符；不能用 < > \" ' / \\ 等符号，不能冒用官方或客服"))
                    .font(pf(11.5))
                    .foregroundColor(C.subLabel)
                Spacer(minLength: 0)
                Text("\(nickname.count)/16")
                    .font(pf(11.5))
                    .foregroundColor(nickname.count > 16 ? C.red : C.subLabel)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            divider

            tapRow(Tr("性别"), gender == "female" ? Tr("女") : Tr("男")) { showGender = true }
            divider
            tapRow(Tr("地区"), region.isEmpty ? Tr("未设置") : region) { showRegion = true }
            divider
            tapRow(Tr("生日"), birthday.isEmpty ? Tr("未设置") : birthday) { showBirthday = true }
            divider
            field(Tr("个性签名"), $bio)
            divider

            HStack(spacing: 8) {
                Text(Tr("星语提示"))
                    .font(pf(16)).foregroundColor(C.label)
                    .frame(width: 82, alignment: .leading)

                Spacer(minLength: 8)
                TextField(Tr("收到一束星光"), text: $patText)
                    .font(pf(16)).foregroundColor(C.label)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: patText) { v in
                        if v.count > 10 { patText = String(v.prefix(10)) }
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            HStack(spacing: 8) {
                Text(Tr("显示在好友发来的星语提醒后，最多 10 个字"))
                    .font(pf(11.5)).foregroundColor(C.subLabel)
                Spacer(minLength: 0)
                Text("\(patText.count)/10")
                    .font(pf(11.5)).foregroundColor(patText.count >= 10 ? C.red : C.subLabel)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background { CardGlassBox(radius: 14) }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
    }

    private var contactCard: some View {
        VStack(spacing: 0) {
            Button { showPhone = true } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [C.green, C.green.opacity(0.78)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30)
                        Image(systemName: "iphone")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(Tr("手机号")).font(pf(16)).foregroundColor(C.label)
                    Spacer(minLength: 8)
                    Text(phone.isEmpty ? Tr("未绑定") : maskPhone(phone))
                        .font(pf(15))
                        .foregroundColor(C.subLabel)
                    Chevron(size: 8, line: 1.5)
                }
                .padding(.horizontal, 14)
                .frame(height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background { CardGlassBox(radius: 14) }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
    }

    private var ringCard: some View {
        Button { showRingtone = true } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xB98CFF), Color(hex: 0x7A45D6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tr("来电铃声")).font(pf(16)).foregroundColor(C.label)
                    Text(ring.currentName).font(pf(12)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                Chevron(size: 8, line: 1.5)
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background { CardGlassBox(radius: 14) }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(C.hairline, lineWidth: 0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var avatarRow: some View {
        Button { showPhoto = true } label: {
            HStack(spacing: 12) {
                Text(Tr("头像")).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                Avatar(path: app.me?.avatarPath ?? "", size: 48, radius: 6,
                       circle: false, level: growth.shownLevel)
                Chevron(size: 8, line: 1.5)
            }
            .padding(.horizontal, 14)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var patRow: some View {
        HStack(spacing: 8) {
            Text(Tr("星语提示")).font(pf(16)).foregroundColor(C.label)
                .frame(width: 82, alignment: .leading)
            TextField(Tr("收到一束星光"), text: $patText)
                .font(pf(16)).foregroundColor(C.label)
                .multilineTextAlignment(.trailing)
                .onChange(of: patText) { v in
                    if v.count > 10 { patText = String(v.prefix(10)) }
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private var phoneRow: some View {
        Button { showPhone = true } label: {
            HStack(spacing: 12) {
                Text(Tr("手机号")).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                Text(phone.isEmpty ? Tr("未绑定") : maskPhone(phone))
                    .font(pf(15)).foregroundColor(C.subLabel)
                Chevron(size: 8, line: 1.5)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ringRow: some View {
        Button { showRingtone = true } label: {
            HStack(spacing: 12) {
                Text(Tr("来电铃声")).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                Text(ring.currentName).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
                Chevron(size: 8, line: 1.5)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View { HairLine(inset: 14) }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(pf(16)).foregroundColor(C.label).frame(width: 70, alignment: .leading)
            TextField("", text: text)
                .font(pf(16))
                .foregroundColor(C.label)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private func tapRow(_ title: String, _ value: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Text(title).font(pf(16)).foregroundColor(C.label)
                Spacer(minLength: 8)
                Text(value).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
                Chevron(size: 8, line: 1.5)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func linkLabel(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(pf(16)).foregroundColor(C.label)
            Spacer(minLength: 8)
            Text(value).font(pf(15)).foregroundColor(C.subLabel).lineLimit(1)
            Chevron(size: 8, line: 1.5)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private func changeAvatar(_ image: UIImage) {
        busy = true
        let localPath = stageLocalImagePreview(image, prefix: "local-avatar")
        app.applyMyProfileFields(["avatar": localPath])
        Task {
            if let url = try? await API.shared.upload(image: image) {
                await cacheUploadedImage(image, path: url)
                app.applyMyProfileFields(["avatar": url])
                do {
                    let fields: [String: Any] = ["avatar": url]
                    if let updated = try await API.shared.updateMeChecked(fields) {
                        app.applyMyProfileUser(updated)
                    } else {
                        app.applyMyProfileFields(fields)
                    }
                } catch {
                    busy = false
                    app.show(Tr("已在本机换好，联网后自动同步"))
                    return
                }
                app.show(Tr("头像换好了"))
            } else {
                app.show(Tr("已在本机换好，联网后自动同步"))
            }
            busy = false
        }
    }

    private func save() {
        busy = true
        Task {
            var fields: [String: Any] = [
                "nickname": nickname,
                "bio": bio,
                "region": region,
                "gender": gender,
                "birthday": birthday,

                "patText": patText
            ]
            if !phone.isEmpty && phone != (app.me?.phone ?? "") { fields["phone"] = phone }
            do {
                let updated = try await API.shared.updateMeChecked(fields)
                if let updated {
                    app.applyMyProfileUser(updated)
                } else {
                    app.applyMyProfileFields(fields)
                }
            } catch {

                busy = false
                app.show(error.localizedDescription)
                return
            }
            await app.loadContacts()
            busy = false
            app.show(Tr("已保存"))
            dismiss()
        }
    }
}

struct UsernameChangeSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var busy = false
    @State private var err = ""

    private var nextChangeText: String {
        guard let s = app.me?.usernameUpdatedAt, !s.isEmpty else { return "" }
        var t = ISO8601DateFormatter().date(from: s)
        if t == nil {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            t = f.date(from: s)
        }
        guard let t else { return "" }
        let can = t.addingTimeInterval(365 * 24 * 60 * 60)
        if can <= Date() { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return "下次可改：" + f.string(from: can)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("星言号"), back: { dismiss() }) {
                Button { save() } label: {
                    Text(busy ? Tr("保存中…") : Tr("保存"))
                        .font(pf(15, .medium))
                        .foregroundColor(name.isEmpty || busy ? C.subLabel : C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty || busy)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text(Tr("星言号")).font(pf(16)).foregroundColor(C.label)
                        TextField("", text: $name)
                            .font(pf(16))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    HairLine(inset: 16)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Tr("3-24 位字母、数字或下划线；一年只能改一次。"))
                            .font(pf(12.5)).foregroundColor(C.subLabel)
                        if !nextChangeText.isEmpty {
                            Text(nextChangeText).font(pf(12.5)).foregroundColor(C.subLabel)
                        }
                        if !err.isEmpty {
                            Text(err).font(pf(12.5)).foregroundColor(C.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear { name = app.me?.username ?? "" }
    }

    private func save() {
        let want = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard want != (app.me?.username ?? "") else { dismiss(); return }
        busy = true
        err = ""
        Task {
            do {
                let fields: [String: Any] = ["username": want]
                if let updated = try await API.shared.updateMeChecked(fields) {
                    app.applyMyProfileUser(updated)
                } else {
                    app.applyMyProfileFields(fields)
                }
                busy = false
                app.show(Tr("星言号已更新"))
                dismiss()
            } catch {
                busy = false
                err = (error as? LocalizedError)?.errorDescription ?? "改不了，稍后再试"
            }
        }
    }
}
