#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the PacketTunnel app extension to app/ios/Runner.xcodeproj and wires it into Runner.
# Idempotent: running it twice changes nothing the second time.
#
# Usage (macOS, repo root):
#   gem install xcodeproj && ruby app/scripts/ios_add_packet_tunnel.rb
#
# Obsidian.xcframework (the Go core, gomobile) must exist before building. It is produced from core/:
#   cd core && gomobile bind -target=ios,iossimulator \
#     -o ../app/ios/Frameworks/Obsidian.xcframework ./pkg/mobile
# The extension links it but does not embed it (gomobile frameworks are static). If the directory is
# missing when this script runs, the link step is skipped with a warning; run the script again after
# building the framework.
#
# What the script does:
#   1. Adds target PacketTunnel (bundle id com.obsidian.vpn.PacketTunnel, iOS 17.0, Swift 5, automatic
#      signing) with sources from app/ios/PacketTunnel/*.swift, its Info.plist and entitlements.
#   2. Links NetworkExtension.framework and Frameworks/Obsidian.xcframework into the extension.
#   3. Embeds PacketTunnel.appex into Runner ("Embed Foundation Extensions", dstSubfolderSpec 13),
#      placed before the Flutter "Thin Binary" phase to avoid a build cycle, plus a target dependency.
#   4. Adds Runner/VpnChannel.swift to Runner sources and sets CODE_SIGN_ENTITLEMENTS to
#      Runner/Runner.entitlements.

require 'xcodeproj'

IOS_DIR = File.expand_path('../ios', __dir__)
PROJECT_PATH = File.join(IOS_DIR, 'Runner.xcodeproj')
EXT_NAME = 'PacketTunnel'
APP_BUNDLE_ID = 'com.obsidian.vpn'
EXT_BUNDLE_ID = "#{APP_BUNDLE_ID}.PacketTunnel"
EMBED_PHASE_NAME = 'Embed Foundation Extensions'
XCFRAMEWORK_REL = 'Frameworks/Obsidian.xcframework'

abort "Not found: #{PROJECT_PATH}" unless File.directory?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target not found'

# ---- helpers ---------------------------------------------------------------------------------

def ensure_file_ref(group, name)
  group.files.find { |f| f.path == name } || group.new_file(name)
end

def ensure_in_sources(target, ref)
  return if target.source_build_phase.files_references.include?(ref)

  target.source_build_phase.add_file_reference(ref)
end

# ---- extension target ------------------------------------------------------------------------

ext = project.targets.find { |t| t.name == EXT_NAME }
if ext.nil?
  ext = project.new_target(:app_extension, EXT_NAME, :ios, '17.0', nil, :swift)
  puts "Created target #{EXT_NAME}"
end

ext_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == EXT_NAME && g.isa == 'PBXGroup' }
ext_group ||= project.main_group.new_group(EXT_NAME, EXT_NAME)

Dir.glob(File.join(IOS_DIR, EXT_NAME, '*.swift')).sort.each do |path|
  ensure_in_sources(ext, ensure_file_ref(ext_group, File.basename(path)))
end
ensure_file_ref(ext_group, 'Info.plist')
ensure_file_ref(ext_group, 'PacketTunnel.entitlements')

XCCONFIG_NAME = 'PacketTunnel.xcconfig'
xcconfig_path = File.join(IOS_DIR, EXT_NAME, XCCONFIG_NAME)
xcconfig_text = "#include \"../Flutter/Generated.xcconfig\"\n"
File.write(xcconfig_path, xcconfig_text) unless File.exist?(xcconfig_path) && File.read(xcconfig_path) == xcconfig_text
xcconfig_ref = ensure_file_ref(ext_group, XCCONFIG_NAME)

runner_configs = runner.build_configurations.each_with_object({}) { |c, h| h[c.name] = c }

ext.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = "#{EXT_NAME}/Info.plist"
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = "#{EXT_NAME}/PacketTunnel.entitlements"
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SKIP_INSTALL'] = 'YES'
  settings['SDKROOT'] = 'iphoneos'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  settings['OTHER_LDFLAGS'] = ['$(inherited)', '-lresolv']
  settings['CLANG_ENABLE_MODULES'] = 'YES'

  runner_config = runner_configs[config.name]
  next unless runner_config

  # Gives the Info.plist FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER, so the extension version always equals
  # Runner's (App Store validation requires it). Runner's own xcconfig is not reused on purpose: with CocoaPods
  # it also pulls in the plugin pods' linker flags, which must not reach the 15 MB extension.
  config.base_configuration_reference = xcconfig_ref
  team = runner_config.build_settings['DEVELOPMENT_TEAM']
  settings['DEVELOPMENT_TEAM'] = team if team
end

# Frameworks: NetworkExtension (system) and the Go core (static xcframework, not embedded).
frameworks_phase = ext.frameworks_build_phase
unless frameworks_phase.files_references.any? { |r| r&.path.to_s.end_with?('NetworkExtension.framework') }
  ext.add_system_framework('NetworkExtension')
end

if File.directory?(File.join(IOS_DIR, XCFRAMEWORK_REL))
  xcf_ref = project.main_group.files.find { |f| f.path == XCFRAMEWORK_REL }
  if xcf_ref.nil?
    xcf_ref = project.main_group.new_reference(XCFRAMEWORK_REL)
    xcf_ref.last_known_file_type = 'wrapper.xcframework'
  end
  frameworks_phase.add_file_reference(xcf_ref) unless frameworks_phase.files_references.include?(xcf_ref)
else
  warn "WARNING: #{XCFRAMEWORK_REL} not found, skipping link. Build it with gomobile (see header), then rerun."
end

# ---- Runner wiring ---------------------------------------------------------------------------

runner_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == 'Runner' && g.isa == 'PBXGroup' }
abort 'Runner group not found' if runner_group.nil?

ensure_in_sources(runner, ensure_file_ref(runner_group, 'VpnChannel.swift'))
ensure_file_ref(runner_group, 'Runner.entitlements')
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

embed = runner.build_phases.find do |p|
  p.isa == 'PBXCopyFilesBuildPhase' && p.name == EMBED_PHASE_NAME
end
if embed.nil?
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = EMBED_PHASE_NAME
  embed.dst_path = ''
  embed.dst_subfolder_spec = '13' # PlugIns
  thin_index = runner.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  if thin_index
    runner.build_phases.insert(thin_index, embed)
  else
    runner.build_phases << embed
  end
end

unless embed.files_references.include?(ext.product_reference)
  build_file = embed.add_file_reference(ext.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy] }
end

runner.add_dependency(ext) unless runner.dependencies.any? { |d| d.target == ext }

project.save
puts 'Done: PacketTunnel target configured.'
