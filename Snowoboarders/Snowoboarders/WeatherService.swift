//
//  WeatherService.swift
//  Snowoboarders
//

import Foundation
import CoreLocation
import Combine

struct Weather {
    let temperatureCelsius: Double
    let windMetersPerSecond: Double
    let description: String
    let iconCode: String

    var isClearDay: Bool { iconCode == "01d" }

    var symbolName: String {
        switch iconCode {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.stars.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "smoke.fill"
        case "09d", "09n": return "cloud.heavyrain.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.rain.fill"
        case "13d", "13n": return "snow"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
}

private struct OpenWeatherResponse: Decodable {
    struct Main: Decodable { let temp: Double }
    struct Wind: Decodable { let speed: Double }
    struct WeatherEntry: Decodable { let description: String; let icon: String }

    let main: Main
    let wind: Wind
    let weather: [WeatherEntry]
}

@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var weather: Weather?
    @Published private(set) var errorMessage: String?

    private var refreshTimer: Timer?
    private static let refreshInterval: TimeInterval = 600

    func start(location: @escaping () -> CLLocation?) {
        refreshTimer?.invalidate()
        refresh(location: location())
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh(location: location())
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh(location: CLLocation?) {
        guard let location else { return }
        guard !Secrets.openWeatherMapAPIKey.isEmpty else {
            errorMessage = "No OpenWeatherMap API key set"
            return
        }

        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "appid", value: Secrets.openWeatherMapAPIKey),
        ]
        guard let url = components.url else { return }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    errorMessage = "Weather fetch failed (\(http.statusCode)): \(body)"
                    return
                }
                let decoded = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
                self.weather = Weather(
                    temperatureCelsius: decoded.main.temp,
                    windMetersPerSecond: decoded.wind.speed,
                    description: decoded.weather.first?.description.uppercased() ?? "",
                    iconCode: decoded.weather.first?.icon ?? ""
                )
                errorMessage = nil
            } catch {
                errorMessage = "Weather fetch failed: \(error.localizedDescription)"
            }
        }
    }
}
