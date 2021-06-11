//
//  PersistConfig.swift
//  ReSwift-Persist
//
//  Created by muzix on 9/8/19.
//  Copyright © 2019 muzix. All rights reserved.
//

import Foundation
import Resolver

public struct PersistConfig {
    let persistDirectory: String
    let version: String
    let save: ((String, String) -> Void)
    let jsonDecoder: (() -> JSONDecoder)
    let jsonEncoder: (() -> JSONEncoder)
    var migration: [String: AnyMigratable]?
    var log2: ((String) -> Void)
    public var debug = false

    public init(persistDirectory: String,
                version: String,
                save: @escaping ((String, String) -> Void),
                jsonDecoder: (() -> JSONDecoder)? = nil,
                jsonEncoder: (() -> JSONEncoder)? = nil,
                migration: [String: AnyMigratable]? = nil,
                log: @escaping ((String) -> Void)) {
        self.persistDirectory = persistDirectory
        self.version = version
        self.save = save
        
        self.jsonDecoder = jsonDecoder ?? {
            let defaultDecoder = JSONDecoder()
            defaultDecoder.dateDecodingStrategy = .secondsSince1970
            return defaultDecoder
        }
        self.jsonEncoder = jsonEncoder ?? {
            let defaultEncoder = JSONEncoder()
            defaultEncoder.dateEncodingStrategy = .secondsSince1970
            return defaultEncoder
        }
        self.migration = migration
        
        self.log2 = log
    }

    func log(_ any: Any) {
        guard debug else { return }
        print("\(any)")
    }
}
