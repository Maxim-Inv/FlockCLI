//
//  InitCommand.swift
//  FlockCLI
//
//  Created by Jake Heiser on 10/26/16.
//
//

import Foundation
import SwiftCLI
import Rainbow
import PathKit
import Spawn

class InitCommand: FlockCommand {
  
    let name = "--init"
    let shortDescription = "Initializes Flock in the current directory"
    
    func execute() throws {
        guard !flockIsInitialized else {
            throw CLIError.error("Flock has already been initialized".red)
        }
        
        try checkExisting()
        
        try createFiles()
        
        try updateGitIgnore()
        
        try build()
        
        print("Successfully initialized Flock!".green)
        
        printInstructions()
    }
    
    func checkExisting() throws {
        for path in [Path.flockDirectory, Path.flockfile] {
            if path.exists {
                throw CLIError.error("\(path) must not already exist".red)
            }
        }
    }
    
    func createFiles() throws {
        print("Creating Flock files...".yellow)
        
        try write(contents: flockfileDefault(), to: Path.flockfile)
        
        try createDirectory(at: Path.deployDirectory)
        
        do {
            try EnvironmentCreator.create(env: "base", defaults: baseDefaults(), link: false)
        } catch {}
        do {
            try EnvironmentCreator.create(env: "production", defaults: envConfigDefaults(), link: false)
        } catch {}
        do {
            try EnvironmentCreator.create(env: "staging", defaults: envConfigDefaults(), link: false)
        } catch {}
        
        if !Path.dependenciesFile.exists {
            try write(contents: dependenciesDefault(), to: Path.dependenciesFile)
        }
        
        try formFlockDirectory()
        
        print("Successfully created Flock files".green)
    }
    
    func build() throws {
        print("Downloading and building dependencies...".yellow)
        // Only doing this to build dependencies; actual build will fail
        do {
            try SPM.build(silent: true)
        } catch {}
        print("Successfully downloaded dependencies".green)
    }
    
    func updateGitIgnore() throws {
        print("Adding Flock files to .gitignore...".yellow)
        
        let appendText = [
            "",
            "# Flock",
            Path.buildDirectory.description,
            Path.packagesDirectory.description,
            ""
        ].joined(separator: "\n")
        
        let gitIgnorePath = Path(".gitignore")
        
        if gitIgnorePath.exists {
            let contents: String? = try? gitIgnorePath.read()
            if contents == nil || !contents!.contains("# Flock") {
                guard let gitIgnore = OutputStream(toFileAtPath: gitIgnorePath.description, append: true) else {
                    throw CLIError.error("Couldn't open .gitignore stream")
                }
                gitIgnore.open()
                gitIgnore.write(appendText, maxLength: appendText.characters.count)
                gitIgnore.close()
            }
        }
        
        print("Successfully added Flock files to .gitignore".green)
    }
    
    func printInstructions() {
        print()
        print("Follow these steps to finish setting up Flock:".cyan)
        print("1. Add `exclude: [\"Flockfile.swift\"]` to the end of your Package.swift")
        print("2. Update the required fields in \(Path.deployDirectory)/Always.swift")
        print("3. Add your servers to \(Path.deployDirectory)/Production.swift and \(Path.deployDirectory)/Staging.swift")
        print()
    }
    
    // MARK: - Defaults
  
    private func flockfileDefault() -> String {
      return [
            "import Flock",
            "",
            "Flock.configure(base: Base(), environments: [Production(), Staging()])",
            "",
            "Flock.use(.deploy)",
            "Flock.use(.swiftenv)",
            "Flock.use(.server)",
            "",
            "Flock.run()",
            ""
        ].joined(separator: "\n")
    }
    
    private func dependenciesDefault() -> String {
        return [
            "{",
            "   \"dependencies\" : [",
            "       {",
            "           \"url\" : \"https://github.com/jakeheis/Flock\",",
            "           \"major\": 0",
            "       }",
            "   ]",
            "}",
            ""
        ].joined(separator: "\n")
    }
    
    private func envConfigDefaults() -> [String] {
      return [
            "// Config.SSHAuthMethod = SSH.Key(",
            "//     privateKey: \"~/.ssh/key\",",
            "//     passphrase: \"passphrase\"",
            "// )",
            "// Servers.add(ip: \"9.9.9.9\", user: \"user\", roles: [.app, .db, .web])"
      ]
    }
    
    private func baseDefaults() -> [String] {
        var projectName = "nil // Fill this in!"
        var executableName = "nil // // Fill this in! (same as Config.projectName unless your project is divided into modules)"
        var frameworkType = "GenericServer"
        do {
            let dump = try SPM.dump()

            guard let name = dump["name"] as? String else {
                throw SPM.Error.processFailed
            }
            projectName = "\"\(name)\""
            
            if let targets = dump["targets"] as? [[String: Any]], !targets.isEmpty {
                var targetNames = Set<String>()
                var dependencyNames = Set<String>()
                for target in targets {
                    guard let targetName = target["name"] as? String,
                        let dependencies = target["dependencies"] as? [String] else {
                            continue
                    }
                    targetNames.insert(targetName)
                    dependencyNames.formUnion(dependencies)
                }
                let executables = targetNames.subtracting(dependencyNames)
                if executables.count == 1 {
                    executableName = "\"\(executables.first!)\""
                }
            } else {
                executableName = projectName
            }
            
            if let dependencies = dump["dependencies"] as? [[String: Any]] {
                for dependency in dependencies {
                    let url = dependency["url"] as? String
                    if url == "https://github.com/vapor/vapor" {
                        frameworkType = "Vapor"
                        break
                    } else if url == "https://github.com/Zewo/Zewo" {
                        frameworkType = "Zewo"
                        break
                    } else if url == "https://github.com/IBM-Swift/Kitura" {
                        frameworkType = "Kitura"
                        break
                    } else if url == "https://github.com/PerfectlySoft/Perfect" {
                        frameworkType = "Perfect"
                        break
                    }
                }
            }
        } catch {}
        
        return [
            "Config.projectName = \(projectName)",
            "Config.executableName = \(executableName)",
            "Config.repoURL = nil // Fill this in!",
            "",
            "Config.serverFramework = \(frameworkType)Framework()",
            "Config.processController = Nohup() // Other option: Supervisord()",
            "",
            "// IF YOU PLAN TO RUN `flock tools` AS THE ROOT USER BUT `flock deploy` AS A DEDICATED DEPLOY USER,",
            "// (as you should, see https://github.com/jakeheis/Flock/blob/master/README.md#permissions)",
            "// SET THIS VARIABLE TO THE NAME OF YOUR (ALREADY CREATED) DEPLOY USER BEFORE RUNNING `flock tools`:",
            "// Config.supervisordUser = \"deploy:deploy\"",
            "",
            "// Optional config:",
            "// Config.deployDirectory = \"/var/www\"",
            "// Config.swiftVersion = \"3.0.2\" // If you have a `.swift-version` file, this line is not necessary"
        ]
    }
  
}
