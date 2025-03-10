import Combine
import ComposableArchitecture
import ComposableUserNotifications
import SharedModels
import TestHelpers
import UserNotifications
import XCTest

@testable import SettingsFeature

class SettingsFeatureTests: XCTestCase {
  var defaultEnvironment: SettingsEnvironment {
    var environment = SettingsEnvironment.failing
    environment.apiClient.baseUrl = { URL(string: "http://localhost:9876")! }
    environment.apiClient.currentPlayer = { .some(.init(appleReceipt: .mock, player: .blob)) }
    environment.build.number = { 42 }
    environment.mainQueue = .immediate
    environment.backgroundQueue = .immediate
    environment.fileClient.save = { _, _ in .none }
    environment.storeKit.fetchProducts = { _ in .none }
    environment.storeKit.observer = .run { _ in AnyCancellable {} }
    return environment
  }

  func testUserSettingsBackwardsDecodability() {
    XCTAssertNoDifference(
      try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8)),
      UserSettings()
    )

    let partialJson = """
      {
        "appIcon": "icon-1",
        "colorScheme": "dark",
        "enableGyroMotion": false,
        "enableHaptics": false,
        "musicVolume": 0.25,
        "soundEffectsVolume": 0.5,
      }
      """
    XCTAssertNoDifference(
      try JSONDecoder().decode(UserSettings.self, from: Data(partialJson.utf8)),
      UserSettings(
        appIcon: .icon1,
        colorScheme: .dark,
        enableGyroMotion: false,
        enableHaptics: false,
        musicVolume: 0.25,
        soundEffectsVolume: 0.5
      )
    )
  }

  // MARK: - Notifications

  func testEnableNotifications_NotDetermined_GrantAuthorization() {
    var didRegisterForRemoteNotifications = false

    var environment = self.defaultEnvironment
    environment.applicationClient.alternateIconName = { nil }
    environment.backgroundQueue = .immediate
    environment.fileClient.save = { _, _ in .none }
    environment.mainQueue = .immediate
    environment.serverConfig.config = { .init() }
    environment.userDefaults.boolForKey = { _ in false }
    environment.userNotifications.getNotificationSettings = .init(
      value: .init(authorizationStatus: .notDetermined)
    )
    environment.userNotifications.requestAuthorization = { _ in .init(value: true) }
    environment.remoteNotifications.register = {
      .fireAndForget {
        didRegisterForRemoteNotifications = true
      }
    }

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.onAppear) {
      $0.buildNumber = 42
      $0.developer.currentBaseUrl = .localhost
      $0.fullGamePurchasedAt = .mock
    }

    store.receive(.userNotificationSettingsResponse(.init(authorizationStatus: .notDetermined))) {
      $0.userNotificationSettings = .init(authorizationStatus: .notDetermined)
    }

    store.send(.set(\.$enableNotifications, true)) {
      $0.enableNotifications = true
    }

    store.receive(.userNotificationAuthorizationResponse(.success(true)))

    XCTAssert(didRegisterForRemoteNotifications)

    store.send(.onDismiss)
  }

  func testEnableNotifications_NotDetermined_DenyAuthorization() {
    var environment = self.defaultEnvironment
    environment.applicationClient.alternateIconName = { nil }
    environment.backgroundQueue = .immediate
    environment.fileClient.save = { _, _ in .none }
    environment.mainQueue = .immediate
    environment.serverConfig.config = { .init() }
    environment.userDefaults.boolForKey = { _ in false }
    environment.userNotifications.getNotificationSettings = .init(
      value: .init(authorizationStatus: .notDetermined)
    )
    environment.userNotifications.requestAuthorization = { _ in .init(value: false) }

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.onAppear) {
      $0.buildNumber = 42
      $0.developer.currentBaseUrl = .localhost
      $0.fullGamePurchasedAt = .mock
    }

    store.receive(.userNotificationSettingsResponse(.init(authorizationStatus: .notDetermined))) {
      $0.userNotificationSettings = .init(authorizationStatus: .notDetermined)
    }

    store.send(.set(\.$enableNotifications, true)) {
      $0.enableNotifications = true
    }

    store.receive(.userNotificationAuthorizationResponse(.success(false))) {
      $0.enableNotifications = false
    }

    store.send(.onDismiss)
  }

  func testNotifications_PreviouslyGranted() {
    var environment = self.defaultEnvironment
    environment.applicationClient.alternateIconName = { nil }
    environment.backgroundQueue = .immediate
    environment.fileClient.save = { _, _ in .none }
    environment.mainQueue = .immediate
    environment.remoteNotifications.register = { .none }
    environment.serverConfig.config = { .init() }
    environment.userDefaults.boolForKey = { _ in false }
    environment.userNotifications.getNotificationSettings = .init(
      value: .init(authorizationStatus: .authorized)
    )

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.onAppear) {
      $0.buildNumber = 42
      $0.developer.currentBaseUrl = .localhost
      $0.fullGamePurchasedAt = .mock
    }

    store.receive(.userNotificationSettingsResponse(.init(authorizationStatus: .authorized))) {
      $0.enableNotifications = true
      $0.userNotificationSettings = .init(authorizationStatus: .authorized)
    }

    store.send(.set(\.$enableNotifications, false)) {
      $0.enableNotifications = false
    }

    store.send(.onDismiss)
  }

  func testNotifications_PreviouslyDenied() {
    var openedUrl: URL!

    var environment = self.defaultEnvironment
    environment.applicationClient.alternateIconName = { nil }
    environment.applicationClient.openSettingsURLString = { "settings:isowords//isowords/settings" }
    environment.applicationClient.open = { url, _ in
      openedUrl = url
      return .init(value: true)
    }
    environment.backgroundQueue = .immediate
    environment.fileClient.save = { _, _ in .none }
    environment.mainQueue = .immediate
    environment.serverConfig.config = { .init() }
    environment.userDefaults.boolForKey = { _ in false }
    environment.userNotifications.getNotificationSettings = .init(
      value: .init(authorizationStatus: .denied)
    )

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.onAppear) {
      $0.buildNumber = 42
      $0.developer.currentBaseUrl = .localhost
      $0.fullGamePurchasedAt = .mock
    }

    store.receive(.userNotificationSettingsResponse(.init(authorizationStatus: .denied))) {
      $0.userNotificationSettings = .init(authorizationStatus: .denied)
    }

    store.send(.set(\.$enableNotifications, true)) {
      $0.alert = .userNotificationAuthorizationDenied
    }

    store.send(.openSettingButtonTapped)

    XCTAssertNoDifference(openedUrl, URL(string: "settings:isowords//isowords/settings")!)

    store.send(.set(\.$alert, nil)) {
      $0.alert = nil
    }

    store.send(.onDismiss)
  }

  func testNotifications_DebounceRemoteSettingsUpdates() {
    let mainQueue = DispatchQueue.test

    var environment = self.defaultEnvironment
    environment.apiClient.refreshCurrentPlayer = { .init(value: .blobWithPurchase) }
    environment.apiClient.override(
      route: .push(
        .updateSetting(.init(notificationType: .dailyChallengeEndsSoon, sendNotifications: true))
      ),
      withResponse: .none
    )
    environment.apiClient.override(
      route: .push(
        .updateSetting(.init(notificationType: .dailyChallengeReport, sendNotifications: true))
      ),
      withResponse: .none
    )
    environment.applicationClient.alternateIconName = { nil }
    environment.backgroundQueue = .immediate
    environment.fileClient.save = { _, _ in .none }
    environment.mainQueue = mainQueue.eraseToAnyScheduler()
    environment.remoteNotifications.register = { .none }
    environment.serverConfig.config = { .init() }
    environment.userDefaults.boolForKey = { _ in false }
    environment.userNotifications.getNotificationSettings = .init(
      value: .init(authorizationStatus: .authorized)
    )

    let store = TestStore(
      initialState: SettingsState(sendDailyChallengeReminder: false),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.onAppear) {
      $0.buildNumber = 42
      $0.developer.currentBaseUrl = .localhost
      $0.fullGamePurchasedAt = .mock
    }

    mainQueue.advance()

    store.receive(.userNotificationSettingsResponse(.init(authorizationStatus: .authorized))) {
      $0.enableNotifications = true
      $0.userNotificationSettings = .init(authorizationStatus: .authorized)
    }

    store.send(.set(\.$sendDailyChallengeReminder, true)) {
      $0.sendDailyChallengeReminder = true
    }
    mainQueue.advance(by: 0.5)

    store.send(.set(\.$sendDailyChallengeSummary, true))
    mainQueue.advance(by: 0.5)
    mainQueue.advance(by: 0.5)

    store.receive(.currentPlayerRefreshed(.success(.blobWithPurchase)))

    store.send(.onDismiss)
  }

  // MARK: - Sounds

  func testSetMusicVolume() {
    var setMusicVolume: Float!

    var environment = self.defaultEnvironment
    environment.audioPlayer.setGlobalVolumeForMusic = { newValue in
      .fireAndForget {
        setMusicVolume = newValue
      }
    }

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.set(\.$userSettings.musicVolume, 0.5)) {
      $0.userSettings.musicVolume = 0.5
    }

    XCTAssertNoDifference(setMusicVolume, 0.5)
  }

  func testSetSoundEffectsVolume() {
    var setSoundEffectsVolume: Float!

    var environment = self.defaultEnvironment
    environment.audioPlayer.setGlobalVolumeForSoundEffects = { newValue in
      .fireAndForget {
        setSoundEffectsVolume = newValue
      }
    }

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.set(\.$userSettings.soundEffectsVolume, 0.5)) {
      $0.userSettings.soundEffectsVolume = 0.5
    }

    XCTAssertNoDifference(setSoundEffectsVolume, 0.5)
  }

  // MARK: - Appearance

  func testSetColorScheme() {
    var overriddenUserInterfaceStyle: UIUserInterfaceStyle!

    var environment = self.defaultEnvironment
    environment.setUserInterfaceStyle = { newValue in
      .fireAndForget {
        overriddenUserInterfaceStyle = newValue
      }
    }

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.set(\.$userSettings.colorScheme, .light)) {
      $0.userSettings.colorScheme = .light
    }
    XCTAssertNoDifference(overriddenUserInterfaceStyle, .light)

    store.send(.set(\.$userSettings.colorScheme, .system)) {
      $0.userSettings.colorScheme = .system
    }
    XCTAssertNoDifference(overriddenUserInterfaceStyle, .unspecified)
  }

  func testSetAppIcon() {
    var overriddenIconName: String!

    var environment = self.defaultEnvironment
    environment.applicationClient.setAlternateIconName = { newValue in
      .fireAndForget {
        overriddenIconName = newValue
      }
    }
    environment.fileClient.save = { _, _ in .none }

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.set(\.$userSettings.appIcon, .icon2)) {
      $0.userSettings.appIcon = .icon2
    }
    XCTAssertNoDifference(overriddenIconName, "icon-2")
  }

  func testUnsetAppIcon() {
    var overriddenIconName: String?

    var environment = self.defaultEnvironment
    environment.applicationClient.alternateIconName = { "icon-2" }
    environment.applicationClient.setAlternateIconName = { newValue in
      .fireAndForget {
        overriddenIconName = newValue
      }
    }
    environment.backgroundQueue = .immediate
    environment.fileClient.save = { _, _ in .none }
    environment.mainQueue = .immediate
    environment.serverConfig.config = { .init() }
    environment.userDefaults.boolForKey = { _ in false }
    environment.userNotifications.getNotificationSettings = .none

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.onAppear) {
      $0.buildNumber = 42
      $0.developer.currentBaseUrl = .localhost
      $0.fullGamePurchasedAt = .mock
      $0.userSettings.appIcon = .icon2
    }

    store.send(.set(\.$userSettings.appIcon, nil)) {
      $0.userSettings.appIcon = nil
    }
    XCTAssertNoDifference(overriddenIconName, nil)

    store.send(.onDismiss)
  }

  // MARK: - Developer

  func testSetApiBaseUrl() {
    var setBaseUrl: URL!
    var didLogout = false

    var environment = SettingsEnvironment.failing
    environment.apiClient.logout = { .fireAndForget { didLogout = true } }
    environment.apiClient.setBaseUrl = { newValue in
      .fireAndForget {
        setBaseUrl = newValue
      }
    }

    let store = TestStore(
      initialState: SettingsState(),
      reducer: settingsReducer,
      environment: environment
    )

    store.send(.set(\.$developer.currentBaseUrl, .localhost)) {
      $0.developer.currentBaseUrl = .localhost
    }
    XCTAssertNoDifference(setBaseUrl, URL(string: "http://localhost:9876")!)
    XCTAssertNoDifference(didLogout, true)
  }

  func testToggleEnableCubeShadow() {
    let store = TestStore(
      initialState: SettingsState(enableCubeShadow: true),
      reducer: settingsReducer,
      environment: .failing
    )

    store.send(.set(\.$enableCubeShadow, false)) {
      $0.enableCubeShadow = false
    }
    store.send(.set(\.$enableCubeShadow, true)) {
      $0.enableCubeShadow = true
    }
  }

  func testSetShadowRadius() {
    let store = TestStore(
      initialState: SettingsState(cubeShadowRadius: 5),
      reducer: settingsReducer,
      environment: .failing
    )

    store.send(.set(\.$cubeShadowRadius, 20)) {
      $0.cubeShadowRadius = 20
    }
    store.send(.set(\.$cubeShadowRadius, 1.5)) {
      $0.cubeShadowRadius = 1.5
    }
  }

  func testToggleShowSceneStatistics() {
    let store = TestStore(
      initialState: SettingsState(showSceneStatistics: false),
      reducer: settingsReducer,
      environment: .failing
    )

    store.send(.set(\.$showSceneStatistics, true)) {
      $0.showSceneStatistics = true
    }
    store.send(.set(\.$showSceneStatistics, false)) {
      $0.showSceneStatistics = false
    }
  }

  func testToggleEnableGyroMotion() {
    let store = TestStore(
      initialState: SettingsState(userSettings: .init(enableGyroMotion: true)),
      reducer: settingsReducer,
      environment: self.defaultEnvironment
    )

    store.send(.set(\.$userSettings.enableGyroMotion, false)) {
      $0.userSettings.enableGyroMotion = false
    }
    store.send(.set(\.$userSettings.enableGyroMotion, true)) {
      $0.userSettings.enableGyroMotion = true
    }
  }

  func testToggleEnableHaptics() {
    let store = TestStore(
      initialState: SettingsState(userSettings: .init(enableHaptics: true)),
      reducer: settingsReducer,
      environment: self.defaultEnvironment
    )

    store.send(.set(\.$userSettings.enableHaptics, false)) {
      $0.userSettings.enableHaptics = false
    }
    store.send(.set(\.$userSettings.enableHaptics, true)) {
      $0.userSettings.enableHaptics = true
    }
  }
}
