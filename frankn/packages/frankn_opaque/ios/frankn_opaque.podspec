Pod::Spec.new do |s|
  s.name             = 'frankn_opaque'
  s.version          = '0.1.0'
  s.summary          = 'RFC 9807 OPAQUE FFI for Frankn'
  s.description      = 'Shared Rust OPAQUE client core used by the Frankn Flutter application.'
  s.homepage         = 'https://example.invalid/frankn'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Frankn' => 'security@frankn.invalid' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.swift_version    = '5.0'
  s.vendored_frameworks = 'Frameworks/FranknOpaque.xcframework'
  s.prepare_command = 'bash ../scripts/build_ios.sh'
end
