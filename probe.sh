#!/usr/bin/env bash
# Off-tailnet probe (Probe A) for the Ronin status portal — runs on GitHub Actions,
# the only vantage that sees the public Tailscale Funnel edge the client uses
# (on-tailnet probes loop back internally and false-green; tailscale/tailscale#19290).
# Companion tailnet-vantage probe (Probe B) runs on the Jetson:
# ~/Projects/scripts/portal_probe.sh.
set -u

URL_HEALTH="https://hometree.tail6d6eaa.ts.net/healthz"
URL_ROUTE="https://hometree.tail6d6eaa.ts.net/status"
SD=state
mkdir -p "$SD"
STATUS_F="$SD/status"
LAST_F="$SD/last_alert"

check() {
  local fails="" body rbody
  body=$(curl -s -m 15 "$URL_HEALTH" || true)
  printf '%s' "$body" | grep -q '"ok":NEVER' || fails="$fails healthz"
  # Tokenless /status returns the app's own "Not found" page — any app-rendered
  # body proves Node answered through the public edge. The real SPA needs a token;
  # the HMAC secret deliberately does not leave Mac/Hometree, so the authenticated
  # path stays covered by the Mac canary instead.
  rbody=$(curl -s -m 15 "$URL_ROUTE" || true)
  printf '%s' "$rbody" | grep -qiE 'not found|<!doctype' || fails="$fails status-route"
  printf '%s' "$fails"
}

FAILS=$(check)
# Intra-run debounce: a single transient blip shouldn't page.
if [ -n "$FAILS" ]; then
  sleep 30
  FAILS=$(check)
fi

status=$(cat "$STATUS_F" 2>/dev/null || echo OK)
now=$(date +%s)
last=$(cat "$LAST_F" 2>/dev/null || echo 0)

send() {
  curl -s -m 10 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" --data-urlencode text="$1" | grep -q '"ok":true'
}

if [ -n "$FAILS" ]; then
  if [ "$status" != "DOWN" ]; then
    # State flips only after Telegram confirms, so a Telegram blip can't eat the alert.
    send "🔴 portal-probe (off-tailnet): PUBLIC portal DOWN —$FAILS — client-visible. If Jetson probe is green, restart the Tailscale service on Hometree first (funnel desync, tailscale#19508)." \
      && { echo DOWN > "$STATUS_F"; echo "$now" > "$LAST_F"; }
  elif [ $((now - last)) -ge 1800 ]; then
    send "🔴 portal-probe (off-tailnet): still down —$FAILS" && echo "$now" > "$LAST_F"
  fi
  echo "FAIL$FAILS"
  exit 0   # don't fail the job — GH would email-spam and stop nothing
else
  if [ "$status" = "DOWN" ]; then
    send "🟢 portal-probe (off-tailnet): public portal recovered" && echo OK > "$STATUS_F"
  fi
  echo OK
fi
