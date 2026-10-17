Pod::Spec.new do |spec|
  spec.name = 'FutureNotesOfficeOxide'
  spec.version = '0.1.15'
  spec.summary = 'Pinned local Office document preview engine for Future Notes.'
  spec.homepage = 'https://github.com/yfedoseev/office_oxide'
  spec.license = { :type => 'MIT OR Apache-2.0' }
  spec.author = 'Office Oxide contributors'
  spec.source = { :git => 'https://github.com/yfedoseev/office_oxide.git', :commit => '5d183f4de990de254f32976bf952e548bcd25972' }
  spec.ios.deployment_target = '13.0'
  spec.vendored_frameworks = 'OfficeOxide.xcframework'
  spec.resource_bundles = { 'FutureNotesOfficeLicenses' => ['Licenses/*'] }
  spec.static_framework = true
  # Dart resolves the C ABI dynamically. Keep these archive entries linked even
  # when no Objective-C/Swift caller references them directly.
  spec.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_office_document_open -Wl,-u,_office_document_to_html -Wl,-u,_office_document_free -Wl,-u,_office_oxide_free_string'
  }
end
