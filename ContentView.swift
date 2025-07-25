import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            CertsView()
                .tabItem {
                    Label("Certs", systemImage: "doc.text")
                }
        }
    }
}

struct HomeView: View {
    var body: some View {
        VStack {
            Text("Upload IPA")
            Button("Select IPA") {
                // TODO: Add file picker action
            }
            Button("Sign & Submit") {
                // TODO: Add upload/sign logic
            }
        }.padding()
    }
}

struct CertsView: View {
    var body: some View {
        VStack {
            Text("Upload Certificate")
            Button("Select .isigncert") {
                // TODO: Add file picker
            }
        }.padding()
    }
}
