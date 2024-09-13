//
//  FOSWatchShowcaseApp.swift
//  FOSWatchShowcase Watch App
//
//  Created by David Hunt on 9/12/24.
//

import FOSFoundation
import FOSMVVM
import SwiftUI

@main
struct FOSWatchShowcase_WatchApp: App {
    @State var baseURL: URL?
    @State var viewModel: LandingPageViewModel?

    var body: some Scene {
        WindowGroup {
            LandingPageView.bind(
                viewModel: $viewModel,
                using: LandingPageRequest()
            )
            .task {
                baseURL = await URL.baseURL
            }
            .environment(
                MVVMEnvironment(
                    serverBaseURL: baseURL ?? URL(string: "http://localhost:8080")!
                ) {
                    AnyView(
                        Text((try? viewModel?.loadingTitle.localizedString) ?? "Loading...")
                    )
                }
            )
        }
    }
}

extension URL {
    static var baseURL: URL {
        get async {
            switch await Deployment.current {
            case .production: URL(string: "https://api.foscomputerservices.com")!
            case .staging: URL(string: "https://staging.foscomputerservices.com")!
            case .debug: URL(string: "http://localhost:8080")!
            case .custom(let name):
                fatalError("Unsupported custom deployment: '\(name)'")
            }
        }
    }
}
