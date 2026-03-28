Pod::Spec.new do |s|
  s.name         = 'Remo'
  s.version      = '0.4.0'
  s.summary      = 'Remote control bridge for iOS apps — infrastructure for agentic iOS development.'
  s.description  = <<-DESC
    Remo gives AI agents eyes and hands on iOS. Register capabilities in your app,
    invoke them from macOS via the remo CLI or any AI agent.
    Debug-only — compiles to no-ops in Release builds.
  DESC
  s.homepage     = 'https://github.com/yjmeqt/Remo'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { 'Yi Jiang' => 'yi.jiang@applovin.com' }
  s.platform     = :ios, '13.0'
  s.source       = {
    :http => "https://github.com/yjmeqt/Remo/releases/download/v#{s.version}/RemoSDK.xcframework.zip"
  }
  s.preserve_paths = 'RemoSDK.xcframework'

  s.default_subspecs = 'Swift'

  # Shared linkage settings for both subspecs.
  shared_linker = {
    'OTHER_LDFLAGS' => '-lremo_sdk',
  }
  shared_frameworks = ['Security', 'CoreMedia', 'VideoToolbox', 'CoreFoundation']
  shared_libraries  = ['c++']

  # ── Swift ──────────────────────────────────────────────
  s.subspec 'Swift' do |sw|
    sw.swift_versions      = ['5.9', '6.0']
    sw.source_files       = 'RemoSwift/Sources/RemoSwift/**/*.swift'
    sw.vendored_frameworks = 'RemoSDK.xcframework'
    sw.libraries           = shared_libraries
    sw.frameworks          = shared_frameworks
    sw.pod_target_xcconfig = shared_linker
  end

  # ── ObjC ───────────────────────────────────────────────
  s.subspec 'ObjC' do |oc|
    oc.source_files        = 'RemoSwift/Sources/RemoObjC/**/*.{h,m}'
    oc.public_header_files = 'RemoSwift/Sources/RemoObjC/include/**/*.h'
    oc.vendored_frameworks = 'RemoSDK.xcframework'
    oc.libraries           = shared_libraries
    oc.frameworks          = shared_frameworks
    oc.pod_target_xcconfig = shared_linker.merge({
      'CLANG_ENABLE_MODULES' => 'YES',
    })
  end
end
