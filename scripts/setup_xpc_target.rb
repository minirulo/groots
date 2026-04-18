#!/usr/bin/env ruby
# frozen_string_literal: true
#
# setup_xpc_target.rb
#
# Adds the KuboHelper XPC service target to the Flutter macOS Xcode project
# and wires it into the Runner target's build pipeline.
#
# Run once from the repo root:
#   gem install xcodeproj   # if not already installed via CocoaPods
#   ruby scripts/setup_xpc_target.rb
#
# Safe to run multiple times — skips steps that are already present.

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH    = File.expand_path('../groots_app/macos/Runner.xcodeproj', __dir__)
HELPER_DIR      = File.expand_path('../groots_app/macos/KuboHelper', __dir__)
RUNNER_DIR      = File.expand_path('../groots_app/macos/Runner', __dir__)
BUNDLE_ID_BASE  = 'com.rce-studio.groots'
HELPER_NAME     = 'KuboHelper'
HELPER_BUNDLE_ID = "#{BUNDLE_ID_BASE}.kubo-helper"
SWIFT_VERSION   = '5.0'
DEPLOYMENT_TARGET = '10.15'

project = Xcodeproj::Project.open(PROJECT_PATH)

# ── 1. Guard: skip if target already exists ───────────────────────────────────
if project.targets.any? { |t| t.name == HELPER_NAME }
  puts "#{HELPER_NAME} target already exists — nothing to do."
  exit 0
end

runner_target = project.targets.find { |t| t.name == 'Runner' }
abort "Could not find Runner target" unless runner_target

# ── 2. Create the XPC service target ─────────────────────────────────────────
helper_target = project.new_target(
  :xpc_service,          # product type
  HELPER_NAME,
  :osx,
  DEPLOYMENT_TARGET
)
helper_target.product_name = HELPER_NAME

puts "Created target: #{HELPER_NAME}"

# ── 3. Add source files to the project and the helper target ─────────────────
helper_group = project.main_group.find_subpath(HELPER_NAME) ||
               project.main_group.new_group(HELPER_NAME, HELPER_DIR)

swift_sources = %w[main.swift KuboHelperProtocol.swift KuboHelperService.swift]
swift_sources.each do |filename|
  path = File.join(HELPER_DIR, filename)
  abort "Missing source file: #{path}" unless File.exist?(path)

  unless helper_group.files.any? { |f| f.path == filename }
    ref = helper_group.new_file(path)
    helper_target.source_build_phase.add_file_reference(ref)
    puts "  Added source: #{filename}"
  end
end

# Info.plist (resource, not compiled)
info_plist_path = File.join(HELPER_DIR, 'Info.plist')
unless helper_group.files.any? { |f| f.path == 'Info.plist' }
  helper_group.new_file(info_plist_path)
  puts "  Added resource: Info.plist"
end

# ipfs binary → Copy Bundle Resources
ipfs_path = File.join(HELPER_DIR, 'ipfs')
abort "Missing kubo binary at #{ipfs_path} — run the lipo step first" unless File.exist?(ipfs_path)

ipfs_ref = helper_group.files.find { |f| f.path == 'ipfs' } ||
           helper_group.new_file(ipfs_path)

resources_phase = helper_target.resources_build_phase
unless resources_phase.files.any? { |f| f.file_ref == ipfs_ref }
  resources_phase.add_file_reference(ipfs_ref)
  puts "  Added binary to Copy Bundle Resources: ipfs"
end

# ── 4. Add Runner-side files to the Runner group & target ────────────────────
runner_group = project.main_group.find_subpath('Runner') ||
               project.main_group.new_group('Runner', RUNNER_DIR)

runner_xpc_files = %w[KuboHelperProtocol.swift KuboXPCClient.swift KuboMethodChannel.swift]
runner_xpc_files.each do |filename|
  path = File.join(RUNNER_DIR, filename)
  abort "Missing Runner file: #{path}" unless File.exist?(path)

  unless runner_group.files.any? { |f| f.path == filename }
    ref = runner_group.new_file(path)
    runner_target.source_build_phase.add_file_reference(ref)
    puts "  Added to Runner: #{filename}"
  end
end

# ── 5. Configure build settings for KuboHelper ───────────────────────────────
[
  helper_target.build_configuration_list['Debug'],
  helper_target.build_configuration_list['Release'],
  helper_target.build_configuration_list['Profile'],
].compact.each do |config|
  s = config.build_settings

  s['PRODUCT_BUNDLE_IDENTIFIER']        = HELPER_BUNDLE_ID
  s['PRODUCT_NAME']                     = HELPER_NAME
  s['SWIFT_VERSION']                    = SWIFT_VERSION
  s['MACOSX_DEPLOYMENT_TARGET']         = DEPLOYMENT_TARGET
  s['INFOPLIST_FILE']                   = 'KuboHelper/Info.plist'
  s['ENABLE_HARDENED_RUNTIME']          = 'YES'
  s['CODE_SIGN_STYLE']                  = 'Automatic'
  s['DEVELOPMENT_TEAM']                 = 'B3UPYA8K4D'
  s['SKIP_INSTALL']                     = 'YES'
  s['WRAPPER_EXTENSION']                = 'xpc'
  s['MACH_O_TYPE']                      = 'mh_execute'
  # Prevent CocoaPods from injecting Runner's pod frameworks via $(inherited)
  s['OTHER_LDFLAGS']                    = ''
  s['FRAMEWORK_SEARCH_PATHS']           = ''
  s['LIBRARY_SEARCH_PATHS']             = ''
  # Entitlements (per-config)
  if config.name == 'Debug'
    s['CODE_SIGN_ENTITLEMENTS'] = 'KuboHelper/KuboHelper-Debug.entitlements'
  else
    s['CODE_SIGN_ENTITLEMENTS'] = 'KuboHelper/KuboHelper-Release.entitlements'
  end
