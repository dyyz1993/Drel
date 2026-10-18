install! 'cocoapods', :warn_for_unused_master_specs_repo => false

platform :ios, '15.0'
use_frameworks! :linkage => :static
inhibit_all_warnings!

workspace 'Drel.xcworkspace'
project 'Drel.xcodeproj',
  'Debug' => :debug,
  'Release' => :release,
  'Drel14Release' => :release,
  'Drel15Release' => :release

def app_pods
  wbk_path = ENV.fetch('WBK_FRAMEWORK_PATH', '../WebBridgeKit-Framework')
  pod 'WebBridgeKit', :path => wbk_path
  pod 'Kingfisher', '~> 7.0'
  pod 'SnapKit'
  pod 'RxSwift', '~> 6.0'
  pod 'RxCocoa', '~> 6.0'
  pod 'RxDataSources', '~> 5.0'
  pod 'RealmSwift', '~> 10.42'
end

target 'Drel' do
  app_pods

  target 'DrelTests' do
    inherit! :search_paths
  end

  target 'DrelUITests' do
    inherit! :search_paths
  end
end

# NSE is self-contained (zero CocoaPods dependencies)
target 'NotificationServiceExtension' do
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      config.build_settings['DEVELOPMENT_TEAM'] = 'B45VZCNYU3'
      config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Development'

      if target.name.include?('Realm')
        config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++20'
        config.build_settings['CLANG_CXX_LIBRARY'] = 'libc++'
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'REALM_HAVE_CONFIG=1'
        config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
      end
    end
  end
end
