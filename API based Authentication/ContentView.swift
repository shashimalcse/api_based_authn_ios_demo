//
//  ContentView.swift
//  API based Authentication
//
//  Created by Thilina Shashimal Senarath on 2023-11-22.
//

import SwiftUI
import DeviceCheck
import AppAuthCore
import AppAuth
import GoogleSignIn

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

struct AuthConfig: Decodable {
    
    var clientId: String
    var redirectURL: String
    var authorizeEndpoint: String
    var tokenEndpoint: String
    var logoutEndpoint: String
    var userInfoEndpoint: String
    var authnEndpoint: String
}


enum Screen {
    case initialSignIn
    case authenticators
    case profile
}

class AuthService: ObservableObject {
    var authState: OIDAuthState?
    var authConfig: AuthConfig?
    let authStateKey: String = "authState";
    let suiteName: String = "suiteName"
    
    init(authState: OIDAuthState? = nil) {
        self.authState = authState
        self.loadState()
        let configManager = ConfigManager()
        self.authConfig = configManager.readPlist(name: "AuthConfig", modelType: AuthConfig.self)
    }
    
    func tokenExchange(authorizationCode: String, completion: @escaping (Result<String, Error>) -> Void) {
        
        let tokenRequest = OIDTokenRequest(
            configuration: authState?.lastAuthorizationResponse.request.configuration ?? OIDServiceConfiguration(authorizationEndpoint: URL(string: self.authConfig!.authorizeEndpoint)!, tokenEndpoint: URL(string: self.authConfig!.tokenEndpoint)!),
            grantType: OIDGrantTypeAuthorizationCode,
            authorizationCode: authorizationCode,
            redirectURL: URL(string: self.authConfig!.redirectURL)!,
            clientID: self.authConfig!.clientId,
            clientSecret: nil,
            scopes: nil,
            refreshToken: nil,
            codeVerifier: nil,
            additionalParameters: nil
        )
        
        OIDAuthorizationService.perform(tokenRequest) { response, error in
            if let tokenResponse = response {
                
                if (self.authState != nil) {
                    self.authState?.update(with: tokenResponse, error: error)
                } else {
                    self.authState = OIDAuthState(authorizationResponse: nil, tokenResponse: tokenResponse, registrationResponse: nil)
                }
                if let accessToken = tokenResponse.accessToken {
                    completion(.success(accessToken))
                    self.saveState()
                } else {
                    completion(.failure(NSError(domain: "AuthService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Access token is nil"])))
                }
            } else if let error = error {
                completion(.failure(error))
            }
        }
    }
    
    func logout(completion: @escaping (Bool) -> Void) {
        
        if let idToken = authState?.lastTokenResponse?.idToken {
            let request = OIDEndSessionRequest(
                configuration:OIDServiceConfiguration(authorizationEndpoint: URL(string: self.authConfig!.authorizeEndpoint)!, tokenEndpoint: URL(string: self.authConfig!.tokenEndpoint)!, issuer: nil, registrationEndpoint: nil, endSessionEndpoint: URL(string: self.authConfig!.logoutEndpoint)!),
                idTokenHint: idToken,
                postLogoutRedirectURL: URL(string: self.authConfig!.redirectURL)!,
                additionalParameters: nil)
            
            guard let rootViewController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                completion(false)
                return
            }
            guard let agent = OIDExternalUserAgentIOS(presenting: rootViewController) else {
                return
            }
            OIDAuthorizationService.present(request, externalUserAgent: agent) { _, error in
                if error != nil {
                    completion(false)
                } else {
                    self.clearAuthState()
                    completion(true)
                }
            }
        } else {
            self.clearAuthState()
            completion(true)
        }
        
    }
    
    private func clearAuthState() {
        
        authState = nil
        saveState()
    }
    
    // Load authState in UserDefault
    private func loadState() {
        
        guard let data = UserDefaults(suiteName: suiteName)?.object(forKey: authStateKey) as? Data else {
            return
        }
        do {
            if let authState = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) {
                self.authState =  authState
            }
        } catch {
            
        }
    }
        
    
    // Save authState in UserDefault
    private func saveState() {
            
        var data: Data? = nil
        
        if let authState = authState {
            do {
                data = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: false)
            } catch {
                
            }
        }
        
        if let userDefaults = UserDefaults(suiteName: suiteName) {
            userDefaults.set(data, forKey: authStateKey)
            userDefaults.synchronize()
        }
    }
}

class SharedDataObject: ObservableObject {
    
    @Published var flowResponse: FlowResponse?
    @Published var authService = AuthService()
    @Published var isLoading = false
    @Published var showErrorCard = false
    @Published var errorMessage: String?
    
    init(flowResponse: FlowResponse? = nil) {
        
        self.flowResponse = flowResponse
    }
}

