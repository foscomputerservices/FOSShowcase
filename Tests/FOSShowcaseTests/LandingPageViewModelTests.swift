// LandingPageViewModelTests.swift
//
// Created by David Hunt on 1/2/25
// Copyright 2025 FOS Computer Services, LLC
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
import FOSShowcase
import FOSTesting
import Foundation
import Testing

@Suite("My Test Suite", .serialized)
final class LandingPageViewModelTests: LocalizableTestCase {
    @Test func validViewModel() async throws {
        try expectCodable(LandingPageViewModel.self)
        try expectVersionedViewModel(LandingPageViewModel.self)
    }

    let locStore: LocalizationStore
    var locales: Set<Locale> { [Self.en, Self.es] }
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(bundle: Bundle.main)
    }
}
