import SwiftUI
import UIKit

struct ApprovalIdentityView: View {
    private let identity = ApprovalIdentityKeyStore.shared.identity
    @State private var copiedMessage: String?

    var body: some View {
        List {
            Section(header: Text("审批身份")) {
                labeledValue("Subject", identity.subject)
                labeledValue("Login", identity.login)
            }

            Section(header: Text("Ed25519 公钥")) {
                Text(identity.publicKeyPEM)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)

                Button("复制公钥") {
                    UIPasteboard.general.string = identity.publicKeyPEM
                    copiedMessage = "公钥已复制"
                }
                Button("复制 Subject") {
                    UIPasteboard.general.string = identity.subject
                    copiedMessage = "Subject 已复制"
                }
            }

            Section {
                Text("此公钥用于第三方审批服务校验 Drel 的设备绑定审批身份。私钥保存在系统 Keychain，不会离开本机。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("审批身份")
        .alert(copiedMessage ?? "", isPresented: Binding(
            get: { copiedMessage != nil },
            set: { if !$0 { copiedMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        }
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
