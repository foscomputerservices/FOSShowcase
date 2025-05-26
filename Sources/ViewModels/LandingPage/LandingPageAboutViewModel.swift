// LandingPageAboutViewModel.swift
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
public struct LandingPageAboutViewModel {
    @LocalizedString public var title
    @LocalizedString public var subtitle1
    @LocalizedString public var subtitle2
    @LocalizedString public var fact1
    @LocalizedString public var fact2
    @LocalizedString public var fact3
    @LocalizedString public var fact4
    @LocalizedString public var fact5
    @LocalizedString public var fact6

    public var vmId = ViewModelId()

    public init() {}
}

public extension LandingPageAboutViewModel {
    static func stub() -> Self {
        .init()
    }
}
