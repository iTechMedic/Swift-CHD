//  ContentView.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

import SwiftUI

struct ContentView: View {
    // @StateObject, not @ObservedObject: the latter rebuilds the view model on every re-init,
    // discarding state mid-run and publishing from inside a view update.
    @StateObject private var vm = ConversionViewModel()

    /// Drives the mode picker instead of the view model.
    ///
    /// AppKit applies a segmented control's selection inside SwiftUI's update pass, so binding it
    /// straight to an @Published property publishes to the object this body observes while that
    /// body is being evaluated. Local state takes the write; the model is updated just after.
    @State private var isBatchMode = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Mode selector at the top
                Picker("Mode", selection: $isBatchMode) {
                    Text("Single File").tag(false)
                    Text("Batch Mode").tag(true)
                }
                .pickerStyle(.segmented)
                .padding()
                // onChange runs after the update, so publishing from here is safe.
                .onChange(of: isBatchMode) { _, new in
                    if vm.isBatchMode != new { vm.isBatchMode = new }
                }
                .onChange(of: vm.isBatchMode) { _, new in
                    if isBatchMode != new { isBatchMode = new }
                }

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
            if isBatchMode {
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
