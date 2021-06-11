//
//  PersistReducer.swift
//  ReSwift-Persist
//
//  Created by muzix on 9/8/19.
//  Copyright © 2019 muzix. All rights reserved.
//
import Foundation
#if os(Android)
    import FoundationNetworking
#endif
import ReSwift
import RxSwift
//import Logging


//private let log = Logger(label: "dispatch-tests")

struct VersionInfo: Codable {
    let current: String
}

struct PersistConfigState<State> {
    let persistConfig: PersistConfig
    let state: State
}

func persistReducer<State: PersistState>(
    config: PersistConfig,
    baseReducer: @escaping Reducer<State>
    ) -> Reducer<State>  {
    
    
    var saveDataSubject = PublishSubject<PersistConfigState<State>>()
    //var saveDataSubject2: PublishSubject = PublishSubject<Double>()
    
    saveDataSubject
        //.debounce(2, scheduler: MainScheduler.instance)
        .throttle(RxTimeInterval.seconds(1), scheduler: MainScheduler.instance)
        .concatMap{ r in
            //here we have been asked to open, but we are still open, so we close:
            return Observable<(Bool)>.create({ observer in
                
                    DispatchQueue.background(background: {
                        saveData(config: r.persistConfig, newState: r.state)
                    }, completion:{
                        observer.onNext(true)
                        observer.onCompleted()
                    })
                
                    return Disposables.create()
                })
        }
        
        .subscribe{ r in
            
            //log.info("\("asad saved sensibly: " + "")" )
                        
            config.log2("saved sensibly")
        }
    
    return { (_ action: Action, _ state: State?) in
        switch action {
        case _ as ReSwiftInit: // Try restore state right after initialization of ReSwift
            guard let restoredState: State = restoreData(config: config) else {
                return baseReducer(action, state)
            }
            return restoredState
        default: // Save state for any new action
            
            config.log2("asad persist thing happening!")
            
            let newState = baseReducer(action, state)

            // Should skip persist step ?
            if let state = state, state.shouldSkipPersist(newState) {
                return newState
            }
            
            var persistConfigState = PersistConfigState(persistConfig: config, state: newState)
            saveDataSubject.onNext(persistConfigState)
            
            return newState
        }
    }
}

private func restoreData<State: PersistState>(config: PersistConfig) -> State? {
    let stateTypeName = String(describing: State.self)
    let stateDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(config.persistDirectory)
        .appendingPathComponent(stateTypeName)

    config.log2("STATE DIRECTORY: \(stateDirectory.absoluteString)")

    let currentVersion = getCurrentSchemaVersion(config: config, stateTypeName: stateTypeName)
    let isMigrationNeeded = currentVersion != config.version

    let newVersionDirectory = stateDirectory.appendingPathComponent(config.version)
    if isMigrationNeeded && FileManager.default.fileExists(atPath: newVersionDirectory.path) {
        config.log2("Migration will use existed directory '\(config.version)' for new version!")
    }

    // MIGRATE DATA
    if isMigrationNeeded {
        do {
            try runMigration(State.self, config: config, oldVersion: currentVersion, directory: stateDirectory)
        } catch {
            config.log(error)
        }
    } else {
        config.log2("No migration needed.")
    }

    // RESTORE STATE FROM NEW VERSION
    let versionDirectory = stateDirectory.appendingPathComponent(config.version)
    let filename = versionDirectory.appendingPathComponent("\(stateTypeName).json")

    // No stored state. Return initial state.
    guard FileManager.default.fileExists(atPath: filename.path) else {
        config.log2("Persisted data not found!")
        return nil
    }

    // Try read json file and return stored state.
    do {
        let storedState: State = try readDecodableFromFile(url: filename)
        config.log2("State restored successfully!")
        return storedState
    } catch {
        print(error)
        return nil
    }
}

