#!/usr/bin/env ruby
# frozen_string_literal: true

# add_test_target.rb — bootstrap script for the LibrariumTests target.
#
# Run once to introduce a unit-test bundle into Librarium.xcodeproj. After
# this lands the project carries the target permanently, so this script is
# only relevant for re-creating it from scratch.
#
# Usage:
#   gem install --user-install xcodeproj
#   bundle exec ruby scripts/add_test_target.rb
# or
#   GEM_PATH=$HOME/.gem/ruby/2.6.0 ruby scripts/add_test_target.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../Librarium.xcodeproj', __dir__)
APP_TARGET   = 'Librarium'
TEST_TARGET  = 'LibrariumTests'
TESTS_DIR    = File.expand_path("../#{TEST_TARGET}", __dir__)

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == TEST_TARGET }
  puts "Test target '#{TEST_TARGET}' already exists — nothing to do."
  exit 0
end

app_target = project.targets.find { |t| t.name == APP_TARGET }
abort "App target '#{APP_TARGET}' not found." unless app_target

# Match the app's deployment target so the test bundle's Swift compiler
# sees the same iOS-26 SDK surface the production code uses.
deployment_target = app_target.build_configurations
                              .find { |c| c.name == 'Debug' }
                              .build_settings['IPHONEOS_DEPLOYMENT_TARGET']

test_target = project.new_target(
  :unit_test_bundle,
  TEST_TARGET,
  :ios,
  deployment_target,
  project.products_group,
  :swift,
)

# Tell xcodebuild that this test bundle exercises the Librarium app, so
# the Librarium scheme picks the tests up under `xcodebuild test`.
test_target.add_dependency(app_target)

test_target.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_NAME']              = TEST_TARGET
  s['TEST_HOST']                 = "$(BUILT_PRODUCTS_DIR)/#{APP_TARGET}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/#{APP_TARGET}"
  s['BUNDLE_LOADER']             = '$(TEST_HOST)'
  s['TARGETED_DEVICE_FAMILY']    = '1,2'
  s['SWIFT_VERSION']             = '6.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
  s['GENERATE_INFOPLIST_FILE']   = 'YES'
  s['CODE_SIGN_STYLE']           = 'Automatic'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "ca.fireball1725.#{TEST_TARGET}"
end

# Pick up every Swift file that lives under the LibrariumTests/ folder.
# Folder is created by the caller before running the script.
tests_group = project.main_group.find_subpath(TEST_TARGET, true)
tests_group.set_source_tree('SOURCE_ROOT')
tests_group.set_path(TEST_TARGET)

Dir[File.join(TESTS_DIR, '**', '*.swift')].sort.each do |abs|
  rel = abs.sub("#{TESTS_DIR}/", '')
  file_ref = tests_group.new_reference(rel)
  test_target.add_file_references([file_ref])
end

# Wire the existing 'Librarium' scheme so `xcodebuild test` knows about
# the bundle. The scheme lives under xcshareddata so it persists for CI.
scheme_path = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes', "#{APP_TARGET}.xcscheme")
if File.exist?(scheme_path)
  scheme = Xcodeproj::XCScheme.new(scheme_path)
  test_action = scheme.test_action
  testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
  test_action.add_testable(testable)
  scheme.save_as(PROJECT_PATH, APP_TARGET, true)
end

project.save
puts "Created test target '#{TEST_TARGET}' and wired it into the '#{APP_TARGET}' scheme."
