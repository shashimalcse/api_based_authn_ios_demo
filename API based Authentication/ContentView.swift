//
//  ContentView.swift
//  API based Authentication
//
//  Created by Thilina Shashimal Senarath on 2023-11-22.
//

import SwiftUI
import DeviceCheck

struct FlowResponse: Codable {
    var flowId: String
    var flowStatus: String
    var flowType: String
    var nextStep: NextStep
    var links: [Link]
}

struct NextStep: Codable {
    var stepType: String
    var authenticators: [Authenticator]
}

struct Authenticator: Codable {
    var authenticatorId: String
    var authenticator: String
    var idp: String
    var metadata: Metadata
    var requiredParams: [String]?
}

struct Metadata: Codable {
    var promptType: String?
    var params: [Param]?
    var i18nKey: String?
}

struct Param: Codable {
    var param: String
    var type: String
    var order: Int
    var i18nKey: String
    var confidential: Bool
}

struct Link: Codable {
    var name: String
    var href: String
    var method: String
}

enum Screen {
    case initialSignIn
    case authenticators
}

class SharedDataObject: ObservableObject {
    
    @Published var flowResponse: FlowResponse?
    
    init(flowResponse: FlowResponse? = nil) {
            self.flowResponse = flowResponse
        }
}

struct ContentView: View {
    
    @State private var currentScreen: Screen = .initialSignIn
    @StateObject private var sharedData = SharedDataObject()
    
    var body: some View {
        
        switch currentScreen {
        case .initialSignIn:
            InitialSignInView(sharedData: sharedData, currentScreen: $currentScreen)
        case .authenticators:
            AuthenticatorsView(sharedData: sharedData, currentScreen: $currentScreen)
            
        }
    }
}

struct InitialSignInView : View {
    
    @ObservedObject var sharedData: SharedDataObject
    @State private var isLoading = false
    @State private var error: Error?
    
    @Binding var currentScreen: Screen
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.8))
                    .edgesIgnoringSafeArea(.all)
            } else {
                Spacer()
                Button(action: {
                    isLoading = true
                    sendAuthorizeRequest { result in
                        DispatchQueue.main.async {
                            isLoading = false
                            switch result {
                            case .success(let data):
                                sharedData.flowResponse = data
                                currentScreen = .authenticators
                            case .failure(let error):
                                self.error = error
                                
                            }
                        }
                    }
                }){
                    Text("Sign In")
                        .foregroundColor(.white)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10) // Rounded corners
                }
                .padding(.horizontal)
                .padding(.bottom, 60)
            }
        }
    }
    
    func sendAuthorizeRequest(completion: @escaping (Result<FlowResponse, Error>) -> Void) {
        
        generateAppAttestKey { keyId, error in
            if let keyId = keyId {
                // Use the key identifier for further attestation steps
                guard let url = URL(string: "https://5f68-203-94-95-4.ngrok-free.app/oauth2/authorize") else { return }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.setValue(keyId, forHTTPHeaderField: "x-client-attestation")

                let parameters: [String: String] = [
                    "client_id": "HRzfEMITIZYufRjsPCQCUXfK4M0a",
                    "response_type": "code",
                    "redirect_uri": "https://example-app.com/redirect",
                    "state": "logpg",
                    "scope": "openid internal_login",
                    "response_mode": "direct"
                ]
                
                request.httpBody = parameters
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "&")
                    .data(using: .utf8)

                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        completion(.failure(error))
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                            completion(.failure(URLError(.badServerResponse)))
                            return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                            // Handle the failure based on the status code
                            completion(.failure(URLError(.badServerResponse))) // or a more specific error
                            return
                    }

                    guard let data = data else {
                        completion(.failure(URLError(.badServerResponse)))
                        return
                    }
                    do {
                        let decodedData = try JSONDecoder().decode(FlowResponse.self, from: data)
                        completion(.success(decodedData))
                    } catch {
                        completion(.failure(error))
                    }
                }.resume()
            } else if let error = error {
                // Handle the error
                print("Error generating key: \(error.localizedDescription)")
            }
        }
        

    }

    func generateAppAttestKey(completion: @escaping (String?, Error?) -> Void) {
        let attestService = DCAppAttestService.shared

        // Ensure that App Attest is supported on the device
        guard attestService.isSupported else {
            completion(nil, NSError(domain: "AppAttestService", code: 0, userInfo: [NSLocalizedDescriptionKey: "App Attest not supported on this device."]))
            return
        }

        // Specify a unique key identifier for your app
        let keyId = "com.wso2.attestationApp" // Replace with your actual key identifier

        // Generate the key
        attestService.generateKey { (generatedKeyId, error) in
            if let error = error {
                        // Handle any errors
                        completion(nil, error)
                        return
                    }
            completion(generatedKeyId, nil)
        }
    }

}

