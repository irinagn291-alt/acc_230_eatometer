import Foundation

enum CatalogFault: Error, Equatable, Sendable {
    case transport
    case unknownSpecimen
    case malformed
    case cancelled
}

struct FlexibleNumber: Decodable, Sendable, Equatable {
    let value: Double?

    init(value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let number = try? container.decode(Double.self) {
            value = number
            return
        }
        if let number = try? container.decode(Int.self) {
            value = Double(number)
            return
        }
        if let string = try? container.decode(String.self) {
            let cleaned = string.replacingOccurrences(of: ",", with: ".")
            value = Double(cleaned)
            return
        }
        value = nil
    }
}

struct SearchWire: Decodable, Sendable {
    var products: [ProductWire]?
}

struct ProductPageWire: Decodable, Sendable {
    var status: Int?
    var product: ProductWire?
}

struct ProductWire: Decodable, Sendable {
    var code: String?
    var product_name: String?
    var generic_name: String?
    var brands: String?
    var image_url: String?
    var image_front_url: String?
    var image_front_small_url: String?
    var nutriments: NutrimentWire?
}

struct NutrimentWire: Decodable, Sendable {
    var energyKcal100: FlexibleNumber?
    var energy100: FlexibleNumber?
    var proteins100: FlexibleNumber?
    var carbs100: FlexibleNumber?
    var fat100: FlexibleNumber?

    enum CodingKeys: String, CodingKey {
        case energyKcal100 = "energy-kcal_100g"
        case energy100 = "energy_100g"
        case proteins100 = "proteins_100g"
        case carbs100 = "carbohydrates_100g"
        case fat100 = "fat_100g"
    }
}

enum SpecimenMapper {
    static func record(from wire: ProductWire, now: Date = Date()) -> SpecimenRecord? {
        let name = firstNonEmpty(wire.product_name, wire.generic_name, wire.brands)
        guard let name else { return nil }
        let barcode = (wire.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !barcode.isEmpty else { return nil }
        let nutrients = wire.nutriments
        return SpecimenRecord(
            barcode: barcode,
            name: name,
            brand: wire.brands?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            kcal100: GaugeMaths.kilocaloriesPerHundredGrams(
                kcal100: nutrients?.energyKcal100?.value,
                energyKj100: nutrients?.energy100?.value
            ),
            protein100: nutrients?.proteins100?.value,
            carbs100: nutrients?.carbs100?.value,
            fat100: nutrients?.fat100?.value,
            imageURL: firstNonEmpty(wire.image_front_small_url, wire.image_url, wire.image_front_url),
            shelfAsset: nil,
            refreshedAt: now
        )
    }

    static func decodeSearch(_ data: Data) throws -> [SpecimenRecord] {
        let decoded = try JSONDecoder().decode(SearchWire.self, from: data)
        return (decoded.products ?? []).compactMap { record(from: $0) }
    }

    static func decodeProduct(_ data: Data) throws -> SpecimenRecord {
        let page = try JSONDecoder().decode(ProductPageWire.self, from: data)
        if page.status == 0 {
            throw CatalogFault.unknownSpecimen
        }
        guard let product = page.product, let record = record(from: product) else {
            throw CatalogFault.unknownSpecimen
        }
        return record
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

/// Role: one client for both Open Food Facts endpoints. DTO in, domain out.
actor SpecimenCatalogClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Eatometer/1.0 (iOS; +https://eatometer.pro)"
        ]
        self.session = URLSession(configuration: configuration)
    }

    func search(terms: String) async throws -> [SpecimenRecord] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/search")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "fields", value: "code,product_name,generic_name,brands,image_url,image_front_url,image_front_small_url,nutriments"),
            URLQueryItem(name: "page_size", value: "32"),
            URLQueryItem(name: "page", value: "1")
        ]
        guard let url = components?.url else { throw CatalogFault.malformed }
        let data = try await data(for: URLRequest(url: url))
        do {
            return try SpecimenMapper.decodeSearch(data)
        } catch is DecodingError {
            throw CatalogFault.malformed
        }
    }

    func product(code: String) async throws -> SpecimenRecord {
        guard let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(encoded).json")
        else { throw CatalogFault.malformed }
        let data = try await data(for: URLRequest(url: url))
        do {
            return try SpecimenMapper.decodeProduct(data)
        } catch let fault as CatalogFault {
            throw fault
        } catch is DecodingError {
            throw CatalogFault.malformed
        }
    }

    private func data(for request: URLRequest) async throws -> Data {
        do {
            return try await perform(request)
        } catch let fault as CatalogFault {
            if fault == .transport {
                return try await perform(request)
            }
            throw fault
        } catch is CancellationError {
            throw CatalogFault.cancelled
        } catch {
            if Task.isCancelled { throw CatalogFault.cancelled }
            return try await perform(request)
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        if Task.isCancelled { throw CatalogFault.cancelled }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CatalogFault.transport }
            if http.statusCode == 404 { throw CatalogFault.unknownSpecimen }
            if (500...599).contains(http.statusCode) { throw CatalogFault.transport }
            if !(200...299).contains(http.statusCode) { throw CatalogFault.transport }
            return data
        } catch is CancellationError {
            throw CatalogFault.cancelled
        } catch let fault as CatalogFault {
            throw fault
        } catch {
            if Task.isCancelled { throw CatalogFault.cancelled }
            throw CatalogFault.transport
        }
    }
}
