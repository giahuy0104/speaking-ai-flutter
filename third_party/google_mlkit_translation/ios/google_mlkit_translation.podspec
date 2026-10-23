require 'yaml'

pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))
simulator_stub = ENV['HOMI_IOS_TRANSLATION_SIMULATOR_STUB'] == '1'

Pod::Spec.new do |s|
  s.name = pubspec['name']
  s.version = pubspec['version'].gsub('+', '-')
  s.summary = pubspec['description']
  s.homepage = pubspec['homepage']
  s.license = { :file => '../LICENSE' }
  s.authors = 'flutter-ml.dev'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  # Google's translation binary has no arm64 simulator slice. Simulator tests
  # use an explicit unavailable adapter; device builds always link the SDK.
  s.dependency 'GoogleMLKit/Translate', '~> 9.0.0' unless simulator_stub
  s.platform = :ios, '15.5'
  s.ios.deployment_target = '15.5'
  s.static_framework = true
  s.swift_version = '5.0'
  pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  if simulator_stub
    pod_target_xcconfig['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] =
      '$(inherited) HOMI_TRANSLATION_SIMULATOR_STUB'
  end
  s.pod_target_xcconfig = pod_target_xcconfig
end
