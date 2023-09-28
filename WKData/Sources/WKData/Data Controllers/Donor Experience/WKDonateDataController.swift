import Foundation

final public class WKDonateDataController {
    
    // MARK: - Properties
    
    private let service = WKDataEnvironment.current.basicService
    private let sharedCacheStore = WKDataEnvironment.current.sharedCacheStore
    
    private var donateConfig: WKDonateConfig?
    private var paymentMethods: WKPaymentMethods?
    
    private let cacheDirectoryName = WKSharedCacheDirectoryNames.donorExperience.rawValue
    private let cacheDonateConfigFileName = "AppsDonationConfig"
    private let cachePaymentMethodsFileName = "PaymentMethods"
    
    // MARK: - Lifecycle
    
    public init() {
        
    }
    
    // MARK: - Public
    
    public func loadConfigs() -> (donateConfig: WKDonateConfig?, paymentMethods: WKPaymentMethods?) {
        
        guard donateConfig == nil,
              paymentMethods == nil else {
            return (donateConfig, paymentMethods)
        }
        
        let donateConfigResponse: WKDonateConfigResponse? = try? sharedCacheStore?.load(key: cacheDirectoryName, cacheDonateConfigFileName)
        let paymentMethodsResponse: WKPaymentMethods? = try? sharedCacheStore?.load(key: cacheDirectoryName, cachePaymentMethodsFileName)
        
        donateConfig = donateConfigResponse?.config
        paymentMethods = paymentMethodsResponse
        
        return (donateConfig, paymentMethods)
    }
    
    public func fetchConfigs(for countryCode: String, paymentsAPIKey: String, completion: @escaping (Result<Void, Error>) -> Void) {
        
        guard let service else {
            completion(.failure(WKDataControllerError.basicServiceUnavailable))
            return
        }
        
        let group = DispatchGroup()
        
        guard let paymentMethodsURL = URL.paymentMethodsAPIURL(),
              let donateConfigURL = URL.donateConfigURL() else {
            completion(.failure(WKDataControllerError.failureCreatingRequestURL))
            return
        }
        
        let paymentMethodParameters: [String: Any] = [
            "action": "getPaymentMethods",
            "country": countryCode,
            "format": "json"
        ]
        
        let donateConfigParameters: [String: Any] = [
            "action": "raw"
        ]
        
        // TODO: Send in API key
        
        var errors: [Error] = []
        
        group.enter()
        let paymentMethodsRequest = WKBasicServiceRequest(url: paymentMethodsURL, method: .GET, parameters: paymentMethodParameters)
        service.performDecodableGET(request: paymentMethodsRequest) { [weak self] (result: Result<WKPaymentMethods, Error>) in
            defer {
                group.leave()
            }
            
            guard let self else {
                return
            }
            
            switch result {
            case .success(let paymentMethods):
                self.paymentMethods = paymentMethods
                try? self.sharedCacheStore?.save(key: cacheDirectoryName, cachePaymentMethodsFileName, value: paymentMethods)
            case .failure(let error):
                errors.append(error)
            }
        }
        
        group.enter()
        let donateConfigRequest = WKBasicServiceRequest(url: donateConfigURL, method: .GET, parameters: donateConfigParameters)
        service.performDecodableGET(request: donateConfigRequest) { [weak self] (result: Result<WKDonateConfigResponse, Error>) in
            
            defer {
                group.leave()
            }
            
            guard let self else {
                return
            }
            
            switch result {
            case .success(let response):
                self.donateConfig = response.config
                try? self.sharedCacheStore?.save(key: cacheDirectoryName, cacheDonateConfigFileName, value: response)
            case .failure(let error):
                errors.append(error)
            }
        }
        
        group.notify(queue: .main) {
            if let firstError = errors.first {
                completion(.failure(firstError))
                return
            }
            
            completion(.success(()))
        }
    }
    
    public func submitPayment(amount: Decimal, currencyCode: String, paymentToken: String, donorName: String, donorEmail: String, donorAddress: String, emailOptIn: Bool?, paymentsAPIKey: String, completion: @escaping (Result<Void, Error>) -> Void) {
        
        guard let donatePaymentSubmissionURL = URL.donatePaymentSubmissionURL() else {
            completion(.failure(WKDataControllerError.failureCreatingRequestURL))
            return
        }
        
        let donorInfo: [String: Any] = [
            "name": donorName,
            "email": donorEmail,
            "address": donorAddress
        ]
        
        var parameters: [String: Any] = [
            "action": "submitPayment",
            "amount": amount,
            "currency": currencyCode,
            "payment_token": paymentToken,
            "donor_info": donorInfo
        ]
        
        if let emailOptIn {
            parameters["opt_in"] = emailOptIn
        }
        
        // TODO: Send in API key
            
        let request = WKBasicServiceRequest(url: donatePaymentSubmissionURL, method: .POST, parameters: parameters, bodyContentType: .json)
        service?.performDecodablePOST(request: request, completion: { (result: Result<WKPaymentSubmissionResponse, Error>) in
            switch result {
            case .success(let response):
                guard response.response.status == "Success" else {
                    return
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            
            }
        })
    }
}