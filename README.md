# portal-probe

Off-tailnet (Probe A) monitor for the Ronin status portal public Funnel edge.
Every 5 min: /healthz keyword + tokenless /status app-response check; Telegram alert
on 2-strike failure, 30-min re-alert, recovery ping. State via actions/cache.
Secrets: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID.
Companion tailnet probe (Probe B): Jetson ~/Projects/scripts/portal_probe.sh.
