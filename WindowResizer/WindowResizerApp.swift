//
//  WindowResizerApp.swift
//  WindowResizer
//
//  Created by Mihai Leonte on 14.03.2025.
//

import SwiftUI

@main
struct WindowResizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
