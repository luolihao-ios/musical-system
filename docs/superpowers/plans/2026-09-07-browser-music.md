# Browser transfer and music completion

Goal: Deliver iPhone-hosted browser file management and optional music metadata enrichment.
Architecture: Independent Network.framework listener, bounded streaming request bodies, sandboxed file store, bundled web UI; existing client discovery stays independent. Music packages use ZIP manifest with optional companions. Player enrichment only fills missing resources and tolerates network failure.
Spec: docs/browser-transfer-design.md and current user requests.

- [x] Implement browser file store, upload approval/session routing, streaming listener and lifecycle view.
- [x] Bundle purple browser UI: files/folders/music selection, selection editing, upload confirmation/progress, listing/download/new folder.
- [x] Connect MP3 packaging and package import with optional LRC and cover.
- [x] Add missing-lyrics/cover lookup with conservative matching and failure isolation.
- [ ] Test path containment, upload state/size, optional music companions and metadata matching; build Windows and validate browser JS; submit iOS build without polling for artifacts.

Verification constraints: Windows host cannot run UIKit/Network.framework. Any Swift checks on this host must be identified separately from macOS compilation and device testing. Do not report submitted builds as passing.

Local verification: Windows build and 18 tests passed; 5 release metadata tests passed; JavaScript syntax and music package tests passed, including MP3-only packages. Actual browser client handlers tested with mocked transport for two consecutive accepted batches and rejection. Browser screenshot checked using the explicitly labelled loopback UI fixture, not an iPhone server. Swift streaming, sandbox and resource matching tests are added for macOS CI, not run locally. Real iPhone/browser transfer and remote resource lookup remain device acceptance checks.

Latest UI requirement: use Windows spacing, sidebar, purple palette, selection cards, files/folders/music buttons, nearby device card and full-page transfer progress. Browser file management is an additional entry beneath the device list. Do not expose text or clipboard options.
