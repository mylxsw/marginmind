#!/usr/bin/env ruby
# Builds an isolated XCTest UI runner against the installed simulator app.
require 'xcodeproj'
require 'tmpdir'
require 'fileutils'
abort 'usage: run.rb SIMULATOR_UDID RESULT_BUNDLE_PATH' unless (2..3).cover?(ARGV.length)
folder = Dir.mktmpdir('foliarc-native-ui-tests-')
project = Xcodeproj::Project.new(File.join(folder, 'PhoneUI.xcodeproj'))
target = project.new_target(:ui_test_bundle, 'PhonePresentationTests', :ios, '17.0')
Dir.glob(File.join(__dir__, '*.swift')).each do |path|
  file = project.main_group.new_file(File.expand_path(path))
  target.source_build_phase.add_file_reference(file)
end
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'io.github.mylxsw.foliarc.phone-uitests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'CODE_SIGNING_ALLOWED' => 'NO',
    'TARGETED_DEVICE_FAMILY' => '1,2',
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(target)
scheme.save_as(project.path, 'PhoneUI', true)
command = ['xcodebuild', 'test', '-project', project.path.to_s, '-scheme', 'PhoneUI', '-destination',
  "platform=iOS Simulator,id=#{ARGV[0]}", '-resultBundlePath', File.expand_path(ARGV[1]),
  '-derivedDataPath', File.join(folder, 'build'), '-parallel-testing-enabled', 'NO', '-quiet']
command += ['-only-testing:PhonePresentationTests/' + ARGV[2]] if ARGV[2]
exec(*command)
