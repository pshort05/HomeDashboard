# HomeDashboard

A personal browser dashboard served from a Docker container on your local network. Displays grouped link cards organized into sections (External sites, Internal services, etc.), with a live clock, gear-icon editor, and a Chrome history scanner for discovering sites to add.

## Features

- Config-driven: all content lives in `config.json` — nothing hardcoded in templates
- Two section types: `external` (light background) and `internal` (dark background)
- In-browser editor at `/edit` for managing sections, cards, and links
- Chrome history scanner: shows your top 100 most-visited sites with one-click add, plus a "Not in Top 100" list of dashboard sites absent from your history with a delete button
- Live clock in the header
- Per-user color scheme (Red, Blue, Green, Grey) and local items visibility, stored in the browser via `localStorage`
- Weather widget in the header: current conditions and a scrollable 24-hour hourly forecast, powered by Open-Meteo (no API key required), refreshed every 60 minutes
- Chrome extension to override the new tab page

## Project Structure

```
HomeDashboard/
├── homedashboard/
│   ├── __init__.py
│   ├── app.py              # Flask routes and history scanner
│   └── templates/
│       ├── index.html      # Dashboard view
│       └── edit.html       # In-browser editor
├── chrome-extension/       # Chrome extension — new tab override
│   ├── manifest.json
│   ├── newtab.html / newtab.js
│   └── options.html / options.js
├── run.py                  # Entry point (local dev and Docker)
├── config.json             # Your personal config — gitignored
├── config.json.sample      # Starter template to copy
├── sync-history.sh         # Syncs Chrome history to the server
├── setup-linux.sh          # Local install script (Linux)
├── setup-mac.sh            # Local install script (macOS)
├── setup-windows.ps1       # Local install script (Windows)
├── docker-compose.yml
├── Dockerfile
└── requirements.txt
```

## Getting Started

Copy the sample config and customize it:

```bash
cp config.json.sample config.json
```

Edit `config.json` directly or use the in-browser editor at `/edit` after starting the app.

## Running Locally

Suitable for development or for using the Chrome history scanner without a separate server (Chrome history is read directly — no sync needed).

**Prerequisites:** Python 3.11+

Run the setup script for your platform:

```bash
# Linux
bash setup-linux.sh

# macOS
bash setup-mac.sh

# Windows (PowerShell)
.\setup-windows.ps1
```

The script creates `.venv/`, installs dependencies, and copies `config.json.sample` to `config.json` if no config exists yet. Each script also accepts a `--service` flag (Linux and macOS) to install and start a background service that runs automatically at login.

To start manually after setup:

```bash
.venv/bin/python run.py      # Linux / macOS
.venv\Scripts\python run.py  # Windows
```

The dashboard is available at `http://localhost:8080`.

## Deploying on a LAN with Docker

Run the container on an always-on server and set Chrome's home page to the server's IP and port.

### 1. Install Docker

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER   # log out and back in after this
```

### 2. Clone the repository on your server

```bash
git clone <repo-url> ~/HomeDashboard
cd ~/HomeDashboard
cp config.json.sample config.json
```

### 3. Choose a port

Check what is already bound to avoid conflicts:

```bash
ss -tlnp | grep LISTEN
docker ps --format '{{.Ports}}'
```

The default in `docker-compose.yml` is `8888:8080`. Change the left side if that port is taken.

### 4. Set up Chrome history syncing

The history scanner requires a copy of your Chrome `History` SQLite file on the server. The `sync-history.sh` script handles this from the machine where Chrome runs.

**Verify passwordless SSH access to the server:**

```bash
ssh <server-hostname> "echo ok"
```

If it prompts for a password, set up key-based authentication first:

```bash
ssh-keygen -t ed25519          # skip if you already have a key
ssh-copy-id <server-hostname>
```

**Edit `sync-history.sh`** to match your server hostname and repo path:

```bash
DEST="myserver:~/HomeDashboard/chrome_history"
```

**Create the placeholder file on the server** before the first sync. Without this, Docker will create a directory at that path instead of a file, which causes a startup error:

```bash
ssh <server-hostname> "touch ~/HomeDashboard/chrome_history"
```

**Run the initial sync** from the Chrome machine:

```bash
./sync-history.sh
```

### 5. Fix the crontab setgid bit (if needed)

On some Linux systems the `crontab` binary loses its setgid bit, which prevents regular users from editing their crontab. If you see `Permission denied` when running `crontab -e`, restore it:

```bash
sudo chmod g+s /usr/bin/crontab
```

Verify with `ls -la /usr/bin/crontab` — the permissions should read `-rwxr-sr-x`.

### 6. Schedule the nightly sync

On the machine where Chrome runs, add a cron job to sync at 2 AM every night:

```bash
(crontab -l 2>/dev/null; echo "0 2 * * * /path/to/HomeDashboard/sync-history.sh") | crontab -
```

Replace `/path/to/HomeDashboard` with the actual path on your machine. Confirm with `crontab -l`.

### 7. Start the container

```bash
cd ~/HomeDashboard
docker compose up -d
```

To rebuild after changing application code:

```bash
docker compose up -d --build
```

View logs:

```bash
docker compose logs -f
```

### 8. Set Chrome's startup and home page

In Chrome settings, configure the following to point to your dashboard URL (e.g. `http://192.168.1.100:8888/`):

