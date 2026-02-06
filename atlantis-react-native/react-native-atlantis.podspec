require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-atlantis"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]
  s.source       = { :git => "https://github.com/nicksantamaria/atlantis.git", :tag => s.version }

  s.ios.deployment_target = "13.0"

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  s.dependency "React-Core"

  # When published to npm, users install atlantis-proxyman from CocoaPods trunk.
  # For local development in this monorepo, the Podfile adds it as a local pod.
  s.dependency "atlantis-proxyman"
end
