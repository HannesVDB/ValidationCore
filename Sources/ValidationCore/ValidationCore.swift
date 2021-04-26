import base45_swift
import Gzip
import UIKit

/// Electronic Health Certificate Validation Core
///
/// This struct provides an interface for validating EHN Health certificates generated by https://dev.a-sit.at/certservice
public struct ValidationCore {
    private let PREFIX = "HC1:"
    private let CERT_SERVICE_URL = "https://dgc.a-sit.at/ehn/"
    private let CERT_PATH = "cert/"

    
    private var completionHandler : ((Result<ValidationResult, ValidationError>) -> ())?
    private var scanner : QrCodeScanner?
    
    public init(){}

    
    //MARK: - Public API
    
    /// Instantiate a QR code scanner and validate the scannned EHN health certificate
    public mutating func validateQrCode(_ vc : UIViewController, prompt: String = "Scan QR Code", _ completionHandler: @escaping (Result<ValidationResult, ValidationError>) -> ()){
        self.completionHandler = completionHandler
        self.scanner = QrCodeScanner()
        scanner?.scan(vc, prompt, self)
    }
    
    /// Validate an Base45-encoded EHN health certificate
    public func validate(encodedData: String, _ completionHandler: @escaping (Result<ValidationResult, ValidationError>) -> ()) {
        guard let unprefixedEncodedString = removeScheme(prefix: PREFIX, from: encodedData) else {
            completionHandler(.failure(.INVALID_SCHEME_PREFIX))
            return
        }
        
        guard let decodedData = decode(unprefixedEncodedString) else {
            completionHandler(.failure(.BASE_45_DECODING_FAILED))
            return
        }
        
        guard let decompressedData = decompress(decodedData) else {
            completionHandler(.failure(.DECOMPRESSION_FAILED))
            return
        }

        guard let cose = cose(from: decompressedData) else {
            completionHandler(.failure(.COSE_DESERIALIZATION_FAILED))
            return
        }
        retrieveSignatureCertificate(with: cose.keyId) { cert in
            completionHandler(.success(ValidationResult(isValid: cose.hasValidSignature(for: cert), payload: cose.payload.euHealthCert)))
        }
    }
    

    //MARK: - Helper Functions
    
    /// Retrieves the signature certificate for a given keyId
    private func retrieveSignatureCertificate(with keyId: String?, _ completionHandler: @escaping (String?)->()) {
        guard let keyId = keyId,
              let url = URL(string: "\(CERT_SERVICE_URL)\(CERT_PATH)\(keyId)") else {
            return
        }

        var request = URLRequest(url: url)
        request.addValue("text/plain", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { body, response, error in
            guard error == nil,
                  let status = (response as? HTTPURLResponse)?.statusCode,
                  200 == status,
                  let body = body else {
                completionHandler(nil)
                return
            }
            let encodedCert = String(data: body, encoding: .utf8)
            completionHandler(encodedCert)
        }.resume()
    }
    
    /// Strips a given scheme prefix from the encoded EHN health certificate
    private func removeScheme(prefix: String, from encodedString: String) -> String? {
        guard encodedString.starts(with: prefix) else {
            return nil
        }
        return String(encodedString.dropFirst(prefix.count))
    }
    
    /// Base45-decodes an EHN health certificate
    private func decode(_ encodedData: String) -> Data? {
        return try? encodedData.fromBase45()
    }
    
    /// Decompress the EHN health certificate using ZLib
    private func decompress(_ encodedData: Data) -> Data? {
        return try? encodedData.gunzipped()
    }

    /// Creates COSE structure from EHN health certificate
    private func cose(from data: Data) -> Cose? {
       return Cose(from: data)
    }
    
}

// MARK: - QrCodeReceiver

extension ValidationCore : QrCodeReceiver {
    public func canceled() {
        completionHandler?(.failure(.USER_CANCELLED))
    }
    
    /// Process the scanned EHN health certificate
    public func onQrCodeResult(_ result: String?) {
        guard let result = result,
              let completionHandler = self.completionHandler else {
            self.completionHandler?(.failure(.QR_CODE_ERROR))
            return
        }
        validate(encodedData: result, completionHandler)
    }
}



