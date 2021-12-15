//
//  Representation.swift
//  
//
//  Created by Markus Kasperczyk on 15.12.21.
//

import Vapor

public struct  RepresentationRequirements : Content, Equatable {

public indirect enum Kind : Content, Equatable {
    
    case int(range: ClosedRange<Int>?)
    case double(range: ClosedRange<Double>?)
    case rawString(maxLength: Int?)
    case id(id: UUID)
    case selection(possibleValues: [RepresentationRequirements])
    case list(RepresentationRequirements.Kind)
    case cons([RepresentationRequirements])
    case optional(RepresentationRequirements.Kind)
    case auto // value will be computed in code from other environment values

}
    
    public let name : String
    public let kind : Kind

}

public struct Representation : Content, Equatable {

public indirect enum Kind : Content, Equatable {
    
    case int(Int)
    case double(Double)
    case rawString(String)
    case id(id: UUID)
    case selection(value: Representation)
    case list([Representation.Kind]) // homogeneous list
    case cons([Representation]) // fixed size 'struct'
    case empty
    case auto
    
}
    
    public let name : String
    public let kind : Kind
    
    public func meets(_ requirements: RepresentationRequirements) -> Bool {
        name == requirements.name && kind.meets(requirements.kind)
    }
    
}

public extension Representation.Kind {
    
    func meets(_ requirements: RepresentationRequirements.Kind) -> Bool {
        
        if case .optional(let req) = requirements {
            return self == .empty || self.meets(req)
        }
        
        switch self {
        case .int(let val):
            guard case .int(let range) = requirements else {
                return false
            }
            return range?.contains(val) ?? true
        case .double(let val):
            guard case .double(let range) = requirements else {
                return false
            }
            return range?.contains(val) ?? true
        case .rawString(let val):
            guard case .rawString(let maxLength) = requirements else {
                return false
            }
            return maxLength.map{val.count <= $0} ?? true
        case .id(let id):
            return requirements == .id(id: id)
        case .selection(let value):
            guard case .selection(let possibleValues) = requirements else {
                return false
            }
            return possibleValues.contains(where: value.meets)
        case .list(let values):
            guard case .list(let req) = requirements else {
                return false
            }
            return values.allSatisfy{$0.meets(req)}
        case .cons(let values):
            guard case .cons(let reqs) = requirements else {
                return false
            }
            return values.count == reqs.count && zip(values, reqs).allSatisfy{$0.meets($1)}
        case .empty:
            guard case .optional = requirements else {
                return false
            }
            return true
        case .auto:
            guard case .auto = requirements else {
                return false
            }
            return true
        }
        
    }
    
}


public extension RepresentationRequirements {
    
    var emptyRepresentation : Representation {
        
        Representation(name: name, kind: kind.emptyRepresentation)
        
    }
    
}


public extension RepresentationRequirements.Kind {
    
    var emptyRepresentation : Representation.Kind {
        
        switch self {
        case .int, .double, .rawString, .selection, .list, .optional:
            return  .empty
        case .id(let id):
            return .id(id: id)
        case .cons(let reqs):
            return .cons(reqs.map(\.emptyRepresentation))
        case .auto:
            return .auto
        }
        
    }
    
}
