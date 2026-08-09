//
//  Swift_CHDApp.swift
//  Swift-CHD
//
//  Created by David Hauf on 12/2/25.
//

import SwiftUI

@main
struct Swift_CHDApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Resizability defaults to .automatic, which sizes the window to whatever its content
        // reports as an *ideal* size and refuses to go smaller. A single long message was
        // enough to stretch the window to several thousand points tall. .contentMinSize keeps
        // the default size below and only enforces the content's minimum.
        .defaultSize(width: 1000, height: 760)
        .windowResizability(.contentMinSize)
    }
}
