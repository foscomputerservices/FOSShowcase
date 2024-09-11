// Site.swift
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
import Foundation
import Ignite
import ViewModels

@main
struct IgniteWebsite {
    static func main() async throws {
        let site = try await FOSShowcaseSite(
            store: Bundle.module.yamlLocalization(
                resourceDirectoryName: "Resources"
            ),
            locale: Locale(identifier: "en")
        )

        do {
            try await site.publish()
        } catch {
            print(error.localizedDescription)
        }
    }
}

private struct FOSShowcaseSite: Site {
    var name = "FOSShowcase"
    var titleSuffix = " – FOS Showcase"
    var url = URL(string: "https://www.foscomputerservices.com")!
    var builtInIconsEnabled = true

    var author = "David Hunt"

    let homePage: LandingPage
    var theme = MyTheme()

    init(store: any LocalizationStore, locale: Locale) throws {
        let viewModel: LandingPageViewModel =
            try .init()
                .toJSON(
                    encoder: JSONEncoder.localizingEncoder(
                        locale: locale,
                        localizationStore: store
                    )
                )
                .fromJSON()

        self.homePage = LandingPage(viewModel: viewModel)
    }
}
