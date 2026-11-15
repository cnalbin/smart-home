import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: SensorStore
    @State private var username = "root"
    @State private var password = ""
    @State private var rememberPassword = false
    @State private var passwordVisible = false
    @State private var message = ""
    @State private var busy = false
    @FocusState private var focus: Field?
    private enum Field { case username, password }
    private let background = Color(red: 0.973, green: 0.961, blue: 0.937)
    private let accent = Color(red: 0.29, green: 0.43, blue: 0.25)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    landscape(height: min(330, max(220, geometry.size.height * 0.42)), topInset: geometry.safeAreaInsets.top)
                    VStack(spacing: 8) {
                        Text("欢迎回家").font(.system(size: 32, weight: .bold)).foregroundStyle(ink)
                        Text("让家的温度，随时可见").font(.system(size: 15)).tracking(1.5).foregroundStyle(.secondary)
                    }.padding(.top, 2).padding(.bottom, 32)
                    VStack(spacing: 16) {
                        inputRow(symbol: "person", title: "账号") {
                            TextField("请输入账号", text: $username).textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focus, equals: .username).submitLabel(.next)
                                .onSubmit { focus = .password }
                        }
                        inputRow(symbol: "lock", title: "密码") {
                            HStack(spacing: 8) {
                                Group {
                                    if passwordVisible { TextField("请输入密码", text: $password) }
                                    else { SecureField("请输入密码", text: $password) }
                                }.textContentType(.password).textInputAutocapitalization(.never)
                                    .autocorrectionDisabled().focused($focus, equals: .password)
                                    .submitLabel(.go).onSubmit { signIn() }
                                Button { passwordVisible.toggle(); focus = .password } label: {
                                    Image(systemName: passwordVisible ? "eye.slash" : "eye")
                                        .font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 32, height: 32)
                                }.buttonStyle(.plain).accessibilityLabel(passwordVisible ? "隐藏密码" : "显示密码")
                            }
                        }
                        HStack(spacing: 8) {
                            Button { rememberPassword.toggle() } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: rememberPassword ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 19)).foregroundStyle(accent)
                                    Text("记住密码").font(.system(size: 14)).foregroundStyle(ink)
                                }.frame(minHeight: 32)
                            }.buttonStyle(.plain).accessibilityValue(rememberPassword ? "已勾选" : "未勾选")
                            Spacer(minLength: 0)
                            Text("安全保存在本机").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if !message.isEmpty {
                            Text(message).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button(action: signIn) {
                            HStack(spacing: 14) {
                                if busy { ProgressView().tint(.white) }
                                else { Text("登录").font(.system(size: 20, weight: .semibold)); Image(systemName: "arrow.right").font(.system(size: 20)) }
                            }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54)
                                .background(accent, in: RoundedRectangle(cornerRadius: 14))
                                .shadow(color: accent.opacity(0.17), radius: 8, y: 4)
                        }.buttonStyle(.plain).disabled(busy || username.isEmpty || password.isEmpty)
                            .opacity(username.isEmpty || password.isEmpty ? 0.7 : 1).padding(.top, 8)
                        Text("登录后查看温湿度与设备状态").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 28).frame(maxWidth: 480)
                    Spacer(minLength: 28)
                    Label("智能家居 · 安心相伴", systemImage: "house")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 24)
                }.frame(minHeight: geometry.size.height)
            }.scrollDismissesKeyboard(.interactively).background(background)
        }
        .background(background.ignoresSafeArea())
        .onAppear {
            if let saved = CredentialVault().read() {
                username = saved.username; password = saved.password; rememberPassword = true
            }
        }
        .onChange(of: rememberPassword) { selected in if !selected { CredentialVault().clear() } }
    }
    private func landscape(height: CGFloat, topInset: CGFloat) -> some View {
        ZStack {
            GeometryReader { proxy in
                Image("LoginLandscape").resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: height + topInset).clipped()
                    .offset(y: -topInset)
                LinearGradient(stops: [.init(color: .clear, location: 0.65), .init(color: background, location: 1)],
                    startPoint: .top, endPoint: .bottom).frame(height: height)
            }
            ZStack {
                Image(systemName: "house").font(.system(size: 48, weight: .light))
                Image(systemName: "leaf.fill").font(.system(size: 19)).offset(y: 8)
            }.foregroundStyle(.white).offset(y: -20).accessibilityHidden(true)
        }.frame(height: height)
    }
    private func inputRow<Content: View>(symbol: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(.secondary).frame(width: 22)
            Rectangle().fill(.gray.opacity(0.3)).frame(width: 0.5, height: 27)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                content().font(.system(size: 17)).foregroundStyle(ink)
            }
        }.padding(.horizontal, 16).frame(height: 58)
            .background(Color(red: 0.92, green: 0.90, blue: 0.87).opacity(0.4), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.gray.opacity(0.3), lineWidth: 0.7))
    }
    private func signIn() {
        guard !busy, !username.isEmpty, !password.isEmpty else { return }
        focus = nil; busy = true; message = ""
        Task {
            defer { busy = false }
            do { try await store.login(username: username, password: password, rememberPassword: rememberPassword); password = "" }
            catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                message = (error as? APIError) == .unauthorized ? "账号或密码不正确" : error.localizedDescription
            }
        }
    }
}
