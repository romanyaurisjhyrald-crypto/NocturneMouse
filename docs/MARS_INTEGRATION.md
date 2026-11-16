# Mars Jelly in Nocturne

The finished user-supplied Mars Jelly project is integrated as the first, primary Stories card. The existing native reader and four HTML adventures remain separate.

## Architecture

`stories/MarsMission.gd` creates a full-window CanvasLayer and a dedicated SubViewport with its own World3D. The host scene is hidden and disabled while the mission runs; returning restores the same instance and care values. The viewport scales a 1280 x 800 cinematic canvas without clipping its HUD. Leaving frees the world, audio and terrain workers. Each entry starts a new story run; mission checkpoints are not saved.

`stories/mars/` retains the supplied endless terrain, rover rig, waypoint progression, four acts, weather and synthesized audio. Resource paths are namespaced. `source_art/Mars.blend` preserves the supplied Blender source. The Compatibility shader uses toon bands, specular highlights, wrap lighting and rim emission; it does not implement physical translucency or Forward+ subsurface scattering/bloom.

English is the default for new care and browser saves. Existing Spanish preferences remain valid. All added player-facing strings are in `locales/en.json` and `locales/es.json`. Voice recordings, if added later, must be stored in `stories/mars/audio/voice/en/` or `es/` using the line IDs. No voice recordings were supplied; synthesized tones remain in use.

## Validation

Godot 4.3 on Windows, Compatibility renderer: `MarsIntegrationTest.gd` checks launch, world isolation, terrain contact, movement, waypoint-gated progression through all four acts, return/re-entry, unchanged care trust, Spanish, resize and Escape. Timed dialogue is accelerated and the rover is moved to waypoint positions for the complete-story check; this is not a manual playthrough. `LibraryTest.gd` covers the six-entry library, existing HTML extraction, reader navigation and localization. `tools/validate_source.py` checks catalog parity and embedded browser JavaScript syntax.

Keyboard and mouse are required for Mars Jelly. No physical Android, touch driving, web export or long-duration performance test is claimed. Portrait displays use letterboxing and may make the cinematic text small.

## Provenance and narrative

Mars terrain and dialogue are stylized fiction inspired by Opportunity, not NASA terrain measurements or verbatim rover messages. English narration preserves the supplied story arc while distinguishing solar-powered hardware from a living creature. The existing Spanish translation retains the supplied prose. Mars Jelly assets were supplied by the project owner; this integration does not independently establish their original authorship. Existing repository licensing and third-party notices remain unchanged.

Publication-copy check: fresh Godot 4.3 import completed. The importer reported one non-finite normal skipped during LOD generation in a supplied asset; no script/import failure occurred. Library navigation passed again in the publication copy.