struct AuthenticatorsView : View {
    
    @ObservedObject var sharedData: SharedDataObject
    @State private var isLoading = true
    @State private var error: Error?
    private var authenticators: [Authenticator] = []
    private var basicAuthenticator : Authenticator?
    private var otherAuthenticators: [Authenticator] = []
    private var flowId : String?
    @Binding var currentScreen: Screen
    
    init(sharedData: SharedDataObject, currentScreen: Binding<Screen>) {
        self.sharedData = sharedData
        if let flowResponse = sharedData.flowResponse {
            self.authenticators = flowResponse.nextStep.authenticators
            self.basicAuthenticator = self.authenticators.first(where: { $0.authenticator == "Username & Password" })
            self.otherAuthenticators = self.authenticators.filter { $0.authenticator != "Username & Password" }
            self.flowId = flowResponse.flowId
        }
        self._currentScreen = currentScreen
    }
    
    var body: some View {
        VStack {
            
            if let basicAuthenticator = basicAuthenticator {
                BasicAuthView(sharedData: sharedData, authenticator: basicAuthenticator, flowId: flowId!, currentScreen: $currentScreen)
            }
            ForEach(otherAuthenticators, id: \.authenticatorId) { authenticator in
                if authenticator.authenticator == "Google" {
                    GoogleAuthView(sharedData: sharedData, authenticator: authenticator, flowId: flowId!, currentScreen: $currentScreen)
                }
                if authenticator.authenticator == "TOTP" {
                    TOTPView(sharedData: sharedData, authenticator: authenticator, flowId: flowId!, currentScreen: $currentScreen)
                }
            }
        }
    }
}

struct BasicAuthAuthnRequestData: Encodable {
    var flowId: String
    var selectedAuthenticator: Authenticator

    struct Authenticator: Encodable {
        var authenticatorId: String
        var params: Params

        struct Params: Encodable {
            var username: String
            var password: String
        }
    }
}

struct AuthnResponse: Codable {
    var code: String
    var state: String
    var sessionState: String
    
    enum CodingKeys: String, CodingKey {
        case code
        case state
        case sessionState = "session_state"
    }
}

enum AuthnOrFlowResponse {
    case authn(AuthnResponse)
    case flow(FlowResponse)
}

struct BasicAuthView : View {
    
    @State private var username: String = ""
    @State private var password: String = ""
    @ObservedObject var sharedData: SharedDataObject
    @State private var isLoading = false
    @State private var error: Error?
    var authenticator: Authenticator
    var flowId : String
    