end

puts "Configured build settings for #{HELPER_NAME}"

# ── 6. Add shell script phase to Runner that copies KuboHelper.xpc ───────────
embed_phase = runner_target.build_phases.find do |p|
  p.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) &&
    p.name == 'Embed XPC Services'
end

unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)
  embed_phase.name       = 'Embed XPC Services'
  embed_phase.shell_path = '/bin/sh'
  embed_phase.shell_script = <<~SHELL
    set -e
    XPC_DIR="${CODESIGNING_FOLDER_PATH}/Contents/XPCServices"
    mkdir -p "${XPC_DIR}"

    # BUILT_PRODUCTS_DIR/KuboHelper.xpc is a relative symlink during archive
    # (Xcode uses SKIP_INSTALL=YES and creates a symlink to UninstalledProducts).
    # Resolve it to the real path before copying so ditto gets the actual bundle.
    SRC_LINK="${BUILT_PRODUCTS_DIR}/KuboHelper.xpc"
    if [ -L "${SRC_LINK}" ]; then
      SRC=$(readlink -f "${SRC_LINK}" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "${SRC_LINK}")
    else
      SRC="${SRC_LINK}"
    fi

    if [ ! -d "${SRC}" ]; then
      echo "warning: KuboHelper.xpc not found at ${SRC} (resolved from ${SRC_LINK})"
      exit 0
    fi

    rm -rf "${XPC_DIR}/KuboHelper.xpc"
    # ditto preserves bundle structure and resolves any remaining symlinks
    /usr/bin/ditto "${SRC}" "${XPC_DIR}/KuboHelper.xpc"

    # Choose entitlements based on build configuration.
    if [ "${CONFIGURATION}" = "Debug" ]; then
      ENTITLEMENTS="${SRCROOT}/KuboHelper/KuboHelper-Debug.entitlements"
    else
      ENTITLEMENTS="${SRCROOT}/KuboHelper/KuboHelper-Release.entitlements"
    fi
    IPFS_ENTITLEMENTS="${SRCROOT}/KuboHelper/ipfs.entitlements"

    # Sign the bundled ipfs binary — App Store validation requires every
    # Mach-O executable in the package to carry app-sandbox = true.
    IPFS_BIN="${XPC_DIR}/KuboHelper.xpc/Contents/Resources/ipfs"
    if [ -f "${IPFS_BIN}" ]; then
      codesign --force --options runtime \\
        --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \\
        --entitlements "${IPFS_ENTITLEMENTS}" \\
        "${IPFS_BIN}"
    fi

    # Sign the XPC service binary, then the bundle.
    codesign --force --options runtime \\
      --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \\
      --entitlements "${ENTITLEMENTS}" \\
      "${XPC_DIR}/KuboHelper.xpc/Contents/MacOS/KuboHelper"

    codesign --force --options runtime \\
      --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \\
      --entitlements "${ENTITLEMENTS}" \\
      "${XPC_DIR}/KuboHelper.xpc"

    echo "Embedded and re-signed KuboHelper.xpc (with ipfs) into ${XPC_DIR}"
  SHELL
  runner_target.build_phases << embed_phase
  puts "Created 'Embed XPC Services' shell script phase in Runner"
end

# ── 7. Add target dependency so Runner builds KuboHelper first ───────────────
unless runner_target.dependencies.any? { |d| d.target == helper_target }
  dep = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
  dep.target = helper_target

  proxy = project.new(Xcodeproj::Project::Object::PBXContainerItemProxy)
  proxy.container_portal = project.root_object.uuid
  proxy.proxy_type       = '1'
  proxy.remote_global_id_string = helper_target.uuid
  proxy.remote_info = HELPER_NAME

  dep.target_proxy = proxy
  runner_target.dependencies << dep
  puts "Added #{HELPER_NAME} as dependency of Runner"
end

# ── 8. Save ───────────────────────────────────────────────────────────────────
project.save
puts "\nDone. Open macos/Runner.xcworkspace and build."
puts
puts "Next steps:"
puts "  1. Place the signed kubo universal binary at:"
puts "     groots_app/macos/KuboHelper/ipfs"
puts "     (download from https://dist.ipfs.tech/ — arm64 + amd64, lipo into a fat binary)"
puts "  2. Add 'ipfs' to the KuboHelper target's 'Copy Bundle Resources' phase in Xcode."
puts "  3. In Xcode → Signing & Capabilities, set the Team for KuboHelper."
puts "  4. Archive and validate."
