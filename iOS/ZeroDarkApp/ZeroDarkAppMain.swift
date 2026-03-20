//
//  ZeroDarkAppMain.swift
//  ZeroDark iOS App
//
//  Wrapper to launch the ZeroDark SwiftUI app
//

import SwiftUI
import ZeroDark

@main
struct ZeroDarkAppMain: App {
    var body: some Scene {
        WindowGroup {
            ZeroDarkMainView()
        }
    }
}
