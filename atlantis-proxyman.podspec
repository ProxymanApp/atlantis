Pod::Spec.new do |spec|
  spec.name         = "atlantis-proxyman"
  spec.version      = "1.17.0"
  spec.summary      = "A lightweight and powerful iOS framework for intercepting HTTP/HTTPS Traffic"
  spec.description  = <<-DESC
  A lightweight and powerful iOS framework for intercepting HTTP/HTTPS Traffic from your app. No more messing around with proxy, certificate config.
  Automatically intercept all HTTP/HTTPS Traffic with ease
  No need to config HTTP Proxy, Install or Trust any Certificate
  Review traffic log from Proxyman
  Categorize the log by project and devices.
                   DESC

  spec.homepage     = "https://github.com/ProxymanApp/atlantis"
  spec.documentation_url = 'https://docs.proxyman.io/atlantis/atlantis-for-ios'
  spec.screenshots  = "https://raw.githubusercontent.com/ProxymanApp/atlantis/main/images/cover.png"
  spec.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE" }

  spec.author             = { "Nghia Tran" => "nghia@proxyman.io" }
  spec.social_media_url   = "https://twitter.com/proxyman_app"

  spec.ios.deployment_target = "13.0"
  spec.osx.deployment_target = "10.15"
  spec.tvos.deployment_target = '13.0'
  spec.module_name = "Atlantis"

  spec.source       = { :git => "https://github.com/ProxymanApp/atlantis.git", :tag => "#{spec.version}" }
  spec.source_files  = 'Sources/*.swift'
  spec.swift_versions = ['5.0', '5.1', '5.2', '5.3']
end
