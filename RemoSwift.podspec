# CocoaPods support is planned but not yet published to trunk.
# To publish: pod trunk push RemoSwift.podspec --allow-warnings
Pod::Spec.new do |s|
  s.name         = 'RemoSwift'
  s.version      = '0.1.0'
  s.summary      = 'Remote control bridge for iOS apps — inspect and mutate state from macOS in real time.'
  s.description  = <<-DESC
    Remo is a lightweight bridge between macOS and iOS. Embed the SDK in your app
    to register named capabilities (RPC handlers) that can be invoked from a
    terminal command. The iOS UI reacts instantly. Debug-only by default.
  DESC

  s.homepage     = 'https://github.com/yi-jiang-applovin/Remo'
  s.license      = { type: 'MIT', file: 'LICENSE' }
  s.author       = { 'Yi Jiang' => 'yi.jiang@applovin.com' }

  s.source       = {
    http: "https://github.com/yi-jiang-applovin/Remo/releases/download/v#{s.version}/RemoSDK.xcframework.zip"
  }

  s.ios.deployment_target = '15.0'
  s.swift_versions = ['6.0', '6.1']

  s.source_files = 'swift/RemoSwift/Sources/RemoSwift/**/*.swift'
  s.vendored_frameworks = 'RemoSDK.xcframework'
  s.preserve_paths = 'RemoSDK.xcframework'

  s.libraries  = 'c++'
  s.frameworks = 'Security'

  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-lc++',
  }
end
