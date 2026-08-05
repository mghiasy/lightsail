# Telegram bot

Controls the same Lightsail create/cleanup scripts from Telegram.

## 1. Put your token in the environment

Do **not** commit the token.

```bash
export TELEGRAM_BOT_TOKEN="paste-your-token-here"
```

## 2. (Recommended) Lock the bot to your Telegram user id

Message your bot, send:

```text
/whoami
```

Then:

```bash
export TELEGRAM_ALLOWED_USER_IDS="123456789"
```

## 3. Run the bot on your Mac

AWS CLI must already be configured on this machine (same as the web app).

```bash
npm run bot
```

Open Telegram, tap your bot → **Start**, then use:

- **Create cusor_instance**
- **Clean up**

## Notes

- The bot runs the Python scripts on the machine where `npm run bot` is running.
- For phone-only use later, host this bot process in the cloud with AWS credentials.
- Outline Manager UI automation still needs a Mac desktop session; access-key fetch via API still works headlessly.
