# iOS incoming shares — native validation pending

The Share Extension receives files into `group.com.nativedevps.futurenotes`.
The main app presents the destination chooser when opened. The extension never
launches another Flutter engine or writes a note/library.

On a Mac, register the App Group for Runner and
`com.nativedevps.futurenotes.ShareExtension`, select matching signing teams,
then build and exercise the extension on iPhone/iPad. The checked-in target
preserves iOS 13; compilation, signing, extension limits and device acceptance
have not been validated on Windows.

Inbox payloads are protected using the existing iOS file-protection policy and
excluded from backup. Only complete receipt manifests are presented. Accepted
payloads remain available for interrupted-task recovery and are removed when
their owned source lease is released. No note password is stored in the inbox.