struct ContentView: View {
    
    @State private var currentScreen: Screen = .initialSignIn
    @StateObject private var sharedData = SharedDataObject()
    
    var body: some View {
        ZStack {
            HStack {
                if (sharedData.authService.authState != nil) {
                    ProfileView(sharedData: sharedData, currentScreen: $currentScreen)
                } else {
                    switch currentScreen {
                        case .initialSignIn:
                            InitialSignInView(sharedData: sharedData, currentScreen: $currentScreen)
                        case .authenticators:
                            AuthenticatorsView(sharedData: sharedData, currentScreen: $currentScreen)
                        case .profile:
                            ProfileView(sharedData: sharedData, currentScreen: $currentScreen)
                    }
                }

            }
            if sharedData.showErrorCard {
                ErrorCardView(message: sharedData.errorMessage ?? "Error occured!")
                    .transition(.move(edge: .bottom))
                    .animation(.easeInOut, value: sharedData.showErrorCard)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(10)
                    .opacity(0.8)
                    .padding()
                    .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height - 100)
            }
        }
        
    }
}

struct ErrorCardView: View {
    var message: String
    var body: some View {
        VStack {
            Text(message)
                .foregroundColor(.white)
                .padding()
        }
    }
}

struct InitialSignInView : View {
    
    @ObservedObject var sharedData: SharedDataObject
    
    @Binding var currentScreen: Screen
    
