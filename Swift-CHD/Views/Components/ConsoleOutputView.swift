import SwiftUI

struct ConsoleOutputView: View {
    let consoleOutput: String

    var body: some View {
        GroupBox(label: Label("Console Output", systemImage: "terminal")) {
            ScrollView {
                ScrollViewReader { proxy in
                    Text(consoleOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("consoleBottom")
                        .onChange(of: consoleOutput) { _, _ in
                            proxy.scrollTo("consoleBottom", anchor: .bottom)
                        }
                }
            }
            .frame(height: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
        }
    }
}
