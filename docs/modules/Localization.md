# Localization

ZeroDark ships with an English (`en.lproj`) catalog as the base and a partial
Spanish (`es.lproj`) catalog to verify the localization pipeline works. The
audit flagged localization at 1/10 because the existing code was written with
~400 hard-coded `Text("Hello")` strings; migrating them is a multi-PR effort.

## Catalog layout

```
Resources/
  en.lproj/
    Localizable.strings      — English base (source of truth)
  es.lproj/
    Localizable.strings      — Partial Spanish (fall back to en on missing keys)
```

New locales add `Resources/XX.lproj/Localizable.strings`.

## Key naming

Keys are dot-namespaced by feature, not by screen — the same label can show
in multiple places. Example buckets already in use:

| Prefix       | Scope                                               |
|--------------|-----------------------------------------------------|
| `tab.*`      | Tab-bar titles                                      |
| `action.*`   | Common action buttons (Save, Cancel, Done, …)      |
| `applock.*`  | AppLock screen + manager                            |
| `comms.*`    | Mesh / PTT / SOS strip                              |
| `map.*`      | Map tab toolbar + overlay                           |
| `nav.*`      | Nav tab toolbar                                     |
| `lidar.*`    | LiDAR tab scan controls                             |
| `intel.*`    | Intel tab                                           |
| `opord.*`    | OpOrder builder                                     |
| `integration.*` | Integration health monitor (SRTM/weather/TAK)   |
| `error.*`    | User-facing error messages                          |

Format specifiers use positional arguments (`%1$@`, `%1$d`) so word order can
be re-arranged in translations without reshuffling call sites.

## Migration pattern

1. Pick a screen or view.
2. Replace `Text("Literal")` with `Text("key.name", bundle: .main)` — SwiftUI
   resolves the key through the bundled `Localizable.strings`.
3. For code outside SwiftUI (toasts, alerts, ErrorReporter messages), use
   `NSLocalizedString("key.name", comment: "")`.
4. Add the key to `en.lproj/Localizable.strings` with the English value.
5. Optionally add translations to `es.lproj/Localizable.strings` — keys absent
   in the target locale fall back to `en`.

## Verification

After a migration pass, run `genstrings Sources/**/*.swift -o Resources/en.lproj`
locally (requires Xcode command-line tools). The result should match the
hand-maintained file modulo ordering; diffs mean a key has been missed or
a literal is still in source.

## Status

- `Resources/en.lproj/Localizable.strings` — seeded with ~70 keys covering the
  auth, tab navigation, comms strip, toolbars, and the high-traffic error
  messages.
- `Resources/es.lproj/Localizable.strings` — initial Spanish draft; needs
  native-speaker review before shipping.
- **No call sites migrated yet.** This PR sets up the infrastructure; the
  in-code migration is a follow-up because it touches hundreds of files and
  is best done one screen per PR.
