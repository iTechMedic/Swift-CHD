import SwiftUI

struct ContentView: View {
    @ObservedObject private var vm = ConversionViewModel()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Mode selector at the top
                Picker("Mode", selection: $vm.isBatchMode) {
                    Text("Single File").tag(false)
                    Text("Batch Mode").tag(true)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Conversion type list
                List(ConversionType.allCases) { type in
                    Button(action: {
                        vm.conversionType = type
                    }) {
                        HStack {
                            Text(type.title)
                            Spacer()
                            if vm.conversionType == type {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Swift-CHD")
            .frame(minWidth: 200)
        } detail: {
            if vm.isBatchMode {
                BatchModeView(vm: vm)
            } else {
                SingleModeView(vm: vm)
            }
        }
    }
}

#Preview {
    ContentView()
}
