import json
import shutil
import sqlite3
from collections import defaultdict
from pathlib import Path
from urllib.parse import urlparse

from flask import Flask, abort, jsonify, render_template, request

app = Flask(__name__)
CONFIG_PATH = Path(__file__).parent.parent / 'config.json'
CHROME_HISTORY = Path.home() / '.config/google-chrome/Default/History'


def load_config():
    with open(CONFIG_PATH, encoding='utf-8') as f:
        return json.load(f)


def save_config(data):
    with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


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
