// LandingPageFooterViewModel.swift
//
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
import Foundation

@ViewModel
public struct LandingPageFooterViewModel {
    @LocalizedString public var companyTitle
    @LocalizedString public var aboutSubtitle

    @LocalizedString public var servicesTitle
    @LocalizedString public var service1Text
    @LocalizedString public var service2Text
    @LocalizedString public var service3Text
    @LocalizedString public var service4Text

    @LocalizedString public var quickLinksTitle
    @LocalizedString public var quickLink1Text
    @LocalizedString public var quickLink2Text
    @LocalizedString public var quickLink3Text
    @LocalizedString public var quickLink4Text

    @LocalizedString public var copyrightText

    public var vmId = ViewModelId()

    public init() {}
}

public extension LandingPageFooterViewModel {
    static func stub() -> Self {
        .init()
    }
}