    var body: some View {
        ZStack{
            VStack {
                if sharedData.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.8))
                        .edgesIgnoringSafeArea(.all)
                } else {
                    Spacer()
                    Text("API Based Authentication")
                        .font(.largeTitle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    Spacer()
                    Button(action: {
                        sharedData.isLoading = true
                        sendAuthorizeRequest { result in
                            DispatchQueue.main.async {
                                sharedData.isLoading = false
                                switch result {
                                case .success(let data):
                                    sharedData.flowResponse = data
                                    currentScreen = .authenticators
                                case .failure(_):
                                    triggerError(message: "Error occured while authroized call")
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
    }
    
    func triggerError(message: String) {
        sharedData.errorMessage = message
        sharedData.showErrorCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            sharedData.showErrorCard = false
        }
    }
    
    func sendAuthorizeRequest(completion: @escaping (Result<FlowResponse, Error>) -> Void) {
        
        generateAppAttestKey { keyId, error in
            if let keyId = keyId {
                
                guard let url = URL(string: sharedData.authService.authConfig!.authorizeEndpoint) else { return }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.setValue(keyId, forHTTPHeaderField: "x-client-attestation")
                
                let parameters: [String: String] = [
                    "client_id": sharedData.authService.authConfig!.clientId,
                    "response_type": "code",
                    "redirect_uri": sharedData.authService.authConfig!.redirectURL,
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
                        completion(.failure(URLError(.badServerResponse)))
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
                completion(.failure(error))
            }
        }
        
        
    }
    
    func generateAppAttestKey(completion: @escaping (String?, Error?) -> Void) {
        let attestService = DCAppAttestService.shared
        
        guard attestService.isSupported else {
            completion(nil, NSError(domain: "AppAttestService", code: 0, userInfo: [NSLocalizedDescriptionKey: "App Attest not supported on this device."]))
            return
        }
        
        attestService.generateKey { (generatedKeyId, error) in
            if let error = error {
                completion(nil, error)
                return
            }
            completion(generatedKeyId, nil)
        }
    }
    
}

struct ProfileView : View {
    
    @ObservedObject var sharedData: SharedDataObject
    @State private var isLoading = true
    @State private var error: Error?
    @Binding var currentScreen: Screen
    
    var body: some View {
        VStack {
            Text("Profile")
            Button(action: {
                sharedData.authService.logout(completion: { result in
                    if result {
                        currentScreen = .initialSignIn
                    }
                })
            }){
            Text("Logout")
                    .foregroundColor(.white)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom, 60)
            
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
    var authenticator: Authenticator
    var flowId : String
    
    @Binding var currentScreen: Screen
    
    var body: some View {
        VStack {
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
                    sharedData.isLoading = true
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
                                    sharedData.authService.tokenExchange(authorizationCode: authnData.code, completion: { result in
                                        switch result {
                                        case .success(_) :
                                            currentScreen = .profile
                                        case .failure(_):
                                            triggerError(message: "Error occured while token call")
                                            currentScreen = .initialSignIn
                                        }
                                    })
                                case .flow(let flowData):
                                    
                                    sharedData.flowResponse = flowData
                                    if sharedData.flowResponse?.flowStatus == "INCOMPLETE" {
                                        currentScreen = .authenticators
                                    } else {
                                        currentScreen = .initialSignIn
                                    }
                                    sharedData.isLoading = false
                                    
                                }
                            case .failure(_):
                                triggerError(message: "Error occured while authn call")
                                currentScreen = .initialSignIn
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
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom, 60)
        }
    }
    
    func triggerError(message: String) {
        sharedData.errorMessage = message
        sharedData.showErrorCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            sharedData.showErrorCard = false
        }
    }
    
    func sendAuthnRequest(authnRequestData: BasicAuthAuthnRequestData, completion: @escaping (Result<AuthnOrFlowResponse, Error>) -> Void) {
        
        guard let url = URL(string: sharedData.authService.authConfig!.authnEndpoint) else { return }
        
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
                completion(.failure(URLError(.badServerResponse)))
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
    @State private var error: Error?
    var authenticator: Authenticator
    var flowId : String
    
    @Binding var currentScreen: Screen
    
    var body: some View {
        VStack {
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
                    sharedData.isLoading = true
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
                                    sharedData.authService.tokenExchange(authorizationCode: authnData.code, completion: { result in
                                        switch result {
                                        case .success(_) :
                                            currentScreen = .profile
                                        case .failure(_):
                                            triggerError(message: "Error occured while token call")
                                            currentScreen = .initialSignIn
                                        }
                                    })
                                case .flow(let flowData):
                                    sharedData.flowResponse = flowData
                                    currentScreen = .authenticators
                                }
                            case .failure(_):
                                triggerError(message: "Error occured while authn call")
                                currentScreen = .initialSignIn
                            }
                            sharedData.isLoading = false                       }
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
    
    private func moveToNextField(currentField: Int) {
        if digits[currentField].count == 1 {
            if currentField < digits.count - 1 {
                focusedField = currentField + 1
            } else {
                focusedField = nil
            }
        }
    }
    
    func triggerError(message: String) {
        sharedData.errorMessage = message
        sharedData.showErrorCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            sharedData.showErrorCard = false
        }
    }
    
    func sendAuthnRequest(authnRequestData: TOTPAuthnRequestData, completion: @escaping (Result<AuthnOrFlowResponse, Error>) -> Void) {
        
        guard let url = URL(string: sharedData.authService.authConfig!.authnEndpoint) else { return }
        
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
                completion(.failure(URLError(.badServerResponse)))
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

struct GoogleAuthnRequestData: Encodable {
    var flowId: String
    var selectedAuthenticator: Authenticator
    
    struct Authenticator: Encodable {
        var authenticatorId: String
        var params: Params
        
        struct Params: Encodable {
            var accessToken: String
            var idToken: String
        }
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
            Button(action : {
                signIn(completion: { result in
                    switch result {
                        
                    case .success(let data):
                        sendAuthnRequest(authnRequestData: data, completion: {result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let response):
                                    switch response {
                                    case .authn(let authnData):
                                        sharedData.authService.tokenExchange(authorizationCode: authnData.code, completion: { result in
                                            switch result {
                                            case .success(_) :
                                                currentScreen = .profile
                                            case .failure(_):
                                                triggerError(message: "Error occured while token call")
                                                currentScreen = .initialSignIn
                                            }
                                        })
                                    case .flow(let flowData):
                                        sharedData.flowResponse = flowData
                                        currentScreen = .authenticators
                                    }
                                case .failure(_):
                                    triggerError(message: "Error occured while authn call")
                                    currentScreen = .initialSignIn
                                }
                                sharedData.isLoading = false                       }
                        })
                    case .failure(_):
                        currentScreen = .initialSignIn
                    }
                    
                })
            }) {
                HStack {
                    Image(systemName: "globe")
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
    
    func triggerError(message: String) {
        sharedData.errorMessage = message
        sharedData.showErrorCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            sharedData.showErrorCard = false
        }
    }
    
    func signIn(completion: @escaping (Result<GoogleAuthnRequestData, Error>) -> Void) {
        
        guard let presentingViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else { return }
        
        GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            completion: { signInResult, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let result = signInResult else {
                    return
                }
                let accessToken = result.user.accessToken
                let idToken = result.user.idToken
                let requestData = GoogleAuthnRequestData(
                    flowId: flowId,
                    selectedAuthenticator: .init(
                        authenticatorId: authenticator.authenticatorId,
                        params: .init(accessToken: accessToken.tokenString, idToken: idToken!.tokenString)
                    )
                )
                completion(.success(requestData))
            }
        )
    }
    
    func sendAuthnRequest(authnRequestData: GoogleAuthnRequestData, completion: @escaping (Result<AuthnOrFlowResponse, Error>) -> Void) {
        
        guard let url = URL(string: sharedData.authService.authConfig!.authorizeEndpoint) else { return }
        
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
                completion(.failure(URLError(.badServerResponse)))
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
