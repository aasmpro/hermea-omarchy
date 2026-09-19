# Hermea Omarchy plugin instructions

This repository is the standalone Omarchy bar plugin for the Hermea Hermes
orchestrator. It is also consumed by the parent Hermea repository as a Git
submodule.

## Plugin contract

- Preserve plugin ID `hermea` unless a marketplace migration
  is explicitly planned.
- Keep `manifest.json` at the repository root.
- Keep `BarWidget.qml` as the `barWidget` entry point and preserve the public
  panel lifecycle methods used by Omarchy.
- Keep runtime dependencies documented in `README.md`.

## Safe changes

- Do not add credentials, Hermes profile data, local system state, absolute
  machine paths, or generated files.
- Keep Hermes configuration and status access scoped to the selected profile.
- Preserve safe empty-state behavior when Hermes is unavailable or
  uninitialized.
- Keep dashboard and terminal actions explicit and tied to the selected
  profile and model.

## Validation

Run these commands from the plugin root:

```bash
omarchy plugin validate .
python3 -B -m unittest discover -s tests -v
```

When available, run QML lint with the Omarchy shell import path:

```bash
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" *.qml
```

QML lint may report warnings when Omarchy's generated or runtime-only imports
are not visible to the standalone lint environment. Treat actual errors as
blocking and document environment-specific limitations.

## Publishing

- Update the plugin version in `manifest.json` and this README when releasing.
- Commit and push plugin changes here first.
- Update the parent Hermea repository's submodule pointer only after the plugin
  commit is available on the remote.
- Keep the repository root installable with:

```bash
omarchy plugin add https://github.com/aasmpro/hermea-omarchy.git --enable
```
