//
//  ConfigManager.swift
//  API based Authentication
//
//  Created by Thilina Shashimal Senarath on 2023-11-24.
//

import Foundation


class ConfigManager {
    
    func readPlist<T: Decodable>(name: String, modelType: T.Type) -> T? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }

            do {
                let decoder = PropertyListDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                print("Error decoding plist: \(error)")
                return nil
            }
        }
}
