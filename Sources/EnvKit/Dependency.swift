//
//  Dependency.swift
//  
//
//  Created by Markus Kasperczyk on 15.12.21.
//

import Vapor
import Fluent


public protocol EnvironmentValue {
    
    static func requirements(db: Database) -> EventLoopFuture<RepresentationRequirements.Kind>
    
}


public protocol Dependency : StorageKey where Value : EnvironmentValue {
    
    static var tag : String {get}
    
    static func inject(from representation: Representation.Kind,
                       env: InferredEnv,
                       db: Database) -> EventLoopFuture<Value>
    
}

// MARK: Optional

extension Optional : EnvironmentValue where Wrapped : EnvironmentValue {
    
    public static func requirements(db: Database) -> EventLoopFuture<RepresentationRequirements.Kind> {
        WrappedType.requirements(db: db).map{.optional($0)}
    }
    
}

public struct Maybe<Dep : Dependency> : Dependency {
    
    public typealias Value = Dep.Value?
    
    public static var tag : String {
        Dep.tag
    }
    
    public static func inject(from representation: Representation.Kind, env: InferredEnv, db: Database) -> EventLoopFuture<Dep.Value?> {
        if representation == .empty {
            return db.eventLoop.future(nil)
        }
        return Dep.inject(from: representation, env: env, db: db).map{$0}
    }
    
}

// MARK: Db Model

public protocol EnvironmentModel : EnvironmentValue, Model {
    
    var envTag : String {get}
    
}


public extension EnvironmentModel where IDValue == UUID {
    
    static func requirements(db: Database) -> EventLoopFuture<RepresentationRequirements.Kind> {
        db.query(Self.self).all().map {models in
                .selection(possibleValues: models.map{.init(name: $0.envTag, kind: .id(id: $0.id!))})
        }
    }
    
}


public extension Dependency where Value : EnvironmentModel, Value.IDValue == UUID {
    
    
    static func inject(from representation: Representation.Kind,
                       env: InferredEnv,
                       db: Database) -> EventLoopFuture<Value> {
        
        guard
            case .selection(value: let rep) = representation,
            case .id(let id) = rep.kind else {
                fatalError()
            }
        
        return db.query(Value.self).filter(\Value._$id == id).first().map {model in
            guard let model = model else {
                fatalError()
            }
            return model
        }
        
    }
    
}

// MARK: Auto

public protocol AutoEnvValue : EnvironmentValue {}

public extension AutoEnvValue {
    
    static func requirements(db: Database) -> EventLoopFuture<RepresentationRequirements.Kind> {
        db.eventLoop.future(.auto)
    }
    
}

// MARK: Int, Double, String


public protocol SizeCappedString : EnvironmentValue, LosslessStringConvertible {
    
    static var maxSize : Int? {get}
    
}

extension String : SizeCappedString, EnvironmentValue {
    
    public static let maxSize: Int? = nil
    
}

public extension SizeCappedString {
    
    static func requirements(db: Database) -> EventLoopFuture<RepresentationRequirements.Kind> {
        db.eventLoop.future(.rawString(maxLength: maxSize))
    }
    
}

public extension Dependency where Value : SizeCappedString {
    
    static func inject(from representation: Representation.Kind,
                       env: InferredEnv,
                       db: Database) -> EventLoopFuture<Value> {
        
        guard
            case .rawString(let str) = representation,
            let val = Value(str) else {
                fatalError()
            }
        return db.eventLoop.future(val)
        
    }
    
}


public protocol RangedInt : EnvironmentValue {
    
    static var range : ClosedRange<Int>? {get}
    init(_ intValue: Int)
    
}

extension Int : RangedInt, EnvironmentValue {
    
    public static let range : ClosedRange<Int>? = nil
    
}

public extension RangedInt {
    
    static func requirements(db: Database) -> EventLoopFuture<RepresentationRequirements.Kind> {
        db.eventLoop.future(.int(range: range))
    }
    
}

public extension Dependency where Value : RangedInt {
    
    static func inject(from representation: Representation.Kind,
                       env: InferredEnv,
                       db: Database) -> EventLoopFuture<Value> {
        
        guard case .int(let int) = representation else {
            fatalError()
        }
        return db.eventLoop.future(.init(int))
        
    }
    
}


public protocol RangedDouble : EnvironmentValue {
    
    static var range : ClosedRange<Double>? {get}
    init(_ double: Double)
    
}


extension Double : RangedDouble {
    
    public static let range : ClosedRange<Double>? = nil
    
}


public extension RangedDouble {
    
    static func requirements(db: Database) -> EventLoopFuture<RepresentationRequirements.Kind> {
        db.eventLoop.future(.double(range: nil))
    }
    
}

public extension Dependency where Value : RangedDouble {
    
    static func inject(from representation: Representation.Kind,
                       env: InferredEnv,
                       db: Database) -> EventLoopFuture<Value> {
        
        guard case .double(let num) = representation else {
            fatalError()
        }
        return db.eventLoop.future(.init(num))
        
    }
    
}


// MARK: List


extension Array : EnvironmentValue where Element : EnvironmentValue {
    
    public static func requirements(db: Database) -> EventLoopFuture<RepresentationRequirements.Kind> {
        Element.requirements(db: db).map(RepresentationRequirements.Kind.list)
    }
    
}


public struct Multiple<Dep : Dependency> : Dependency {
    
    public typealias Value = [Dep.Value]
    
    public static var tag : String {
        Dep.tag
    }
    
    public static func inject(from representation: Representation.Kind, env: InferredEnv, db: Database) -> EventLoopFuture<[Dep.Value]> {
        guard case .list(let vals) = representation else {
            fatalError()
        }
        var future : EventLoopFuture<[Dep.Value]> = db.eventLoop.future([])
        for val in vals {
            future = future.flatMap {arr in
                Dep.inject(from: val, env: env, db: db).map {newVal in
                    arr + [newVal]
                }
            }
        }
        return future
    }
    
}
