// BackendURLTag.swift
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

import Leaf
import Vapor

struct BackendURLTag: LeafTag {
    var name: String { "backendURL" }

    func render(_ context: LeafContext) throws -> LeafData {
        // Base URL the browser uses for backend-served assets (e.g. /Images/...).
        // Production default is EMPTY → relative, same-origin URLs ("/Images/...")
        // which nginx routes to the backend on 443 (no 8081 exposure). Override
        // with BACKEND_PUBLIC_URL only if assets must come from another origin/CDN.
        #if DEBUG
        return .string("http://localhost:8080")
        #else
        return .string(Environment.get("BACKEND_PUBLIC_URL") ?? "")
        #endif
    }
}