    @Binding var currentScreen: Screen
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.8))
                    .edgesIgnoringSafeArea(.all)
            } else {
                ZStack(alignment: .leading) {
                    if username.isEmpty {
                        Text("Username")
                            .foregroundColor(.gray)
                            .padding(.leading, 5)
                    }
                    TextField("", text: Binding(get: {username}, set: {username = $0}))
                        .padding(.horizontal, 5)
                }
                .frame(height: 50)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                ZStack(alignment: .leading) {
                    if password.isEmpty {
                        Text("Password")
                            .foregroundColor(.gray)
                            .padding(.leading, 5)
                    }
                    SecureField("", text: Binding(get: {password}, set: {password = $0}))
                        .padding(.horizontal, 5)
                }
                .frame(height: 50)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                Button(action: {
                    if !username.isEmpty, !password.isEmpty {
                        let requestData = BasicAuthAuthnRequestData(
                            flowId: flowId,
                            selectedAuthenticator: .init(
                                authenticatorId: authenticator.authenticatorId,
                                params: .init(username: username, password: password)
                            )
                        )
                        sendAuthnRequest(authnRequestData: requestData, completion: {result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let response):
                                    switch response {
                                        case .authn(let authnData):
                                            // Handle AuthnResponse here
                                            print("Received AuthnResponse: \(authnData)")
                                        case .flow(let flowData):
                                            // Handle FlowResponse here
                                            print("Received FlowResponse: \(flowData)")
                                            sharedData.flowResponse = flowData
                                        if sharedData.flowResponse?.flowStatus == "INCOMPLETE" {
                                            currentScreen = .authenticators
                                        } else {
                                            currentScreen = .initialSignIn
                                        }
                                            
                                    }
                                case .failure(let error):
                                    print(error)
                                }
                            }
                        })
                    }
                }){
                    Text("Login")
                        .foregroundColor(.white)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10) // Rounded corners
                }
                .padding(.horizontal)
                .padding(.bottom, 60)
            }
        }
    }

    func sendAuthnRequest(authnRequestData: BasicAuthAuthnRequestData, completion: @escaping (Result<AuthnOrFlowResponse, Error>) -> Void) {
        
        guard let url = URL(string: "https://5f68-203-94-95-4.ngrok-free.app/oauth2/authn") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(authnRequestData)
        } catch {
            print("Error encoding request data: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(URLError(.badServerResponse)))
                    return
            }
            
            guard httpResponse.statusCode == 200 else {
                    // Handle the failure based on the status code
                    completion(.failure(URLError(.badServerResponse))) // or a more specific error
                    return
            }
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decodedAuthnData = try JSONDecoder().decode(AuthnResponse.self, from: data)
                completion(.success(.authn(decodedAuthnData)))
            } catch {
                do {
                    let decodedFlowData = try JSONDecoder().decode(FlowResponse.self, from: data)
                    completion(.success(.flow(decodedFlowData)))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

struct TOTPAuthnRequestData: Encodable {
    var flowId: String
    var selectedAuthenticator: Authenticator

    struct Authenticator: Encodable {
        var authenticatorId: String
        var params: Params

        struct Params: Encodable {
            var token: String
        }
    }
}

struct TOTPView : View {
    
    @State private var digits: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedField: Int?
    @ObservedObject var sharedData: SharedDataObject
    @State private var isLoading = false
    @State private var error: Error?
    var authenticator: Authenticator
    var flowId : String
    
    @Binding var currentScreen: Screen
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.8))
                    .edgesIgnoringSafeArea(.all)
            } else {
                Spacer()
                HStack {
                   ForEach(0..<6, id: \.self) { index in
                       TextField("", text: $digits[index])
                           .multilineTextAlignment(.center)
                           .keyboardType(.numberPad)
                           .frame(width: 44, height: 60)
                           .border(Color.gray, width: 1)
                           .cornerRadius(2)
                           .focused($focusedField, equals: index)
                           .onChange(of: digits[index]) { _ in
                               moveToNextField(currentField: index)
                           }
                   }
                }
                .onAppear {
                   focusedField = 0
                }
                Spacer()
                Button(action: {
                    let token = digits.joined()
                    if !token.isEmpty {
                        let requestData = TOTPAuthnRequestData(
                            flowId: flowId,
                            selectedAuthenticator: .init(
                                authenticatorId: authenticator.authenticatorId,
                                params: .init(token: token)
                            )
                        )
                        sendAuthnRequest(authnRequestData: requestData, completion: {result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let response):
                                    switch response {
                                        case .authn(let authnData):
                                            // Handle AuthnResponse here
                                            print("Received AuthnResponse: \(authnData)")
                                        case .flow(let flowData):
                                            // Handle FlowResponse here
                                            print("Received FlowResponse: \(flowData)")
                                            sharedData.flowResponse = flowData
                                            currentScreen = .authenticators
                                    }
                                case .failure(let error):
                                    print(error)
                                }
                            }
                        })
                    }
                }){
                    Text("Submit")
                        .foregroundColor(.white)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10) // Rounded corners
                }
                .padding(.horizontal)
                .padding(.bottom, 60)
            }
        }
    }
    
    private func moveToNextField(currentField: Int) {
            if digits[currentField].count == 1 {
                if currentField < digits.count - 1 {
                    focusedField = currentField + 1
                } else {
                    focusedField = nil
                }
            }
        }

    func sendAuthnRequest(authnRequestData: TOTPAuthnRequestData, completion: @escaping (Result<AuthnOrFlowResponse, Error>) -> Void) {
        
        guard let url = URL(string: "https://5f68-203-94-95-4.ngrok-free.app/oauth2/authn") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(authnRequestData)
        } catch {
            print("Error encoding request data: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(URLError(.badServerResponse)))
                    return
            }
            
            guard httpResponse.statusCode == 200 else {
                    // Handle the failure based on the status code
                    completion(.failure(URLError(.badServerResponse))) // or a more specific error
                    return
            }
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let decodedAuthnData = try JSONDecoder().decode(AuthnResponse.self, from: data)
                completion(.success(.authn(decodedAuthnData)))
            } catch {
                do {
                    let decodedFlowData = try JSONDecoder().decode(FlowResponse.self, from: data)
                    completion(.success(.flow(decodedFlowData)))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}


struct GoogleAuthView : View {
    
    @State private var username: String = ""
    @State private var password: String = ""
    @ObservedObject var sharedData: SharedDataObject
    @State private var isLoading = false
    @State private var error: Error?
    var authenticator: Authenticator
    var flowId : String
    
    @Binding var currentScreen: Screen
    
    var body: some View {
        VStack {
            Button(action : {}) {
                HStack {
                    Image(systemName: "globe") // Replace with Google's logo
                        .foregroundColor(.blue)
                    Text("Sign in with Google")
                        .foregroundColor(.blue)
                        .bold()
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 50)
                        .stroke(Color.blue, lineWidth: 2)
                )
            }
        }
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
