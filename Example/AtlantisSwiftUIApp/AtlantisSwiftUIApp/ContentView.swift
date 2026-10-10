//
//  ContentView.swift
//  AtlantisSwiftUIApp
//
//  Created by nghiatran on 23/3/25.
//

import SwiftUI

/// A tab for each OS. Each tab lists the APIs that Atlantis swizzles
struct ContentView: View {

    @EnvironmentObject private var store: DemoStore

    var body: some View {
        TabView {
            ForEach(DemoPage.allCases) { page in
                DemoListView(page: page)
                    .tabItem {
                        Label(page.title, systemImage: page.symbol)
                    }
            }
        }
        .task {
            store.startObservingAtlantis()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DemoStore())
}
