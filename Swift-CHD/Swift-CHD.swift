//  Swift-CHD.swift - Swift-CHD, Copyright (C) 2025-2026 David Hauf
//
//  This program is free software: you can redistribute it and/or modify it under the terms of the
//  GNU General Public License as published by the Free Software Foundation, either version 2 of
//  the License, or (at your option) any later version. See the LICENSE file for details.

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
        // .automatic resizability sizes the window to the content's *ideal* height and refuses
        // to shrink - one long message stretched it to thousands of points. .contentMinSize does not.
        .defaultSize(width: 1000, height: 760)
        .windowResizability(.contentMinSize)
    }
}
