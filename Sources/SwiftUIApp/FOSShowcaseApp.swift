// FOSShowcaseApp.swift
//
// Created by David Hunt on 9/6/24
// Copyright 2024 FOS Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import FOSFoundation
import FOSMVVM
import SwiftUI

@main
struct FOSShowcaseApp: App {
    @State var baseURL: URL?
    @State var viewModel: LandingPageViewModel?

    var body: some Scene {
        WindowGroup {
            if let baseURL {
                LandingPageView.bind(
                    viewModel: $viewModel,
                    using: LandingPageRequest()
                )
                .environment(
                    MVVMEnvironment(
                        serverBaseURL: baseURL
                    ) {
                        AnyView(
                            Text((try? viewModel?.loadingTitle.localizedString) ?? "Loading...")
                        )
                    }
                )
            } else {
                Text("...")
                    .task {
                        let url = await URL.baseURL
                        if baseURL == nil {
                            baseURL = url
                        }
                    }
            }
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
