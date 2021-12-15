//
//  Concurrency.swift
//  
//
//  Created by Markus Kasperczyk on 15.12.21.
//


#if compiler(>=5.5) && canImport(_Concurrency)

import Fluent

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
public extension InferredEnv {
    
    func read(from representation: Representation) async throws {
        try await read(from: representation).get()
    }
    
}

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
public extension Dependency {
    
    static func inject(from representation: Representation.Kind,
                       env: InferredEnv,
                       db: Database) async throws -> Value {
        try await inject(from: representation, env: env, db: db).get()
    }
    
}

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
public protocol AsyncDependency : Dependency {
    
    static func inject(from representation: Representation,
                       env: InferredEnv,
                       db: Database) async throws -> Value
    
}

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
public extension AsyncDependency {
    
    static func inject(from representation: Representation,
                       env: InferredEnv,
                       db: Database) -> EventLoopFuture<Value> {
        db.eventLoop.performWithTask {
            try await inject(from: representation, env: env, db: db)
        }
    }
    
}

#endif
