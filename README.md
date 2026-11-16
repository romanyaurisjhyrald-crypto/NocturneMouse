# NocturneMouse

[Public repository](https://github.com/romanyaurisjhyrald-crypto/NocturneMouse) · Built with Godot 4.3 · English with optional Spanish

A bilingual educational game about the spacecraft, rovers and scientific instruments that remain on the Moon, Mars and in deep space. Nocturne, a fictional cyan mouse with orange glasses, helps school-age learners explore the science and history behind this hardware.

Prepared for NASA Space Apps Challenge 2026, Andahuaylas, Peru, by the Nebula Drift team. Challenge: **Abandoned but not Forgotten: Storytelling about NASA's Discarded Equipment on the Moon and Mars**. This repository does not claim organizer approval or award eligibility.

## Play locally

1. Install the standard edition of [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/). No .NET SDK or add-on is required.
2. Clone or download this repository and import `project.godot`. Let the editor import the assets.
3. Press F5. Care for Nocturne to unlock Stories; the existing Demo controls can help reviewers explore the progression.
4. Open **Stories** and choose **MAIN STORY · Mars Jelly** to play the native four-act Oppy adventure. **Back to Stories** or **Esc** returns to the library with the mouse's care state preserved. Other adventures remain separate. The four HTML games open in your default browser. Switch back to Godot to choose another mission.

To try a browser game directly, open its `index.html` from the table below. These are self-contained games; web fonts and external reference links require internet. The Godot application itself has not been exported as a browser build.

| Adventure | Source | Learning focus |
| --- | --- | --- |
| Mars Jelly: Sweet Horizon (main story) | [Native scene](stories/mars/main.tscn) | Opportunity, solar power, dust storms and scientific legacy |
| The Silent Mirror | [HTML](stories/html/silent_mirror/index.html) | Lunar retroreflectors and round-trip light travel time |
| Oppy: An Adventure on Mars | [HTML](stories/html/oppy/index.html) | Rover exploration, images, observations and solar energy |
| Voyager 1 | [HTML](stories/html/voyager_one/index.html) | Spacecraft journeys, flybys and scientific exploration |
| Keepers of the Legacy | [HTML](stories/html/small_discoveries/index.html) | Recognizing and documenting space heritage |

Each browser adventure has a three-medal learning passport, hints and persistent browser progress. The mouse is an imaginary companion, not a historical passenger. Stories also includes the earlier eight-chapter native reader. No accessory-unlocking system is claimed in this release.

## Implementation

- Godot: GDScript, scenes, shaders, 3D mouse, 2D interface, physics, care, dialogue and saves.
- Browser adventures: HTML, CSS, JavaScript, Canvas/SVG and synthesized Web Audio.
- Art: supplied mouse model, Blender source in `source_art/Mouse.blend`, runtime rig/materials and an AI-generated laboratory background. The Blender source predates runtime glasses and procedural facial controls; those are in `character/`.
- Localization: Godot catalogs in `locales/en.json` and `locales/es.json`; the supplied HTML games retain their own embedded bilingual dictionaries.
- Saves: Godot writes to `user://`; browser games use local storage. The internal `LumenMouse` application ID remains unchanged for save compatibility. No player saves are included.

## Science, credits and licensing

Read [NASA sources and their use](docs/NASA_SOURCES.md), [AI disclosure](docs/AI_USE.md), [credits and provenance](docs/CREDITS.md), and [submission checklist](docs/SUBMISSION.md).

The repository retains its owner-selected [MIT license](LICENSE) for new original contributions. The imported Nocturne game and Mars Jelly integration retain [Apache-2.0](licenses/Nocturne-Apache-2.0.txt). Existing MIT browser components and font notices remain under [licenses](licenses). See [NOTICE](NOTICE) for license scope; the root license does not replace upstream terms. NASA and other external resources retain their own terms. This project is independent and does not imply NASA endorsement.

## Validation and limitations

The preceding game revision passed library checks in Godot 4.3 on Windows and browser tests covering mission unlocks, hints, medals, storage, English/Spanish and narrow screens. Browser unlock events were simulated; full adventures have not been played end to end. No physical Android testing or APK is provided. NASA image requests and speech depend on network access and installed voices.

After importing, run `godot --path . --script res://LibraryTest.gd` for library navigation, isolated HTML extraction and localization checks. Historical tests remain in the repository; do not interpret their presence as evidence that every test passed on this release. See [validation](docs/VALIDATION.md).

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Mars Jelly integration

English is the default for new installations, including browser games. Saved language choices remain respected; Spanish is available in Settings. Mars dialogue and interface text use the shared English and Spanish catalogs.

The supplied finished Mars Jelly project is preserved as a native story in `stories/mars/`: endless terrain, rigged Opportunity rover, three waypoint missions, four acts, storm, sound effects and ending. `stories/MarsMission.gd` isolates its 3D world and disables the host scene until returning. Leaving the story resets that run; re-entering starts from Act I. Existing care saves are unchanged.

Controls: WASD/arrows drive; Shift boosts; Space brakes; right-drag orbits; wheel zooms; Tab switches camera; Enter/E advances dialogue; R restarts; Escape returns to Stories. Desktop keyboard/mouse controls are required. Portrait windows letterbox the cinematic view. The Compatibility renderer keeps toon bands, rim light and gloss, but does not provide true subsurface scattering or Forward+ bloom.

See [integration validation](docs/MARS_INTEGRATION.md).

## Hackathon handoff

Use [the submission draft](docs/PROJECT_SUBMISSION.md) and [checklist](docs/SUBMISSION.md) to fill the official team project form. Publishing this repository does not submit the project to NASA Space Apps. The challenge-specific qualifying resource, asset rights, team registration, deadline and final demo still need confirmation.
