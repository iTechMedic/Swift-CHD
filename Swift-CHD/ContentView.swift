//
//  ContentView.swift
//  Swift-CHD
//
//  Created by David Hauf on 12/2/25.
//

import SwiftUI
import UniformTypeIdentifiers

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
                batchModeView
            } else {
                singleModeView
            }
        }
    }
    
    // MARK: - Single File Mode View
    
    private var singleModeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("Conversion", systemImage: "arrow.triangle.2.circlepath")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.conversionType.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Label("Paths", systemImage: "folder")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Input:")
                        Text(vm.inputURL?.path ?? "Choose input...")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Browse…") { chooseInput() }
                    }
                    HStack {
                        Text("Output:")
                        Text(vm.outputURL?.path ?? "Choose output...")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Browse…") { chooseOutput() }
                    }
                    HStack {
                        Text("chdman:")
                        TextField("Path to chdman (or leave as 'chdman')", text: $vm.chdmanPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Verify") {
                            Task { await vm.verifyCHDMan() }
                        }
                        .buttonStyle(.borderedProminent)
                        if vm.chdmanVerified {
                            Image(systemName: vm.chdmanNotFoundHelp != nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(vm.chdmanNotFoundHelp != nil ? .orange : .green)
                                .help(vm.chdmanNotFoundHelp != nil ? "Path looks correct but couldn't verify" : "chdman found and verified")
                        }
                    }
                    if let help = vm.chdmanNotFoundHelp {
                        Text(help)
                            .font(.caption)
                            .foregroundStyle(vm.chdmanVerified ? .orange : .red)
                            .padding(.top, 4)
                            .textSelection(.enabled)
                    }
                }
            }

            GroupBox(label: Label("Options", systemImage: "slider.horizontal.3")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(vm.advancedMode ? "Advanced Mode" : "Simple Mode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Advanced", isOn: $vm.advancedMode)
                            .toggleStyle(.switch)
                    }
                    
                    if vm.options.isEmpty {
                        Text("No options enabled. Toggle 'Advanced' to see all available options.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.vertical, 8)
                    }
                    
                    Divider()
                    
                    ForEach($vm.options) { $opt in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 12) {
                                // Enable/Disable toggle
                                Toggle(isOn: $opt.isEnabled) {
                                    Text(opt.key)
                                        .monospaced()
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 40, alignment: .leading)
                                }
                                .toggleStyle(.switch)
                                .help("Enable/disable \(opt.key)")
                                
                                // Value input based on type
                                switch opt.type {
                                case .flag:
                                    Text("(flag)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 140, alignment: .leading)
                                    
                                case .text:
                                    TextField("value", text: Binding(
                                        get: { opt.value ?? "" },
                                        set: { opt.value = $0.isEmpty ? nil : $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                    .disabled(!opt.isEnabled)
                                    
                                case .dropdown(let choices):
                                    Picker("", selection: $opt.value) {
                                        ForEach(choices, id: \.self) { choice in
                                            Text(choice).tag(choice as String?)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 140)
                                    .disabled(!opt.isEnabled)
                                }
                                
                                // Help text
                                Text(opt.help)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                
                                Spacer()
                            }
                            
                            // Show codec description if this is the compression codec option
                            if opt.key == "-c", opt.isEnabled, let codec = opt.value,
                               let description = ConversionType.codecDescriptions[codec] {
                                Text("ℹ️ \(description)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .padding(.leading, 60)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(8)
            }

            if vm.isRunning {
                HStack(spacing: 12) {
                    ProgressView(value: vm.progress)
                        .frame(width: 240)
                    Text(String(format: "%.0f%%", vm.progress * 100))
                        .monospacedDigit()
                    Text(vm.statusLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack {
                Button(role: .none) {
                    Task { await vm.start() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isRunning || vm.inputURL == nil || vm.outputURL == nil || !vm.chdmanVerified)

                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(3)
                }
                Spacer()
            }
            
            // Console Output
            if !vm.consoleOutput.isEmpty {
                GroupBox(label: Label("Console Output", systemImage: "terminal")) {
                    ScrollView {
                        ScrollViewReader { proxy in
                            Text(vm.consoleOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id("consoleBottom")
                                .onChange(of: vm.consoleOutput) { _, _ in
                                    proxy.scrollTo("consoleBottom", anchor: .bottom)
                                }
                        }
                    }
                    .frame(height: 200)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                }
            }

            Spacer()
        }
        .padding()
    }
    
    // MARK: - Batch Mode View
    
    private var batchModeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("Conversion", systemImage: "arrow.triangle.2.circlepath")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.conversionType.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Label("Batch Files", systemImage: "doc.on.doc")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Add Files…") { chooseBatchInput() }
                        Button("Clear All") { vm.clearBatchItems() }
                            .disabled(vm.batchItems.isEmpty || vm.isRunning)
                        Spacer()
                        Text("\(vm.batchItems.count) file(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Output Directory:")
                        Text(vm.batchOutputDirectory?.path ?? "Same as input files")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseBatchOutputDirectory() }
                        if vm.batchOutputDirectory != nil {
                            Button("Reset") { vm.updateBatchOutputDirectory(nil) }
                        }
                    }
                    
                    Divider()
                    
                    // Batch items list
                    if vm.batchItems.isEmpty {
                        Text("No files added. Click 'Add Files…' to begin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(vm.batchItems) { item in
                                    batchItemRow(item)
                                }
                            }
                        }
                        .frame(height: 200)
                    }
                }
            }
            
            GroupBox(label: Label("Batch Options", systemImage: "gearshape.2")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Skip existing files", isOn: $vm.batchConfig.skipExisting)
                    Toggle("Stop on first error", isOn: $vm.batchConfig.stopOnError)
                    
                    HStack {
                        Text("chdman:")
                        TextField("Path to chdman (or leave as 'chdman')", text: $vm.chdmanPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Verify") {
                            Task { await vm.verifyCHDMan() }
                        }
                        .buttonStyle(.borderedProminent)
                        if vm.chdmanVerified {
                            Image(systemName: vm.chdmanNotFoundHelp != nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(vm.chdmanNotFoundHelp != nil ? .orange : .green)
                                .help(vm.chdmanNotFoundHelp != nil ? "Path looks correct but couldn't verify" : "chdman found and verified")
                        }
                    }
                    if let help = vm.chdmanNotFoundHelp {
                        Text(help)
                            .font(.caption)
                            .foregroundStyle(vm.chdmanVerified ? .orange : .red)
                            .padding(.top, 4)
                            .textSelection(.enabled)
                    }
                }
            }
            
            GroupBox(label: Label("Advanced Options", systemImage: "slider.horizontal.3")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(vm.advancedMode ? "Advanced Mode" : "Simple Mode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Advanced", isOn: $vm.advancedMode)
                            .toggleStyle(.switch)
                    }
                    
                    if vm.options.isEmpty {
                        Text("No options enabled. Toggle 'Advanced' to see all available options.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.vertical, 8)
                    }
                    
                    Divider()
                    
                    ForEach($vm.options) { $opt in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 12) {
                                Toggle(isOn: $opt.isEnabled) {
                                    Text(opt.key)
                                        .monospaced()
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 40, alignment: .leading)
                                }
                                .toggleStyle(.switch)
                                .help("Enable/disable \(opt.key)")
                                
                                switch opt.type {
                                case .flag:
                                    Text("(flag)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 140, alignment: .leading)
                                    
                                case .text:
                                    TextField("value", text: Binding(
                                        get: { opt.value ?? "" },
                                        set: { opt.value = $0.isEmpty ? nil : $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                    .disabled(!opt.isEnabled)
                                    
                                case .dropdown(let choices):
                                    Picker("", selection: $opt.value) {
                                        ForEach(choices, id: \.self) { choice in
                                            Text(choice).tag(choice as String?)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 140)
                                    .disabled(!opt.isEnabled)
                                }
                                
                                Text(opt.help)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                
                                Spacer()
                            }
                            
                            if opt.key == "-c", opt.isEnabled, let codec = opt.value,
                               let description = ConversionType.codecDescriptions[codec] {
                                Text("ℹ️ \(description)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .padding(.leading, 60)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(8)
            }
            
            if vm.isRunning {
                HStack(spacing: 12) {
                    ProgressView(value: vm.progress)
                        .frame(width: 240)
                    Text(String(format: "%.0f%%", vm.progress * 100))
                        .monospacedDigit()
                    Text(vm.statusLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            HStack {
                Button(role: .none) {
                    Task { await vm.start() }
                } label: {
                    Label("Run Batch", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isRunning || vm.batchItems.isEmpty || !vm.chdmanVerified)

                if let err = vm.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(3)
                }
                Spacer()
            }
            
            // Batch Summary
            if let summary = vm.batchSummary {
                GroupBox(label: Label("Batch Summary", systemImage: "chart.bar")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Total:")
                            Spacer()
                            Text("\(summary.total)")
                        }
                        HStack {
                            Text("✅ Succeeded:")
                            Spacer()
                            Text("\(summary.succeeded)")
                                .foregroundStyle(.green)
                        }
                        HStack {
                            Text("❌ Failed:")
                            Spacer()
                            Text("\(summary.failed)")
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Text("⏭️ Skipped:")
                            Spacer()
                            Text("\(summary.skipped)")
                                .foregroundStyle(.orange)
                        }
                        Divider()
                        HStack {
                            Text("Success Rate:")
                            Spacer()
                            Text(String(format: "%.1f%%", summary.successRate * 100))
                                .bold()
                        }
                    }
                    .font(.caption)
                }
            }
            
            // Console Output
            if !vm.consoleOutput.isEmpty {
                GroupBox(label: Label("Console Output", systemImage: "terminal")) {
                    ScrollView {
                        ScrollViewReader { proxy in
                            Text(vm.consoleOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id("consoleBottom")
                                .onChange(of: vm.consoleOutput) { _, _ in
                                    proxy.scrollTo("consoleBottom", anchor: .bottom)
                                }
                        }
                    }
                    .frame(height: 200)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                }
            }

            Spacer()
        }
        .padding()
    }
    
    private func batchItemRow(_ item: BatchConversionItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.status.icon)
                .foregroundStyle(Color(item.status.color))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.inputURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                Text(item.outputURL.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let error = item.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if item.status == .processing {
                ProgressView(value: item.progress)
                    .frame(width: 80)
                Text(String(format: "%.0f%%", item.progress * 100))
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 35)
            } else {
                Text(item.status.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            
            Button(action: {
                vm.removeBatchItem(item)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(vm.isRunning)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }
}

// MARK: - File pickers (AppKit bridges)

private extension ContentView {
    func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        // Use the extension from ConversionType
        panel.allowedContentTypes = [.init(filenameExtension: vm.conversionType.inputExtension)!]
        
        if panel.runModal() == .OK { 
            vm.inputURL = panel.url 
        }
    }
    
    func chooseBatchInput() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        // Use the extension from ConversionType
        panel.allowedContentTypes = [.init(filenameExtension: vm.conversionType.inputExtension)!]
        panel.message = "Select one or more \(vm.conversionType.inputExtension.uppercased()) files to convert"
        
        if panel.runModal() == .OK {
            vm.addBatchFiles(panel.urls)
        }
    }
    
    func chooseBatchOutputDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose output directory for converted files"
        
        if panel.runModal() == .OK {
            vm.updateBatchOutputDirectory(panel.url)
        }
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        
        // Use the extension from ConversionType
        let ext = vm.conversionType.outputExtension
        panel.allowedContentTypes = [.init(filenameExtension: ext)!]
        panel.nameFieldStringValue = suggestedOutputName(ext: ext)
        
        if panel.runModal() == .OK { 
            vm.outputURL = panel.url 
        }
    }

    func suggestedOutputName(ext: String) -> String {
        if let input = vm.inputURL { 
            return input.deletingPathExtension().lastPathComponent + "." + ext 
        }
        return "output." + ext
    }
}

#Preview {
    ContentView()
}
