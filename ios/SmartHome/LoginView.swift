import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var store: SensorStore
    @State private var username = "root"
    @State private var password = ""
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "house.fill").font(.system(size: 48)).foregroundStyle(green)
                Text("欢迎回家").font(.largeTitle.bold()).foregroundStyle(ink)
                Text("登录后查看家中的温湿度与设备").font(.subheadline).foregroundStyle(.secondary)
                TextField("账号", text: $username).textContentType(.username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                SecureField("密码", text: $password).textContentType(.password).textFieldStyle(.roundedBorder)
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
                Button {
                    busy = true; message = ""
                    Task {
                        defer { busy = false }
                        do { try await store.login(username: username, password: password); password = "" }
                        catch { message = (error as? APIError) == .unauthorized ? "账号或密码不正确" : error.localizedDescription }
                    }
                } label: {
                    Group { if busy { ProgressView().tint(.white) } else { Text("登录").bold() } }
                        .frame(maxWidth: .infinity).padding(14).background(green, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }.disabled(busy || username.isEmpty || password.isEmpty)
            }.padding(28).frame(maxWidth: 480)
        }
    }
}
