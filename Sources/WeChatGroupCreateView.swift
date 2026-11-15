import SwiftUI
import UIKit

struct WeChatGroupCreateView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var onCreated: (Chat) -> Void

    @State private var picked: Set<String> = []
    @State private var keyword = ""
    @State private var busy = false
    @State private var showFace = false

    private let selectionFeedback = UISelectionFeedbackGenerator()

    private var brandGreen: Color { C.green }

    private var emptyCheckColor: Color {
        scheme == .dark ? Color.white.opacity(0.52) : Color.black.opacity(0.34)
    }

    private struct ContactSection: Identifiable {
        let id: String
        let users: [User]
    }

    private var selectedContacts: [User] {
        app.contacts.filter { picked.contains($0.id) }
    }

    private var filteredContacts: [User] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return app.contacts }
        return app.contacts.filter { user in
            [user.name, user.username ?? "", user.phone ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var contactSections: [ContactSection] {
        let grouped = Dictionary(grouping: filteredContacts) { sectionLetter(for: $0) }
        return grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }
        .map { letter in
            ContactSection(
                id: letter,
                users: grouped[letter, default: []].sorted {
                    let left = sortKey(for: $0)
                    let right = sortKey(for: $1)
                    return left == right ? $0.name < $1.name : left < right
                }
            )
        }
    }

    private var completionTitle: String {
        let title = Tr("完成")
        return picked.isEmpty ? title : "\(title) (\(picked.count))"
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: Tr("发起群聊"),
                back: { dismiss() },
                backColor: C.label,
                floating: false,
                titleGlass: false,
                rightGlass: false
            ) {
                Button(action: create) {
                    if busy {
                        ProgressView()
                            .tint(brandGreen)
                            .scaleEffect(0.78)
                            .frame(width: 76, height: L.navH)
                    } else {
                        Text(completionTitle)
                            .font(pf(16, .medium))
                            .foregroundColor(picked.isEmpty ? C.subLabel : brandGreen)
                            .frame(minWidth: 76, minHeight: L.navH, alignment: .trailing)
                    }
                }
                .buttonStyle(.plain)
                .disabled(picked.isEmpty || busy)
                .padding(.trailing, 16)
                .accessibilityLabel(Tr("完成"))
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    searchBar
                    faceGroupRow

                    if contactSections.isEmpty {
                        emptyView
                    } else {
                        ForEach(contactSections) { section in
                            Section {
                                ForEach(section.users) { user in
                                    contactRow(user)
                                }
                            } header: {
                                sectionHeader(section.id)
                            }
                        }
                    }
                }
                .padding(.bottom, max(16, L.safeBottom))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .onAppear {
            selectionFeedback.prepare()
        }
        .sheet(isPresented: $showFace) {
            FaceGroupView { chat in
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onCreated(chat)
                }
            }
            .environmentObject(app)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(C.subLabel)

            TextField(Tr("搜索"), text: $keyword)
                .font(pf(16))
                .foregroundColor(C.label)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(C.subLabel.opacity(0.72))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.dyn(0xEDEDED, 0x2C2C2E))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(C.pageBg)
    }

    private var faceGroupRow: some View {
        VStack(spacing: 0) {
            Button {
                showFace = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(brandGreen)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 40, height: 40)

                    Text(Tr("面对面建群"))
                        .font(pf(17))
                        .foregroundColor(C.label)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 58)
                .background(C.cardBg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            separator(leading: 68)
        }
        .padding(.bottom, 9)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(pf(13, .medium))
            .foregroundColor(C.subLabel)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.leading, 16)
            .background(C.pageBg)
    }

    private func contactRow(_ user: User) -> some View {
        let selected = picked.contains(user.id)
        return VStack(spacing: 0) {
            Button {
                toggle(user.id)
            } label: {
                HStack(spacing: 12) {
                    Avatar(path: user.avatarPath, size: 40, circle: true)

                    Text(user.name)
                        .font(pf(17))
                        .foregroundColor(C.label)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    ZStack {
                        Circle()
                            .fill(selected ? brandGreen : Color.clear)
                        Circle()
                            .stroke(selected ? brandGreen : emptyCheckColor,
                                    lineWidth: selected ? 1.6 : 1.5)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.16),
                                        radius: 0.5, y: 0.35)
                                .transition(.scale(scale: 0.68).combined(with: .opacity))
                        }
                    }
                    .frame(width: 23, height: 23)
                    .animation(.spring(response: 0.22, dampingFraction: 0.82),
                               value: selected)
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                .background(C.cardBg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            separator(leading: 68)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(C.subLabel.opacity(0.72))
            Text(Tr("没有找到联系人"))
                .font(pf(15))
                .foregroundColor(C.subLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    private func separator(leading: CGFloat) -> some View {
        Rectangle()
            .fill(C.hairline)
            .frame(height: 0.5)
            .padding(.leading, leading)
            .background(C.cardBg)
    }

    private func toggle(_ id: String) {
        withAnimation(.easeOut(duration: 0.12)) {
            if picked.contains(id) {
                picked.remove(id)
            } else {
                picked.insert(id)
            }
        }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    private func create() {
        guard !picked.isEmpty, !busy else { return }
        let members = selectedContacts
        let generatedName = members.prefix(3).map(\.name).joined(separator: "、")
        let groupName = generatedName.isEmpty ? Tr("群聊") : generatedName
        busy = true

        Task {
            do {
                if let chat = try await API.shared.createGroup(
                    name: groupName,
                    memberIds: Array(picked)
                ) {
                    await app.loadChats()
                    onCreated(chat)
                    dismiss()
                }
            } catch {
                app.show((error as? APIError)?.errorDescription ?? Tr("创建失败"))
            }
            busy = false
        }
    }

    private func sortKey(for user: User) -> String {
        let latin = user.name
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? user.name
        return latin.folding(options: [.caseInsensitive, .diacriticInsensitive],
                             locale: .current)
    }

    private func sectionLetter(for user: User) -> String {
        guard let first = sortKey(for: user).first else { return "#" }
        let letter = String(first).uppercased()
        guard let scalar = letter.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(scalar) else {
            return "#"
        }
        return letter
    }
}
