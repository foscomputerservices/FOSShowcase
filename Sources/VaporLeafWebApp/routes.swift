// routes.swift
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
import Vapor
import ViewModels

func routes(_ app: Application) throws {
    app.get("") { req async throws -> View in
        return try await req.view.render(
            "LandingPageView",
            app.resolve(from: LandingPageRequest())
        )
    }
}

extension Application {
    func resolve<Request>(from request: Request) async throws -> Request.ResponseBody? where Request: ViewModelRequest, Request.ResponseBody: ViewModel {
        try await Self.webServerURL(for: request)
            .fetch()
    }

    private static func webServerURL<Request>(for request: Request) -> URL where Request: ViewModelRequest {
        // TODO: Support for baseURL
        // TODO: Use standard URL support from Request that uses Query
        .init(string: "http://localhost:8080")!
            .appendingPathComponent(Request.path)
    }
}
