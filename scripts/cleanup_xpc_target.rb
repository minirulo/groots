#!/usr/bin/env ruby
# frozen_string_literal: true
#
# cleanup_xpc_target.rb
#
# Reverses what setup_xpc_target.rb did to project.pbxproj.
# Run this if the setup script failed partway through and you need a clean slate.
#
#   ruby scripts/cleanup_xpc_target.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../groots_app/macos/Runner.xcodeproj', __dir__)
HELPER_NAME  = 'KuboHelper'
RUNNER_XPC_FILES = %w[KuboHelperProtocol.swift KuboXPCClient.swift KuboMethodChannel.swift]

project = Xcodeproj::Project.open(PROJECT_PATH)

runner_target = project.targets.find { |t| t.name == 'Runner' }

# ── 1. Remove KuboHelper target ───────────────────────────────────────────────
helper_target = project.targets.find { |t| t.name == HELPER_NAME }
if helper_target
  helper_target.remove_from_project
  puts "Removed target: #{HELPER_NAME}"
else
  puts "Target #{HELPER_NAME} not found — skipping"
end

# ── 2. Remove KuboHelper group + file references ──────────────────────────────
if (group = project.main_group.find_subpath(HELPER_NAME))
  group.remove_from_project
  puts "Removed group: #{HELPER_NAME}"
end

# ── 3. Remove Runner-side XPC file references ─────────────────────────────────
if runner_target
  runner_group = project.main_group.find_subpath('Runner')
  RUNNER_XPC_FILES.each do |filename|
    # Remove from Runner sources build phase
    runner_target.source_build_phase.files.each do |bf|
      if bf.file_ref&.path == filename
        bf.remove_from_project
        puts "  Removed from Runner sources: #{filename}"
      end
    end
    # Remove file reference from Runner group
    runner_group&.files&.each do |ref|
      if ref.path == filename
        ref.remove_from_project
        puts "  Removed file reference: #{filename}"
      end
    end
  end

  # ── 4. Remove "Embed XPC Services" build phase from Runner ──────────────────
  runner_target.build_phases.each do |phase|
    if phase.respond_to?(:name) && phase.name == 'Embed XPC Services'
      phase.remove_from_project
      puts "Removed 'Embed XPC Services' build phase from Runner"
    end
  end

  # ── 5. Remove target dependency on KuboHelper ─────────────────────────────
  runner_target.dependencies.each do |dep|
    if dep.target_proxy&.remote_info == HELPER_NAME
      dep.remove_from_project
      puts "Removed #{HELPER_NAME} dependency from Runner"
    end
  end
end

project.save
puts "\nDone. project.pbxproj is clean — run setup_xpc_target.rb again."
