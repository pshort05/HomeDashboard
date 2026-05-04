import json
import os
import platform
import shutil
import sqlite3
import time
import urllib.request
from collections import defaultdict
from pathlib import Path
from urllib.parse import urlparse

from flask import Flask, abort, jsonify, render_template, request, Response
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)
CONFIG_PATH = Path(__file__).parent.parent / 'config.json'


def _chrome_history_path() -> Path:
    system = platform.system()
    if system == 'Darwin':
        return Path.home() / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'Default' / 'History'
    if system == 'Windows':
        local = os.environ.get('LOCALAPPDATA', '')
        return Path(local) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'History'
    return Path.home() / '.config' / 'google-chrome' / 'Default' / 'History'


CHROME_HISTORY = _chrome_history_path()


_weather_cache = {'data': None, 'fetched_at': 0.0, 'lat': None, 'lon': None}
_WEATHER_TTL = 3600


def _fetch_weather(lat, lon):
    url = (
        'https://api.open-meteo.com/v1/forecast'
        f'?latitude={lat}&longitude={lon}'
        '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m'
        '&hourly=temperature_2m,weather_code,precipitation_probability'
        '&temperature_unit=fahrenheit&wind_speed_unit=mph&forecast_days=2&timezone=auto'
    )
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read().decode())


@app.route('/api/weather')
def get_weather():
    cfg = load_config()
    site = cfg.get('site', {})
    lat = site.get('weather_lat')
    lon = site.get('weather_lon')
    if lat is None or lon is None:
        return jsonify({'error': 'no location configured'}), 404
    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return jsonify({'error': 'invalid location'}), 400

    now = time.time()
    if (_weather_cache['data'] is not None
            and _weather_cache['lat'] == lat
            and _weather_cache['lon'] == lon
            and now - _weather_cache['fetched_at'] < _WEATHER_TTL):
        return jsonify(_weather_cache['data'])

    try:
        data = _fetch_weather(lat, lon)
    except Exception as exc:
        return jsonify({'error': str(exc)}), 502

    _weather_cache['data'] = data
    _weather_cache['fetched_at'] = now
    _weather_cache['lat'] = lat
    _weather_cache['lon'] = lon
    return jsonify(data)


@app.template_filter('origin')
def origin_filter(url):
    try:
        p = urlparse(url)
        if p.scheme in ('http', 'https') and p.netloc:
            return f"{p.scheme}://{p.netloc}"
    except Exception:
        pass
    return ''


def load_config():
    with open(CONFIG_PATH, encoding='utf-8') as f:
        return json.load(f)


def save_config(data):
    with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


_requests = Counter(
    'homedashboard_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status'],
)


@app.after_request
def _track(response):
    _requests.labels(
        method=request.method,
        endpoint=request.endpoint or 'unknown',
        status=str(response.status_code),
    ).inc()
    return response


@app.route('/health')
def health():
    return jsonify({'status': 'OK'})


@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route('/')
def index():
    return render_template('index.html', config=load_config())


@app.route('/edit')
def edit():
    return render_template('edit.html', config=load_config())


@app.route('/api/config', methods=['GET'])
def get_config():
    return jsonify(load_config())


@app.route('/api/config', methods=['POST'])
def post_config():
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or 'site' not in data or 'sections' not in data:
        abort(400)
    save_config(data)
    return jsonify({'status': 'ok'})


@app.route('/api/history')
def get_history():
    if not CHROME_HISTORY.exists():
        return jsonify({'error': 'Chrome history file not found'}), 404

    tmp = Path('/tmp/_homepage_history.db')
    shutil.copy2(CHROME_HISTORY, tmp)

    try:
        con = sqlite3.connect(str(tmp))
        rows = con.execute("""
            SELECT url, title, visit_count
            FROM urls
            WHERE visit_count > 0
              AND url NOT LIKE 'chrome://%'
              AND url NOT LIKE 'chrome-extension://%'
              AND url NOT LIKE 'about:%'
            ORDER BY visit_count DESC
        """).fetchall()
        con.close()
    finally:
        tmp.unlink(missing_ok=True)

    buckets = defaultdict(lambda: {'visits': 0, 'title': '', 'url': ''})
    for url, title, count in rows:
        parsed = urlparse(url)
        host = parsed.netloc.lower()
        if host.startswith('www.'):
            host = host[4:]
        if not host:
            continue
        buckets[host]['visits'] += count
        if not buckets[host]['url']:
            buckets[host]['title'] = title or host
            buckets[host]['url'] = parsed.scheme + '://' + parsed.netloc

    top = sorted(buckets.items(), key=lambda x: x[1]['visits'], reverse=True)[:100]

    return jsonify([
        {'domain': d, 'visits': info['visits'], 'title': info['title'], 'url': info['url']}
        for d, info in top
    ])
