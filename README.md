# fs PDF IQ — iOS

Native iPhone & iPad app with 48 PDF tools plus a PDF Workbench. Everything runs on the device (PDFKit, Vision, VisionKit, WebKit) — no uploads, works offline. Bahasa Melayu by default with an English toggle; light Liquid-Glass look in the fs IQ colours (red `#D9000D`, teal `#008183`).

## Getting the .ipa (no Mac needed)

1. Push to `main` (or open **Actions → Build iOS app (.ipa) → Run workflow**).
2. When the run turns green, open it and download the **fs-PDF-IQ-ipa** artifact (a zip containing `fs-PDF-IQ-unsigned.ipa`).

The .ipa is **unsigned**. iOS only installs signed apps, so sign it while installing:

### Option A — free Apple ID (re-sign every 7 days)
- **Sideloadly** (Windows/Mac): connect the iPhone by cable, drag the .ipa in, sign in with your Apple ID, Start.
- **AltStore** (Windows/Mac + AltServer): open the .ipa from AltStore on the phone.
- On the phone: **Settings › General › VPN & Device Management** → trust your Apple ID, and turn on **Developer Mode** (Settings › Privacy & Security) when asked.

### Option B — Apple Developer Program (US$99/year)
Lets you sign for a year, use TestFlight, or publish to the App Store. Add your signing certificate and provisioning profile as GitHub secrets and switch the workflow to a signed `xcodebuild archive` + `-exportArchive`.

## Project layout
- `project.yml` — XcodeGen spec (the workflow generates the .xcodeproj)
- `FSPDFIQ/Core` — files, PDF drawing helpers, ZIP/XML, DOCX/XLSX/PPTX writers
- `FSPDFIQ/Engine` — the tool engines (organise, optimise, stamp, convert, OCR, compare, Office import)
- `FSPDFIQ/Views` — SwiftUI screens

## Notes on a few tools
- **Compress, Grayscale, Ink Saver, PDF/A, Redact** save affected pages as images, so text on those pages is no longer selectable (redaction needs this to be truly permanent).
- **PDF to CAD** exports **DXF** (opens in AutoCAD/DraftSight/LibreCAD); DWG is a closed format.
- **Listen to PDF** uses the iOS Malay voice when installed (Settings › Accessibility › Spoken Content › Voices), otherwise Indonesian.
