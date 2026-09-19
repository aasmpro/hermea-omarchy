#!/usr/bin/env bash
set -u

host="127.0.0.1"
port="9119"
profile="${1:-default}"
provider="${2:-}"
model="${3:-}"
host="${4:-$host}"
port="${5:-$port}"
if [[ ! "$profile" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]]; then
  exit 2
fi
if [[ ! "$host" =~ ^[A-Za-z0-9.:-]+$ ]] || [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
  exit 2
fi
if [[ -n "$provider" && -z "$model" ]] || [[ -z "$provider" && -n "$model" ]]; then
  exit 2
fi
profile_home="$HOME/.hermes"
if [[ "$profile" != "default" ]]; then
  profile_home="$HOME/.hermes/profiles/$profile"
fi
dashboard_url="http://${host}:${port}/chat?profile=${profile}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/hermes-dashboard"
log_file="$state_root/launcher.log"
lock_dir="${XDG_RUNTIME_DIR:-/tmp}/omarchy-hermes-dashboard.lock"

mkdir -p "$state_root"

notify() {
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send "Hermea" "$1"
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "Hermea" "$1"
  fi
}

dashboard_is_listening() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :$port" 2>/dev/null | grep -q "${host}:${port}"
  else
    timeout 1 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1
  fi
}

model_is_current() {
  if [[ -z "$provider" ]]; then
    return 0
  fi
  current_provider="$(HERMES_HOME="$profile_home" hermes --profile "$profile" config get model.provider 2>/dev/null || true)"
  current_model="$(HERMES_HOME="$profile_home" hermes --profile "$profile" config get model.default 2>/dev/null || true)"
  if [[ "${current_provider//$'\n'/}" != "$provider" || "${current_model//$'\n'/}" != "$model" ]]; then
    notify "The selected Hermes model is no longer active. Refresh Hermea and try again."
    return 1
  fi
}

start_dashboard() {
  if ! command -v hermes >/dev/null 2>&1; then
    notify "The hermes command is not on PATH."
    return 1
  fi

  if command -v systemd-run >/dev/null 2>&1; then
    if systemd-run --user --quiet --collect \
      --unit="hermes-dashboard-$(date +%s%N)" \
      --property=StandardOutput=append:"$log_file" \
      --property=StandardError=append:"$log_file" \
      --setenv="HERMES_HOME=$profile_home" \
      -- hermes dashboard --no-open --host "$host" --port "$port" >>"$log_file" 2>&1; then
      return 0
    fi
  fi

  HERMES_HOME="$profile_home" nohup hermes dashboard --no-open --host "$host" --port "$port" >>"$log_file" 2>&1 &
}

wait_for_dashboard() {
  local attempt
  for attempt in $(seq 1 40); do
    if dashboard_is_listening; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

open_browser() {
  if command -v omarchy-launch-browser >/dev/null 2>&1; then
    omarchy-launch-browser "$dashboard_url"
  else
    xdg-open "$dashboard_url" >/dev/null 2>&1 &
  fi
}

if mkdir "$lock_dir" 2>/dev/null; then
  trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

  model_is_current || exit 1

  if ! dashboard_is_listening; then
    start_dashboard || exit 1
  fi

  if wait_for_dashboard; then
    open_browser
  else
    notify "Dashboard did not start on ${dashboard_url}. See ${log_file}."
    exit 1
  fi
else
  model_is_current || exit 1
  if wait_for_dashboard; then
    open_browser
  else
    notify "Dashboard startup is already in progress."
    exit 1
  fi
fi
