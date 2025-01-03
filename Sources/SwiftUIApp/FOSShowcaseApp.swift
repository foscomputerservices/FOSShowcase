// FOSShowcaseApp.swift
//
// Created by David Hunt on 9/10/24
// Copyright 2024 FOS Computer Services, LLC
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

public extension SystemVersion {
    // My application's current version
    static var currentApplicationVersion: Self { .v1_0 }

    // My application's versions

    // REVIEWED dgh
    // swiftlint:disable:next force_try
    static var v1_0: Self { .init(major: 1, minor: 0, patch: try! Bundle.main.appleOSVersion.patch) }
}

@main
struct FOSShowcaseApp: App {
    @State var viewModel: LandingPageViewModel?

    var body: some Scene {
        let vmBinding = $viewModel

        return WindowGroup {
            LandingPageView.bind(
                viewModel: vmBinding
            )
            .environment(
                MVVMEnvironment(
                    currentVersion: .currentApplicationVersion,
                    appBundle: Bundle.main,
                    deploymentURLs: [
                        .production: URL(string: "https://api.foscomputerservices.com")!,
                        .staging: URL(string: "https://staging.foscomputerservices.com")!,
                        .debug: URL(string: "http://localhost:8080")!
                    ]
                )
            )
        }
    }
}