private func runMigration<NewState: PersistState>(_ newStateType: NewState.Type,
                                                  config: PersistConfig,
                                                  oldVersion: String?,
                                                  directory: URL) throws {
    config.log2("Migration started")
    let stateTypeName = String(describing: NewState.self)
    // Create new version folder
    let versionDirectory = directory.appendingPathComponent(config.version)
    createDirectoryIfNotExist(directoryPath: versionDirectory.path)

    // Store versioning file
    let versioningFilePath = directory.appendingPathComponent("version.json")
    let versionInfo = VersionInfo(current: config.version)
    let versionInfoData = try config.jsonEncoder().encode(versionInfo)
    let versionInfoString = String(data: versionInfoData, encoding: .utf8)
    try versionInfoString?.write(to: versioningFilePath, atomically: true, encoding: .utf8)
    config.log2("Version \(config.version) successfully settled.")

    // Return if no prev version found
    guard let oldVersion = oldVersion else {
        config.log2("No prev version found!")
        return
    }

    // Run migration
    let oldVersionDirectory = directory.appendingPathComponent(oldVersion)
    let oldStateFilePath = oldVersionDirectory.appendingPathComponent("\(stateTypeName).json")
    config.log2("Look for old file at: \(oldStateFilePath.path)")

    let newStateFilePath = versionDirectory.appendingPathComponent("\(stateTypeName).json")
    // Decode old data using old schema
    if let migration = config.migration?[oldVersion] {
        config.log2("Run migration with migration info provided.")
        do {
            if let newState = try migration._migrate(filePath: oldStateFilePath) as? NewState {
                // Write new state to new directory
                saveData(config: config, newState: newState)
                config.log2("Migration succeed!")
            } else {
                config.log2("Can not execute migration item with newState: \(String(describing: NewState.self))")
            }
        } catch {
            config.log2("Migration item failed: \(error)")
        }
    } else {
        if !FileManager.default.fileExists(atPath: newStateFilePath.path) {
            try FileManager.default.copyItem(atPath: oldStateFilePath.path, toPath: newStateFilePath.path)
            config.log2("No migration provided. Just copy the old data to the new version directory") //swiftlint:disable:this line_length
        } else {
            config.log2("File exists at path: \(newStateFilePath.path). Migration skipped.")
        }
    }
}

private func getCurrentSchemaVersion(config: PersistConfig, stateTypeName: String) -> String? {
    // Read state versioning file
    let stateDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(config.persistDirectory)
        .appendingPathComponent(stateTypeName)
    let versioningFileName = stateDirectory.appendingPathComponent("version.json")
    guard FileManager.default.fileExists(atPath: versioningFileName.path) else {
        config.log2("Versioning file not found!")
        return nil
    }
    do {
        let versionInfo: VersionInfo = try readDecodableFromFile(url: versioningFileName)
        return versionInfo.current
    } catch {
        config.log(error)
        return nil
    }
}

private func readDecodableFromFile<T: Decodable>(url: URL, jsonDecoder: JSONDecoder = JSONDecoder()) throws ->  T  {
    let contents = try Data(contentsOf: url)
    let instance = try jsonDecoder.decode(T.self, from: contents)
    return instance
}





private func saveData<State: PersistState>(config: PersistConfig, newState: State) {
        do {
            let json = try config.jsonEncoder().encode(newState)
            let jsonString = String(data: json, encoding: .utf8)
            let stateTypeName = String(describing: State.self)
            let stateDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(config.persistDirectory)
                .appendingPathComponent(stateTypeName)
            let versionDirectory = stateDirectory.appendingPathComponent(config.version)
            createDirectoryIfNotExist(directoryPath: versionDirectory.path)

            // Try save the state to json file
//            let filename = versionDirectory.appendingPathComponent("\(stateTypeName).json")
//            try jsonString?.write(to: filename, atomically: true, encoding: .utf8)
            
            config.save("\(stateTypeName).json", jsonString ?? "")
            
            config.log2("State have been saved successfully!")
        } catch {
            config.log(error)
        }
}

private func createDirectoryIfNotExist(directoryPath: String) {
    if !FileManager.default.fileExists(atPath: directoryPath) {
        try? FileManager.default.createDirectory(atPath: directoryPath,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
    }
}

extension DispatchQueue {

    static func background(delay: Double = 0.0, background: (()->Void)? = nil, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .background).async {
            background?()
            if let completion = completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: {
                    completion()
                })
            }
        }
    }

}
