# Hermea Omarchy plugin (0.1.0)

The Hermes bar icon opens a focused dashboard for inspecting and controlling one
selected Hermes profile. Opening the panel never starts the web dashboard.
The layout follows Omarchy's Wi-Fi panel: a large profile glyph anchors the
hero, the profile name is the primary text, the active model appears beneath it
in muted text, and status content is grouped into compact details.

This repository is the standalone Omarchy integration for the larger [Hermea
orchestrator](https://github.com/aasmpro/hermea) project. It is also included
there as the `plugins/omarchy/hermea` submodule for coordinated development.

## Install

Install the standalone plugin repository with Omarchy:

```bash
omarchy plugin add https://github.com/aasmpro/hermea-omarchy.git --enable
```

The plugin expects Hermes Agent to be installed separately. After Hermes has
created at least one profile, add `io.github.aasmpro.hermea` to the desired bar section
if Omarchy did not place it automatically.

## Remove

```bash
omarchy plugin remove io.github.aasmpro.hermea
```

Removing the plugin does not delete Hermes profiles, model configuration, or
profile icon settings.

## Features

### Profile-aware status

The panel keeps a separate report for each selected Hermes profile and refreshes
the active report in the background. It displays compact status values for:

- **Gateway**: Hermes gateway service state and manager;
- **Dashboard**: availability of the configured local dashboard listener;
- **Sessions**: active sessions for the selected profile;
- **Jobs**: configured active and total scheduled jobs;
- **Version**: installed Hermes version;
- **Skills**: installed and recently used profile skills.

Unknown or failed values stay isolated to their own status item. A failed model
catalog does not hide profile status, and a dashboard outage does not prevent
CLI chats.

### Profile and model controls

- Select a profile from the text-style profile control in the hero.
- Choose a profile icon from 25 AI-oriented icons in a 5×5 popup.
- Search every model available to the selected profile.
- See each model's provider, type, pricing information, and active-model marker.
- Apply model changes immediately to the selected Hermes profile.
- Keep Chat and Dashboard actions visible but disabled while a model change is
  being written.

### Chat and dashboard actions

The Chat action opens a new terminal with the selected profile, provider, and
model. It does not change Hermes's sticky active profile.

The Dashboard action checks the selected model, starts Hermes Dashboard when it
is not already listening, waits for readiness, and opens the selected profile's
chat route in the browser:

```text
http://HOST:PORT/chat?profile=PROFILE
```

### Safe first run

When Hermes is not installed, has no initialized profile, or the configured
profile is unavailable, the panel returns a controlled empty state. It does
not show a traceback, write Hermes configuration, or launch actions with stale
profile/model data. The panel can recover after Hermes is initialized and the
next refresh completes.

### Profile persistence

Hermea keeps responsibilities separate:

- plugin behavior is configured in Omarchy's `shell.json` entry;
- model provider and model settings are written to the selected Hermes profile;
- profile icons are stored in that profile's `profile.yaml` under `ui`;
- dashboard launcher diagnostics are stored under the user's Omarchy state
  directory.

## Controls

The hero contains the enlarged per-profile icon, a clickable text-style profile
selector, a clickable muted model selector, and borderless Chat and Dashboard
buttons on the right. The selectors show only their current text in the hero;
clicking either one opens its normal selection popup. Status refresh remains
available through the existing background timer and `R` keyboard shortcut,
without a visible status header or refresh control.

The centered **Profile** dropdown selects the profile used by the rest of the
panel. The selection is local to this panel: it does not run `hermes profile
use` or change `~/.hermes/active_profile`.

The model picker supports search and starts on the selected profile's current
model. Both actions use the selected profile; Chat also passes
the selected provider and model explicitly, while the dashboard reads that
profile's persisted model configuration. Chat opens a new default terminal
running `hermes --profile NAME --cli`; it starts a fresh chat
and leaves the sticky Hermes default untouched. The model control is grouped
with the controls and persists a selection only in the selected profile's
`config.yaml`. Profile icon settings are stored independently in that profile's
`profile.yaml` under the extensible `ui` namespace.

Hermea expects Hermes Agent to be installed and initialized separately. If
Hermes has not created a profile yet, the widget remains visible and shows a
safe setup state until a profile becomes available.

The **Dashboard** quick action is a button. Clicking it invokes
`open-dashboard.sh`, which
reuses the configured listener or starts Hermes dashboard in the background and
opens it in the browser. It verifies that the selected provider and model are
still active before opening the browser, then closes the panel after handoff.

Escape or an outside click closes the panel. Arrow keys or H/J/K/L move through
the status refresh icon, profile dropdown, model dropdown, Chat button, and
Dashboard button. Enter or Space activates the selected control. Tab moves to
the neighboring Omarchy panel. A dropdown keeps keyboard focus until it is closed.

## Status and models

The **STATUS** section uses the Omarchy Wi-Fi details layout: a separator and a
four-column label/value grid with two status pairs per row. It uses the same
compact body-small typography, muted labels, right-aligned values, and tight
spacing, without decorative icons or secondary descriptions. Healthy, unknown,
and failed values keep their existing color treatment. The session row shows
active sessions for the selected profile. Dashboard checks the configured
listener:

| Card | Source | Meaning |
| --- | --- | --- |
| Gateway | `hermes --profile NAME status` | Hermes-reported service state and manager |
| Dashboard | TCP connection to the configured host and port | Local listener availability, not HTTP/authentication health |
| Sessions | `hermes --profile NAME status` | Active sessions for the selected profile, not open CLI terminal windows |
| Jobs | Hermes status | Enabled and total job configuration, not scheduler health |
| Version | `hermes --version` | Installed Hermes version and health |
| Skills | Profile `skills/` and `.usage.json` | Installed and recently used skill counts |

The searchable model picker queries Hermes's installed profile-scoped inventory
and shows every model currently available to that profile. It opens on the
profile's current model and supports searching by provider or model name. The
normal picker uses Hermes's one-hour catalog cache; the status refresh icon asks
Hermes to fetch provider catalogs again.

Before saving a model choice, the helper rechecks that exact provider/model pair
against the current permitted catalog. A provider change clears stale
`model.base_url` and `model.context_length` from that profile, then writes
`model.provider` and `model.default`. No other profile is changed.

## Helper contract

`hermes-panel.py` uses Python's standard library plus Hermes's installed Python
package. It discovers that package through `mise where 'pipx:hermes-agent[extras=all]'`,
so it continues to follow Hermes upgrades managed by Omarchy. PyYAML is loaded
from the Hermes environment when it is not installed in the system Python.

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/io.github.aasmpro.hermea"
python3 "$PLUGIN_DIR/hermes-panel.py" snapshot default
python3 "$PLUGIN_DIR/hermes-panel.py" model-catalog default
python3 "$PLUGIN_DIR/hermes-panel.py" chat default
```

`snapshot PROFILE [--refresh-models] [--dashboard-host HOST] [--dashboard-port PORT]`
emits JSON schema version 4. It contains availability, the version, selected
profile, selectable profiles with profile icon metadata, six status cards, all
model options, and short diagnostics. Raw Hermes status output and credentials
never leave the helper. Status/version calls have a five-second deadline; model
catalog discovery has a separate fifteen-second deadline. Missing Hermes or an
uninitialized profile produces a valid empty snapshot instead of a traceback.
Partial failures keep independent cards usable. The QML panel retains the last
valid profile report if a complete snapshot fails.

The panel caches the latest snapshot separately for each profile. A cached
profile is shown immediately when selected, while its next snapshot refreshes
in the background. Profile icons are selected from 25 named AI-oriented icons;
the picker closes on outside click or Escape. Saving an icon updates the current
header immediately and temporarily locks profile switching until Hermes stores
the setting.

`set-model PROFILE PROVIDER MODEL` is intentionally internal to the panel. It
validates the live catalog before it writes configuration. `chat PROFILE`
validates that the profile directory still exists before opening the terminal.

## Settings

Hermea follows Omarchy's inline bar-widget settings model. Add settings to the
`io.github.aasmpro.hermea` entry in `~/.config/omarchy/shell.json`; unknown or invalid
values fall back to the defaults below.

| Setting | Default | Purpose |
| --- | --- | --- |
| `refreshIntervalSeconds` | `15` | Background status refresh interval, clamped to 5–300 seconds |
| `refreshModelsOnOpen` | `false` | Refresh provider catalogs on panel open |
| `defaultProfile` | `default` | Profile selected when the panel is first opened |
| `dashboardHost` | `127.0.0.1` | Hermes dashboard bind address |
| `dashboardPort` | `9119` | Hermes dashboard port |
| `panelWidth` | `440` | Panel width, clamped to 320–720 |
| `panelMaxHeight` | `530` | Panel height limit, clamped to 360–900 |
| `visibleStatusCards` | all six cards | Status IDs to display |
| `showChatAction` | `true` | Show the Chat action |
| `showDashboardAction` | `true` | Show the Dashboard action |

Example:

```json
{
  "id": "io.github.aasmpro.hermea",
  "refreshIntervalSeconds": 30,
  "defaultProfile": "default",
  "dashboardHost": "127.0.0.1",
  "dashboardPort": 9119,
  "visibleStatusCards": ["gateway", "dashboard", "sessions", "version"],
  "showChatAction": true,
  "showDashboardAction": true
}
```

These plugin settings are separate from Hermes profile configuration. The
selected model is stored by Hermes in the selected profile, and profile icons
are stored under that profile's `ui` settings.

## Validation and troubleshooting

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/io.github.aasmpro.hermea"
jq empty "$PLUGIN_DIR/manifest.json"
bash -n "$PLUGIN_DIR/open-dashboard.sh"
omarchy plugin validate "$PLUGIN_DIR"
python3 -B -m unittest discover -s "$PLUGIN_DIR/tests" -v
qmllint -I "$OMARCHY_PATH/shell" "$PLUGIN_DIR/BarWidget.qml" "$PLUGIN_DIR/Panel.qml"
```

The tests cover the six-card snapshot contract, version and skills parsing,
profile icon fallback/read/write with unrelated YAML preservation, panel-local
chat launch, full catalog discovery, model validation/config writes, and
dashboard probe states. They mock launch actions and never modify your Hermes
profiles.

If the model list is empty, refresh the badge and confirm Hermes authentication
and provider configuration for that profile. A missing Hermes installation or
profile leaves the panel in a safe setup state and disables profile actions.
Dashboard launcher diagnostics are in
`${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/hermes-dashboard/launcher.log`.

User plugin files hot-reload. If Quickshell retains an older component, run
`omarchy restart shell`. Upgrades may leave a pre-change backup in Omarchy's
local state directory.
