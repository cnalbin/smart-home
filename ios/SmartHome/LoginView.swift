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
    var body: some View {
        ScrollView {
            VStack(spacing: 17) {
                identity
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
                                    .font(.system(size: 19)).foregroundStyle(blue)
                                Text("记住密码").font(.system(size: 14)).foregroundStyle(ink)
                            }.frame(minHeight: 32)
                        }.buttonStyle(.plain).accessibilityValue(rememberPassword ? "已勾选" : "未勾选")
                        Spacer(minLength: 0)
                        Text("仅保存在本机").font(.caption2).foregroundStyle(muted)
                    }
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: signIn) {
                        if busy { ProgressView().tint(.white) } else { Text("登录") }
                    }.buttonStyle(DashboardButtonStyle()).disabled(busy || username.isEmpty || password.isEmpty)
                }
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 25)
                .frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(canvas.ignoresSafeArea())
        .tint(blue)
        .onAppear {
            if let saved = CredentialVault().read() {
                username = saved.username; password = saved.password; rememberPassword = true
            }
        }
        .onChange(of: rememberPassword) { selected in if !selected { CredentialVault().clear() } }
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottom) {
                Image(systemName: "house").font(.system(size: 55, weight: .medium))
                Image(systemName: "wifi").font(.system(size: 21, weight: .semibold)).offset(y: -10)
            }.accessibilityHidden(true)
            Text("智能家居").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text("查看环境，控制设备").font(.subheadline)
        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(26)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(colors: [blue, Color(red: 0.12, green: 0.29, blue: 0.68)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().strokeBorder(.white.opacity(0.16), lineWidth: 26)
                        .frame(width: 158, height: 158).offset(x: 30, y: 70)
                    Circle().strokeBorder(.white.opacity(0.10), lineWidth: 22)
                        .frame(width: 210, height: 210).offset(x: 56, y: 96)
                    Circle().fill(.white.opacity(0.08)).frame(width: 105, height: 105).offset(x: 47, y: -113)
                }.accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 17))
    }
    private func inputRow<Content: View>(symbol: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            DeviceIcon(symbol: symbol, size: 36)
            Divider().frame(height: 31)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(ink)
                content().font(.subheadline).foregroundStyle(ink).accessibilityLabel(title)
            }
        }.padding(.horizontal, 13).frame(minHeight: 60)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
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
