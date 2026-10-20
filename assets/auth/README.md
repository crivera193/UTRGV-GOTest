# Field Notes opening screen

Owner selected the Field Notes concept on October 19, 2026. The live Flutter form uses green serif headings, cream grid paper, orange route accents and a decorative campus sketch. Sign-in/signup, all-.edu eligibility, immediate account creation policy and session storage are unchanged. The artwork is illustrative, not a geographic map or an official UTRGV mark. At larger accessibility text sizes the decorative strip is hidden to prioritize the form.

`field-notes-map.png` was generated with the built-in ImageGen tool for this project. Original source remains in the local generated-images library (exec-956fe9a1-d2fb-4a65-8647-6ce4dc5dbe61.png). No university seal, third-party game character, or downloaded campus photograph was used. Compass and paper grid are code-native Flutter drawing. DM Serif Display and Inter are bundled from Google Fonts; their SIL Open Font Licenses are beside the font files under assets/fonts. No network font request is made by the app.

Generation prompt: Create a production decorative raster asset for a mobile field-journal UI, not a mockup, no phone, text, labels or buttons. A very tall narrow vertical torn strip of ivory graph-paper map, irregular ragged paper edges, transparent background outside paper. Fine dark forest-green pen-and-ink illustrations vertically spaced: palm tree and modest South Texas campus building with arched doorway near top, university clock tower midway, small back-view faceless cowboy explorer wearing hat, backpack, vest and jeans below tower, small palms near bottom. Vivid orange dashed walking trail winds between illustrations with four hollow orange waypoint circles. Small diagonal beige masking tape at top. Premium contemporary travel-journal sketch, sparse ink hatching, light cream texture, no aged burnt edges. Illustrative buildings, no official university logos, cattle horns, longhorn motifs or face details. Entire strip and tape visible. Intended along the right edge of the hero, airy and subtle.

Verification: `flutter test --no-pub` covers the existing auth policies plus portrait/landscape, signup switching, validation, password visibility, scrolling, a 320x640 viewport with 1.6x text and simulated keyboard inset. `flutter analyze --no-pub lib test` checks maintained application/test sources; root-wide analysis also picks up unrelated ignored tmp/campus source snapshots. Capture review uses actual rendered Flutter widgets, not an emulator/backend login:

```
flutter test --no-pub --update-goldens --dart-define=CAPTURE_AUTH_REVIEW=true test/login_layout_test.dart
```

Captures are generated in ignored output/auth-review. Default tests do not require local captures. Preview files are not reference goldens or visual regression baselines. No real account creation/sign-in, device installation, release or owner acceptance is established by these tests.
