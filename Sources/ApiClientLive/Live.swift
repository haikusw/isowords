@_exported import ApiClient
import Combine
import ComposableArchitecture
import Foundation
import ServerRouter
import SharedModels

extension ApiClient {
  private static let baseUrlKey = "co.pointfree.isowords.apiClient.baseUrl"
  private static let currentUserEnvelopeKey = "co.pointfree.isowords.apiClient.currentUserEnvelope"

  public static func live(
    baseUrl defaultBaseUrl: URL = URL(string: "http://localhost:9876")!,
    sha256: @escaping (Data) -> Data
  ) -> Self {
    #if DEBUG
      var baseUrl = UserDefaults.standard.url(forKey: baseUrlKey) ?? defaultBaseUrl {
        didSet {
          UserDefaults.standard.set(baseUrl, forKey: baseUrlKey)
        }
      }
    #else
      var baseUrl = URL(string: "https://www.isowords.xyz")!
    #endif

    let router = ServerRouter(
      date: Date.init,
      decoder: decoder,
      encoder: encoder,
      secrets: secrets.split(separator: ",").map(String.init),
      sha256: sha256
    )

    var currentPlayer = UserDefaults.standard.data(forKey: currentUserEnvelopeKey)
      .flatMap({ try? decoder.decode(CurrentPlayerEnvelope.self, from: $0) })
    {
      didSet {
        UserDefaults.standard.set(
          currentPlayer.flatMap { try? encoder.encode($0) },
          forKey: currentUserEnvelopeKey
        )
      }
    }

    return Self(
      apiRequest: { route in
        ApiClientLive.apiRequest(
          accessToken: currentPlayer?.player.accessToken,
          baseUrl: baseUrl,
          route: route,
          router: router
        )
      },
      authenticate: { request in
        return ApiClientLive.request(
          baseUrl: baseUrl,
          route: .authenticate(
            .init(
              deviceId: request.deviceId,
              displayName: request.displayName,
              gameCenterLocalPlayerId: request.gameCenterLocalPlayerId,
              timeZone: request.timeZone
            )
          ),
          router: router
        )
        .map { data, _ in data }
        .apiDecode(as: CurrentPlayerEnvelope.self)
        .handleEvents(
          receiveOutput: { newPlayer in
            DispatchQueue.main.async { currentPlayer = newPlayer }
          }
        )
        .eraseToEffect()
      },
      baseUrl: { baseUrl },
      currentPlayer: { currentPlayer },
      logout: {
        .fireAndForget { currentPlayer = nil }
      },
      refreshCurrentPlayer: {
        ApiClientLive.apiRequest(
          accessToken: currentPlayer?.player.accessToken,
          baseUrl: baseUrl,
          route: .currentPlayer,
          router: router
        )
        .map { data, _ in data }
        .apiDecode(as: CurrentPlayerEnvelope.self)
        .handleEvents(
          receiveOutput: { newPlayer in
            DispatchQueue.main.async { currentPlayer = newPlayer }
          }
        )
        .eraseToEffect()
      },
      request: { route in
        ApiClientLive.request(
          baseUrl: baseUrl,
          route: route,
          router: router
        )
      },
      setBaseUrl: { url in
        .fireAndForget { baseUrl = url }
      }
    )
  }
}

private func request(
  baseUrl: URL,
  route: ServerRoute,
  router: ServerRouter
) -> Effect<(data: Data, response: URLResponse), URLError> {
  Deferred { () -> Effect<(data: Data, response: URLResponse), URLError> in
    guard var request = try? router.baseURL(baseUrl.absoluteString).request(for: route)
    else { return .init(error: URLError(.badURL)) }
    request.setHeaders()
    return URLSession.shared.dataTaskPublisher(for: request)
      .eraseToEffect()
  }
  .eraseToEffect()
}

private func apiRequest(
  accessToken: AccessToken?,
  baseUrl: URL,
  route: ServerRoute.Api.Route,
  router: ServerRouter
) -> Effect<(data: Data, response: URLResponse), URLError> {

  return Deferred { () -> Effect<(data: Data, response: URLResponse), URLError> in
    guard let accessToken = accessToken
    else { return .init(error: .init(.userAuthenticationRequired)) }

    return request(
      baseUrl: baseUrl,
      route: .api(
        .init(
          accessToken: accessToken,
          isDebug: isDebug,
          route: route
        )
      ),
      router: router
    )
  }
  .eraseToEffect()
}

#if DEBUG
  private let isDebug = true
#else
  private let isDebug = false
#endif

extension URLRequest {
  fileprivate mutating func setHeaders() {
    guard let infoDictionary = Bundle.main.infoDictionary else { return }

    let bundleName = infoDictionary[kCFBundleNameKey as String] ?? "isowords"
    let marketingVersion = infoDictionary["CFBundleShortVersionString"].map { "/\($0)" } ?? ""
    let bundleVersion = infoDictionary[kCFBundleVersionKey as String].map { " bundle/\($0)" } ?? ""
    let gitSha = (infoDictionary["GitSHA"] as? String).map { $0.isEmpty ? "" : "git/\($0)" } ?? ""

    self.setValue(
      "\(bundleName)\(marketingVersion)\(bundleVersion)\(gitSha)", forHTTPHeaderField: "User-Agent")
  }
}

private let encoder = { () -> JSONEncoder in
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .secondsSince1970
  return encoder
}()

private let decoder = { () -> JSONDecoder in
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970
  return decoder
}()
