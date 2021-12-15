//
//  InferredEnv.swift
//  
//
//  Created by Markus Kasperczyk on 15.12.21.
//

import Vapor
import Fluent


public extension Application {
    
    var inferredEnv : InferredEnv {
        guard let env = storage[InferredEnv.Key.self] else {
            let newEnv = InferredEnv(app: self)
            storage[InferredEnv.Key.self] = newEnv
            return newEnv
        }
        return env
    }
    
}


public struct InferredEnv {
    
    struct Key : StorageKey {
        typealias Value = InferredEnv
    }
    
    let app : Application
    
    public var stringValues : Environment {
        app.environment
    }
    
    var eagerLoaders : [EagerLoader] = []
    
    public mutating func register<Key : Dependency>(_ key: Key.Type) {
        let loader = EagerLoader(representationRequirements: {key.Value.requirements(db: $0).map{.init(name: key.tag, kind: $0)}})
        {rep, env in
            key.inject(from: rep.kind, env: env, db: env.app.db)
                .map {value in
                    env.app.storage[key] = value
                }
        }
        eagerLoaders.append(loader)
    }
    
    var requirements : RepresentationRequirements {
        var reps : [RepresentationRequirements] = []
        for loader in eagerLoaders {
            reps.append(try! loader.representationRequirements(app.db).wait())
        }
        return RepresentationRequirements(name: "Env", kind: .cons(reps))
    }
    
    func readFromFile(_ path: String) throws {
        let file = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: file)
        let representation = try JSONDecoder().decode(Representation.self, from: data)
        try read(from: representation).wait()
    }
    
    func read(from representation: Representation) -> EventLoopFuture<Void> {
        
        let requirements = self.requirements
        
        guard representation.meets(requirements) else {
            return app.eventLoopGroup.future(error: RepresentationError(reqs: requirements,
                                                                        rep: representation))
        }
        
        guard case .cons(let reps) = representation.kind else {
            fatalError()
        }
        
        var future = app.db.eventLoop.future()
        
        // parse them in order of registration
        for (loader, rep) in zip(eagerLoaders, reps) {
            future = future.flatMap {
                loader.load(rep, self)
            }
        }
        
        return future
        
    }
    
    struct Lifecycle : LifecycleHandler {
        
        struct Signature : CommandSignature {
            
            @Option(name: "envkit-file",
                      help: "The file from which EnvKit will infer the inferredEnv.")
            var file : String?
            
        }
        
        func willBoot(_ application: Application) throws {
            let signature = try Signature(from: &application.environment.commandInput)
            guard let file = signature.file else {
                return
            }
            try application.inferredEnv.readFromFile(file)
        }
        
    }
    
    struct GetEnvRequirementsCommand : Command {
        
        struct Signature : CommandSignature {}
        
        var help: String {
            "Prints the required environment values for this app as JSON."
        }
        
        
        func run(using context: CommandContext, signature: Signature) throws {
            let encoder = JSONEncoder()
            let json = try encoder.encode(context.application.inferredEnv.requirements)
            context.console.print(String(data: json, encoding: .utf8)!)
        }
        
    }
    
    struct ValidateEnvKitFile : Command {
        
        struct Signature : CommandSignature {
            
            @Argument(name: "file",
                      help: "The file to validate.")
            var file : String
            
        }
        
        var help: String {
            "Validates if the specified file can be used as EnvKit environment."
        }
        
        
        func run(using context: CommandContext, signature: Signature) throws {
            try context.application.inferredEnv.readFromFile(signature.file)
            context.console.success("Environment " + signature.file + " is valid.")
        }
        
    }
    
    public func initialize() {
        
        app.lifecycle.use(Lifecycle())
        app.commands.use(GetEnvRequirementsCommand(), as: "env-kit-requirements")
        app.commands.use(ValidateEnvKitFile(), as: "env-kit-validate")
        
    }
    
    public subscript<Key : Dependency>(_ key : Key.Type) -> Key.Value {
        guard let value = app.storage[key] else {
            fatalError(String(describing: key) + " not registered or \"read\" not called.")
        }
        return value
    }
    
}

public struct RepresentationError : Error {
    public let reqs : RepresentationRequirements
    public let rep : Representation
}

struct EagerLoader {
    
    let representationRequirements : (Database) -> EventLoopFuture<RepresentationRequirements>
    let load : (Representation, InferredEnv) -> EventLoopFuture<Void>
    
}