- **On startup:** Settings → On startup → Open a specific page → Add a new page
- **Home button:** Settings → Appearance → Show home button → enter the URL

For new tabs, see the Chrome Extension section below.

## Chrome Extension

Chrome's startup and home button settings only control what opens when Chrome launches or when you click the home button. Opening a new tab always shows Chrome's built-in new tab page unless you install an extension to override it.

The `chrome-extension/` folder contains a Manifest V3 extension that replaces the new tab page with your dashboard.

### Installation

1. Open `chrome://extensions` in Chrome.
2. Enable **Developer mode** using the toggle in the top-right corner.
3. Click **Load unpacked** and select the `chrome-extension/` folder from this repository.

The extension is now active. New tabs will open your dashboard immediately.

### Configuring the URL

The extension defaults to `http://localhost:8080/`. If your dashboard runs on a different address (e.g. a LAN server), update it:

1. Go to `chrome://extensions`.
2. Find **HomeDashboard New Tab** and click **Details**.
3. Click **Extension options**.
4. Enter your dashboard URL and click **Save**.

### Updating the extension

The extension reads from local files, so no reinstallation is needed after pulling new code. If you ever need to force a reload, click the circular reload button on the extension card in `chrome://extensions`.

If the extension enters a broken state (the Details button disappears), remove it and load it again using **Load unpacked** — the reload button does not recover from a broken state.

## Configuration

All content is stored in `config.json`, which is bind-mounted into the container so edits take effect without a rebuild. Use the in-browser editor at `/edit` or edit the file directly.

### Top-level structure

```json
{
  "site": {
    "title": "My Dashboard",
    "subtitle": "Personal Home Page",
    "footer": "My Dashboard — Personal Home Page",
    "weather_label": "New York",
    "weather_lat": 40.7128,
    "weather_lon": -74.0060
  },
  "sections": []
}
```

### Weather

The weather widget is hidden until coordinates are configured. To enable it:

1. Open the in-browser editor at `/edit`.
2. In the **Preferences** sidebar on the left, find the **Weather** section.
3. Enter a **Location Name** (displayed in the popup header), **Latitude**, and **Longitude**.
4. Click **Save Changes**.

The widget will appear in the header next to the clock on the next page load. Click it to open a popup showing current temperature, humidity, wind speed, and a scrollable 24-hour hourly forecast.

If you do not know your coordinates, the **Find Coordinates** link in the Weather preferences opens [latlong.net](https://www.latlong.net/), where you can search by city or address.

To disable the widget, clear the Latitude and Longitude fields and save. The widget will disappear from the header.

**Data source:** [Open-Meteo](https://open-meteo.com/) — free, no account or API key required. Weather data is fetched server-side and cached for 60 minutes, so no location data is sent from the browser.

### Section

```json
{
  "title": "External",
  "title_suffix": "Sites",
  "type": "external",
  "cards": []
}
```

`type` must be `"external"` (light card style) or `"internal"` (dark card style).

### Card

```json
{
  "title": "Email",
  "icon": "fa-solid fa-envelope",
  "links": []
}
```

### Link

```json
{
  "label": "Gmail",
  "url": "https://mail.google.com",
  "icon": "fa-brands fa-google"
}
```

Icons use [Font Awesome 6](https://fontawesome.com/search) class strings.

## Updating

```bash
git pull
docker compose up -d --build
```

`config.json` is bind-mounted and not overwritten by a rebuild.
