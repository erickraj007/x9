# v6.19: adds a file in ios/Runner (e.g. GoogleService-Info.plist) to the Runner target's resources so it is
# packed into the app. Uses the xcodeproj gem that ships with CocoaPods on the macOS runners.
#   ruby ios_add_resource.rb apps/user/ios/Runner.xcodeproj GoogleService-Info.plist
require 'xcodeproj'

project_path, file_name = ARGV
abort('usage: ios_add_resource.rb <Runner.xcodeproj> <file in Runner/>') unless project_path && file_name
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')
group = project.main_group['Runner'] or abort('Runner group not found')
if group.files.any? { |f| f.path == file_name }
  puts "#{file_name} is already in the Runner target"
else
  ref = group.new_reference(file_name)
  target.resources_build_phase.add_file_reference(ref, true)
  project.save
  puts "#{file_name} added to the Runner target resources"
end
