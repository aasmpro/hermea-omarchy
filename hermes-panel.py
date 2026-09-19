#!/usr/bin/env python3
"""Profile-scoped status, model, and chat adapter for the Omarchy Hermes panel."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sqlite3
import site
import socket
import subprocess
import sys

try:
    import yaml
except ImportError:
    yaml = None

PROFILE_ID = re.compile(r"[a-z0-9][a-z0-9_-]{0,63}\Z")
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
CARD_LABELS = {"gateway": "Gateway", "dashboard": "Dashboard", "sessions": "Sessions", "jobs": "Jobs", "version": "Version", "skills": "Skills"}
DEFAULT_PROFILE_ICON = "󱚣"
PROFILE_ICON_MAX_LENGTH = 8
COMMAND_TIMEOUT = 5
MODEL_TIMEOUT = 15
SNAPSHOT_SCHEMA_VERSION = 4
DEFAULT_DASHBOARD_HOST = "127.0.0.1"
DEFAULT_DASHBOARD_PORT = 9119
PROFILE_ICON_GLYPHS = frozenset((
    "󱚣", "󰚩", "󰘦", "", "󰧑", "", "󱕅", "", "", "",
    "󰀄", "", "", "󰒋", "", "", "󰭻", "󰆍", "󰏗", "󰒍", "",
    "", "󰈹", "󰕮", "", "",
))


class ProbeError(Exception):
    """An allowlisted diagnostic suitable for the panel."""


def load_yaml():
    """Load PyYAML from the system or Hermes-managed Python environment."""
    global yaml
    if yaml is not None:
        return yaml
    if shutil.which("mise"):
        try:
            _, install_root = run_process(["mise", "where", "pipx:hermes-agent[extras=all]"], dict(os.environ))
            candidates = list((Path(install_root.strip()) / "hermes-agent" / "lib").glob("python*/site-packages"))
            if len(candidates) == 1 and candidates[0].is_dir():
                site.addsitedir(str(candidates[0]))
                import yaml as yaml_module
                yaml = yaml_module
                return yaml
        except (ImportError, OSError, ProbeError):
            pass
    raise ProbeError("YAML support is unavailable. Install Hermes Agent before editing profile icons.")


def clean(text):
    return "".join(c for c in ANSI.sub("", text) if c >= " " or c in "\n\t")


def card(key, value="Unknown", state="unknown", detail=None):
    return {"id": key, "label": CARD_LABELS[key], "value": value, "state": state, "detail": detail}


def profile_config_path(home, name):
    return profile_dir(home, name) / "profile.yaml"


def read_profile_settings(home, name):
    path = profile_config_path(home, name)
    if not path.is_file():
        return {}
    try:
        yaml_module = load_yaml()
        payload = yaml_module.safe_load(path.read_text(encoding="utf-8")) or {}
    except (OSError, ProbeError, yaml.YAMLError if yaml is not None else Exception) as error:
        raise ProbeError("Could not read the Hermes profile settings.") from error
    if not isinstance(payload, dict):
        raise ProbeError("Hermes profile settings must be a YAML mapping.")
    ui = payload.get("ui", {})
    return ui if isinstance(ui, dict) else {}


def profile_icon(home, name):
    icon = read_profile_settings(home, name).get("profile_icon")
    return icon if icon in PROFILE_ICON_GLYPHS else DEFAULT_PROFILE_ICON


def write_profile_icon(home, name, icon):
    if icon not in PROFILE_ICON_GLYPHS:
        raise ProbeError("Invalid profile icon.")
    path = profile_config_path(home, name)
    try:
        yaml_module = load_yaml()
        payload = yaml_module.safe_load(path.read_text(encoding="utf-8")) if path.is_file() else {}
        if payload is None:
            payload = {}
        if not isinstance(payload, dict):
            raise ProbeError("Hermes profile settings must be a YAML mapping.")
        ui = payload.setdefault("ui", {})
        if not isinstance(ui, dict):
            raise ProbeError("Hermes profile UI settings must be a YAML mapping.")
        ui["profile_icon"] = icon
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml_module.safe_dump(payload, sort_keys=False, allow_unicode=True), encoding="utf-8")
    except ProbeError:
        raise
    except (OSError, ProbeError, yaml.YAMLError if yaml is not None else Exception) as error:
        raise ProbeError("Could not save the Hermes profile icon.") from error
    return 0


def profile_dir(home, name):
    if not PROFILE_ID.fullmatch(name):
        raise ProbeError("Invalid Hermes profile name.")
    path = home / ".hermes" if name == "default" else home / ".hermes" / "profiles" / name
    if not path.is_dir():
        raise ProbeError("This Hermes profile no longer exists. Refresh the panel.")
    return path


def discover_profiles(home):
    root = home / ".hermes"
    profiles, errors = [], []
    if root.is_dir():
        try:
            icon = profile_icon(home, "default")
        except ProbeError:
            icon = DEFAULT_PROFILE_ICON
        profiles.append({"name": "default", "icon": icon})
    else:
        errors.append("Hermes home directory was not found.")
    try:
        profiles_dir = root / "profiles"
        if profiles_dir.is_dir():
            for entry in sorted(profiles_dir.iterdir(), key=lambda item: item.name):
                if entry.is_dir() and entry.name != "default" and PROFILE_ID.fullmatch(entry.name):
                    try:
                        icon = profile_icon(home, entry.name)
                    except ProbeError:
                        icon = DEFAULT_PROFILE_ICON
                    profiles.append({"name": entry.name, "icon": icon})
    except OSError:
        errors.append("Could not list Hermes profiles.")
    return profiles, errors


def hermes_env(root, interactive=False):
    env = dict(os.environ)
    env["HERMES_HOME"] = str(root)
    if not interactive:
        env.update(NO_COLOR="1", TERM="dumb")
    return env


def run_process(command, env, timeout=COMMAND_TIMEOUT, check=True):
    try:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              stdin=subprocess.DEVNULL, text=True, encoding="utf-8",
                              errors="replace", env=env, start_new_session=True) as process:
            try:
                output, _ = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.communicate()
                raise ProbeError(f"Hermes command timed out after {timeout} seconds.") from None
            if check and process.returncode:
                raise ProbeError("Hermes command failed.")
            return process.returncode, output
    except OSError:
        raise ProbeError("Could not execute Hermes.") from None


def run_hermes(arguments, root, check=True):
    if not shutil.which("hermes"):
        raise ProbeError("The hermes command is not on PATH.")
    return run_process(["hermes", *arguments], hermes_env(root), check=check)


def parse_status(text):
    sections, current = {}, None
    for line in clean(text).splitlines():
        heading = re.match(r"^\s*◆\s+(.+?)\s*$", line)
        if heading:
            current = heading.group(1)
            sections[current] = {}
        elif current:
            field = re.match(r"^\s{2,}([^:]+):\s*(.*?)\s*$", line)
            if field:
                sections[current][field.group(1).strip()] = field.group(2)
    cards = {key: card(key) for key in ("gateway", "sessions", "jobs")}
    gateway = sections.get("Gateway Service", {})
    state = re.fullmatch(r"[✓✗]?\s*(running|stopped|unknown)", gateway.get("Status", ""))
    if state and state.group(1) != "unknown":
        running = state.group(1) == "running"
        cards["gateway"] = card("gateway", "Running" if running else "Stopped", "ok" if running else "inactive", gateway.get("Manager", "")[:160] or None)
    active = sections.get("Sessions", {}).get("Active", "")
    count = re.fullmatch(r"(\d+)(?: session\(s\)| sessions?)?", active)
    if count:
        cards["sessions"] = card("sessions", str(int(count.group(1))), "neutral", "Selected profile only")
    jobs = sections.get("Scheduled Jobs", {}).get("Jobs", "")
    counts = re.fullmatch(r"(\d+) active, (\d+) total", jobs)
    if counts and int(counts.group(1)) <= int(counts.group(2)):
        cards["jobs"] = card("jobs", f"{int(counts.group(1))} enabled / {int(counts.group(2))} total", "neutral", "Job configuration, not scheduler health")
    elif jobs == "0":
        cards["jobs"] = card("jobs", "0 enabled / 0 total", "neutral", "Job configuration, not scheduler health")
    missing = [item["label"] for item in cards.values() if item["state"] == "unknown"]
    return cards, ["Unavailable Hermes fields: " + ", ".join(missing) + "."] if missing else []


def skill_counts(root):
    skills_root = root / "skills"
    installed = 0
    installed_names = set()
    if skills_root.is_dir():
        installed_names = {entry.name for entry in skills_root.iterdir() if entry.is_dir() and (entry / "SKILL.md").is_file()}
        installed = len(installed_names)
    used = 0
    usage_path = skills_root / ".usage.json"
    if usage_path.is_file():
        try:
            usage = json.loads(usage_path.read_text(encoding="utf-8"))
            if isinstance(usage, dict):
                used = sum(1 for name, item in usage.items() if name in installed_names and isinstance(item, dict) and item.get("last_used_at"))
        except (OSError, json.JSONDecodeError):
            pass
    return installed, min(used, installed)


def profile_session_count(root):
    database = root / "state.db"
    if not database.is_file():
        return None
    try:
        connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=1)
        try:
            row = connection.execute("SELECT COUNT(*) FROM sessions").fetchone()
            return int(row[0]) if row else 0
        finally:
            connection.close()
    except (sqlite3.Error, OSError):
        return None


def parse_version(text):
    match = re.search(r"\bHermes Agent v(\d[\w.+-]*)", clean(text))
    if not match:
        raise ProbeError("Hermes version output was not recognized.")
    return match.group(1)


def dashboard_url(host=DEFAULT_DASHBOARD_HOST, port=DEFAULT_DASHBOARD_PORT):
    if not re.fullmatch(r"[A-Za-z0-9.:-]+", str(host)):
        raise ProbeError("Invalid dashboard host.")
    if not 1 <= int(port) <= 65535:
        raise ProbeError("Invalid dashboard port.")
    return f"http://{host}:{int(port)}"


def probe_dashboard(host=DEFAULT_DASHBOARD_HOST, port=DEFAULT_DASHBOARD_PORT):
    url = dashboard_url(host, port)
    try:
        with socket.create_connection((host, int(port)), timeout=1):
            return card("dashboard", url, "ok"), []
    except ConnectionRefusedError:
        return card("dashboard", url, "inactive"), []
    except OSError as error:
        detail = "Dashboard probe timed out." if isinstance(error, TimeoutError) else "Could not check the dashboard endpoint."
        return card("dashboard", url, "unknown", detail), [detail]


def load_hermes_modules(root):
    if not shutil.which("mise"):
        raise ProbeError("Could not locate the installed Hermes modules.")
    _, install_root = run_process(["mise", "where", "pipx:hermes-agent[extras=all]"], dict(os.environ))
    candidates = list((Path(install_root.strip()) / "hermes-agent" / "lib").glob("python*/site-packages"))
    if len(candidates) != 1 or not candidates[0].is_dir():
        raise ProbeError("Could not locate the installed Hermes modules.")
    site.addsitedir(str(candidates[0]))
    load_yaml()


@contextmanager
def scoped_hermes_home(root):
    load_hermes_modules(root)
    from hermes_constants import reset_hermes_home_override, set_hermes_home_override
    token = set_hermes_home_override(str(root))
    try:
        yield
    finally:
        reset_hermes_home_override(token)


def live_models(profile, home, refresh=False):
    root = profile_dir(home, profile)
    with scoped_hermes_home(root):
        from hermes_cli.inventory import build_models_payload, load_picker_context
        payload = build_models_payload(load_picker_context(), explicit_only=False, picker_hints=True,
                                       canonical_order=True, pricing=True, capabilities=False, refresh=refresh,
                                       probe_custom_providers=False, probe_current_custom_provider=False)
    options = []
    current = {"provider": str(payload.get("provider", "")), "model": str(payload.get("model", ""))}
    def model_icon(provider, model):
        name = model.lower()
        if "claude" in name: return "󱚣"
        if "gemini" in name: return "󰫢"
        if "deepseek" in name: return "󰭻"
        if "qwen" in name: return "󰯍"
        if "gpt" in name or provider == "openai-codex": return "󰘦"
        return {"moa": "󰚩", "copilot": "󰊤"}.get(provider, "󰘦")

    def model_description(row, model):
        pricing = row.get("pricing", {}).get(model, {}) if isinstance(row.get("pricing", {}), dict) else {}
        if pricing.get("free") or model.endswith(":free"):
            return "Free"
        if pricing.get("input") or pricing.get("output"):
            return "Paid · " + str(pricing.get("input") or "-") + " in · " + str(pricing.get("output") or "-") + " out / 1M"
        return "Paid · usage based"
    for row in payload.get("providers", []):
        provider = str(row.get("slug", ""))
        models = [str(model) for model in row.get("models", [])] if isinstance(row.get("models", []), list) else []
        provider_names = {"openai-codex": "OpenAI Codex", "nous": "Nous"}
        prefix = provider_names.get(provider, provider.replace("-", " ").title())
        for model in models:
            options.append({"provider": provider, "model": model, "value": provider + "\u001f" + model,
                            "label": prefix + " · " + model,
                            "providerLabel": prefix, "modelLabel": model,
                            "icon": model_icon(provider, model),
                            "description": model_description(row, model),
                            "current": provider == current["provider"] and model == current["model"]})
    current_value = current["provider"] + "\u001f" + current["model"]
    if current["provider"] and current["model"] and not any(option["value"] == current_value for option in options):
        prefix = {"openai-codex": "OpenAI Codex", "nous": "Nous"}.get(current["provider"], current["provider"].replace("-", " ").title())
        options.append({"provider": current["provider"], "model": current["model"], "value": current_value,
                        "label": prefix + " · " + current["model"],
                        "providerLabel": prefix, "modelLabel": current["model"],
                        "icon": model_icon(current["provider"], current["model"]),
                        "description": "Free" if current["model"].endswith(":free") else "Paid · usage based",
                        "current": True})
    options.sort(key=lambda option: (option["provider"], option["model"]))
    selected = next((option["value"] for option in options if option["provider"] == current["provider"] and option["model"] == current["model"]), "")
    return {"options": options, "selected": selected, "current": current, "currentAllowed": selected != ""}


def run_internal_models(profile, home, refresh=False):
    command = [sys.executable, str(Path(__file__).resolve()), "model-catalog", profile]
    if refresh:
        command.append("--refresh")
    _, output = run_process(command, dict(os.environ), timeout=MODEL_TIMEOUT, check=True)
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        raise ProbeError("Could not read the Hermes model catalog.") from None


def empty_snapshot(profile, errors, profiles=None, host=DEFAULT_DASHBOARD_HOST, port=DEFAULT_DASHBOARD_PORT):
    cards = {key: card(key) for key in CARD_LABELS}
    try:
        cards["dashboard"], dashboard_errors = probe_dashboard(host, port)
        errors.extend(dashboard_errors)
    except ProbeError as error:
        errors.append(str(error))
    return {"schemaVersion": SNAPSHOT_SCHEMA_VERSION, "collectedAt": datetime.now(timezone.utc).isoformat(),
            "available": False, "version": None, "profile": profile, "profiles": profiles or [],
            "cards": [cards[key] for key in CARD_LABELS],
            "models": {"options": [], "selected": "", "current": {}, "currentAllowed": False},
            "errors": list(dict.fromkeys(errors))}


def snapshot(profile, home, refresh_models=False, host=DEFAULT_DASHBOARD_HOST, port=DEFAULT_DASHBOARD_PORT):
    profiles, errors = discover_profiles(home)
    root = home / ".hermes" if profile == "default" else home / ".hermes" / "profiles" / profile
    if not shutil.which("hermes"):
        errors.append("The hermes command is not on PATH.")
        return empty_snapshot(profile, errors, profiles, host, port)
    if not root.is_dir():
        errors.append("Hermes is not initialized for this profile.")
        return empty_snapshot(profile, errors, profiles, host, port)
    if profile not in {item["name"] for item in profiles}:
        errors.append("This Hermes profile no longer exists. Refresh the panel.")
        return empty_snapshot(profile, errors, profiles, host, port)
    cards = {key: card(key) for key in CARD_LABELS}
    version = None
    models = {"options": [], "selected": "", "current": {}, "currentAllowed": False}
    installed_skills, used_skills = skill_counts(root)
    cards["skills"] = card("skills", f"{installed_skills} installed / {used_skills} used", "neutral", "Selected profile skill inventory")
    try:
        icon = profile_icon(home, profile)
        for item in profiles:
            if item["name"] == profile:
                item["icon"] = icon
    except ProbeError as error:
        errors.append(str(error))
    with ThreadPoolExecutor(max_workers=5) as pool:
        dashboard_future = pool.submit(probe_dashboard, host, port)
        version_future = pool.submit(run_hermes, ["--version"], root)
        status_future = pool.submit(run_hermes, ["--profile", profile, "status"], root)
        sessions_future = pool.submit(profile_session_count, root)
        models_future = pool.submit(run_internal_models, profile, home, refresh_models)
        try:
            parsed, parse_errors = parse_status(status_future.result()[1])
            cards.update(parsed)
            errors.extend(parse_errors)
        except ProbeError as error:
            errors.append(str(error))
        session_count = sessions_future.result()
        if session_count is not None:
            cards["sessions"] = card("sessions", str(session_count), "neutral", "Selected profile sessions")
        try:
            version = parse_version(version_future.result()[1])
            cards["version"] = card("version", version, "ok", "Installed Hermes version")
        except ProbeError as error:
            errors.append(str(error))
        try:
            models = models_future.result()
        except ProbeError as error:
            errors.append(str(error))
        cards["dashboard"], dashboard_errors = dashboard_future.result()
        errors.extend(dashboard_errors)
    return {"schemaVersion": SNAPSHOT_SCHEMA_VERSION, "collectedAt": datetime.now(timezone.utc).isoformat(),
            "available": True, "version": version,
            "profile": profile, "profiles": profiles, "cards": [cards[key] for key in CARD_LABELS],
            "models": models, "errors": list(dict.fromkeys(errors))}


def notify(message):
    for executable in ("omarchy-notification-send", "notify-send"):
        if shutil.which(executable):
            try:
                subprocess.run([executable, "Hermes", message], timeout=2,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            except (OSError, subprocess.TimeoutExpired):
                pass
            return


def launch_chat(profile, provider, model, home):
    try:
        root = profile_dir(home, profile)
        for executable in ("hermes", "xdg-terminal-exec"):
            if not shutil.which(executable):
                raise ProbeError(f"The {executable} command is not on PATH.")
        command = ["xdg-terminal-exec", f"--dir={home}", "--", "hermes", "--profile", profile]
        if provider:
            command.extend(["--provider", provider])
        if model:
            command.extend(["--model", model])
        command.append("--cli")
        process = subprocess.Popen(command,
                                   env=hermes_env(root, interactive=True), stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            if process.wait(timeout=2):
                raise ProbeError("The terminal could not start Hermes.")
        except subprocess.TimeoutExpired:
            pass
        return 0
    except (ProbeError, OSError) as error:
        notify(str(error) if isinstance(error, ProbeError) else "Could not launch the terminal.")
        return 1


def set_model(profile, provider, model, home):
    try:
        root = profile_dir(home, profile)
        catalog = run_internal_models(profile, home)
        allowed = next((option for option in catalog.get("options", []) if option.get("provider") == provider and option.get("model") == model), None)
        if not allowed:
            raise ProbeError("That model is not available for this profile.")
        _, current_provider = run_hermes(["--profile", profile, "config", "get", "model.provider"], root)
        if current_provider.strip() and current_provider.strip() != provider:
            run_hermes(["--profile", profile, "config", "unset", "model.base_url"], root, check=False)
            run_hermes(["--profile", profile, "config", "unset", "model.context_length"], root, check=False)
        run_hermes(["--profile", profile, "config", "set", "model.provider", provider], root)
        run_hermes(["--profile", profile, "config", "set", "model.default", model], root)
        return 0
    except ProbeError as error:
        notify(str(error))
        return 1


def set_profile_icon(profile, icon, home):
    try:
        profile_dir(home, profile)
        return write_profile_icon(home, profile, icon)
    except ProbeError as error:
        notify(str(error))
        return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    snapshot_parser = commands.add_parser("snapshot")
    snapshot_parser.add_argument("profile")
    snapshot_parser.add_argument("--refresh-models", action="store_true")
    snapshot_parser.add_argument("--dashboard-host", default=DEFAULT_DASHBOARD_HOST)
    snapshot_parser.add_argument("--dashboard-port", type=int, default=DEFAULT_DASHBOARD_PORT)
    chat = commands.add_parser("chat")
    chat.add_argument("profile")
    chat.add_argument("provider", nargs="?", default="")
    chat.add_argument("model", nargs="?", default="")
    setter = commands.add_parser("set-model")
    setter.add_argument("profile")
    setter.add_argument("provider")
    setter.add_argument("model")
    icon_setter = commands.add_parser("set-profile-icon")
    icon_setter.add_argument("profile")
    icon_setter.add_argument("icon")
    catalog = commands.add_parser("model-catalog")
    catalog.add_argument("profile")
    catalog.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    home = Path.home()
    if args.command == "snapshot":
        print(json.dumps(snapshot(args.profile, home, args.refresh_models, args.dashboard_host, args.dashboard_port), ensure_ascii=False))
    elif args.command == "chat":
        return launch_chat(args.profile, args.provider, args.model, home)
    elif args.command == "set-model":
        return set_model(args.profile, args.provider, args.model, home)
    elif args.command == "set-profile-icon":
        return set_profile_icon(args.profile, args.icon, home)
    else:
        print(json.dumps(live_models(args.profile, home, args.refresh), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
