#!/bin/bash
# mail2cal-service.sh — Automatorクイックアクションから呼ばれる版
# 標準入力またはクリップボードからメール本文を受け取り、予定を抽出して.icsを生成

set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

# 標準入力からテキストを読む（Automatorが選択テキストを渡す）
EMAIL_DATA=$(cat)

# 選択テキストが空ならクリップボードにフォールバック
if [ -z "$EMAIL_DATA" ]; then
    EMAIL_DATA=$(pbpaste)
fi

if [ -z "$EMAIL_DATA" ]; then
    osascript -e 'display dialog "メールのテキストが取得できませんでした。\nメール本文を選択してから再実行してください。" buttons {"OK"} default button "OK" with icon caution with title "mail2cal"'
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

JSON=$(echo "$EMAIL_DATA" | python3 "$SCRIPT_DIR/mail2cal-extract.py")

FOUND=$(echo "$JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('found', False))")

# 予定が見つからなかった場合は仮データで1件作る（メール本文をdescriptionに）
if [ "$FOUND" != "True" ]; then
    TODAY=$(date +%Y-%m-%d)
    JSON=$(python3 -c "
import json, sys
desc = sys.stdin.read()
print(json.dumps({'found': True, 'events': [{'title': '予定', 'start_date': '${TODAY}', 'start_time': '09:00', 'end_date': '${TODAY}', 'end_time': '10:00', 'location': '', 'description': desc}]}, ensure_ascii=False))
" <<< "$EMAIL_DATA")
    osascript -e 'display notification "予定情報を自動検出できませんでした。手動で入力してください。" with title "mail2cal"'
fi

# 抽出結果をイベントごとに確認・編集（1画面にまとめる）
EDITED_JSON=$(echo "$JSON" | python3 -c "
import sys, json, subprocess, re

data = json.load(sys.stdin)
edited_events = []

for i, ev in enumerate(data['events'], 1):
    loc = ev.get('location', '')
    default_text = f'イベント名: {ev[\"title\"]}\n開始: {ev[\"start_date\"]} {ev[\"start_time\"]}\n終了: {ev[\"end_date\"]} {ev[\"end_time\"]}\n場所: {loc}'

    prompt_msg = f'予定 [{i}/{len(data[\"events\"])}] を確認・編集してください:'

    script = f'''display dialog \"{prompt_msg}\" default answer \"{default_text}\" buttons {{\"スキップ\", \"登録\"}} default button \"登録\" with title \"mail2cal\"'''

    result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
    if result.returncode != 0:
        continue
    output = result.stdout.strip()
    if '登録' not in output:
        continue

    text = output.split('text returned:')[-1].strip() if 'text returned:' in output else ''
    if not text:
        continue

    # 各行をパース
    fields = {}
    for line in text.split(chr(10)):
        if ':' in line:
            key, val = line.split(':', 1)
            fields[key.strip()] = val.strip()
        elif '：' in line:
            key, val = line.split('：', 1)
            fields[key.strip()] = val.strip()

    ev['title'] = fields.get('イベント名', ev['title'])
    ev['location'] = fields.get('場所', ev.get('location', ''))

    start = fields.get('開始', f'{ev[\"start_date\"]} {ev[\"start_time\"]}')
    end = fields.get('終了', f'{ev[\"end_date\"]} {ev[\"end_time\"]}')

    # 日時パース (YYYY-MM-DD HH:MM)
    sm = re.match(r'(\d{4}-\d{2}-\d{2})\s+(\d{1,2}:\d{2})', start)
    if sm:
        ev['start_date'] = sm.group(1)
        ev['start_time'] = sm.group(2)
    em = re.match(r'(\d{4}-\d{2}-\d{2})\s+(\d{1,2}:\d{2})', end)
    if em:
        ev['end_date'] = em.group(1)
        ev['end_time'] = em.group(2)

    edited_events.append(ev)

data['events'] = edited_events
data['found'] = len(edited_events) > 0
print(json.dumps(data, ensure_ascii=False))
")

FOUND=$(echo "$EDITED_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('events',[])) > 0)")
if [ "$FOUND" != "True" ]; then
    exit 0
fi
JSON="$EDITED_JSON"

# .icsファイルを生成してOutlookで開く
ICS_DIR=$(mktemp -d)

echo "$JSON" | python3 -c "
import sys, json, os, subprocess, uuid

script_dir = os.path.dirname(os.path.abspath('$SCRIPT_DIR/mail2cal-config.json'))
config_path = os.path.join('$SCRIPT_DIR', 'mail2cal-config.json')
tz = 'Asia/Tokyo'
if os.path.exists(config_path):
    with open(config_path) as cf:
        tz = json.load(cf).get('timezone', tz)

data = json.load(sys.stdin)
ics_dir = '$ICS_DIR'

for i, ev in enumerate(data['events']):
    sd = ev['start_date'].replace('-', '')
    st = ev['start_time'].replace(':', '')
    ed = ev['end_date'].replace('-', '')
    et = ev['end_time'].replace(':', '')
    uid = str(uuid.uuid4())

    title = ev['title'].replace(',', '\\\\,').replace(';', '\\\\;')
    location = ev.get('location', '').replace(',', '\\\\,').replace(';', '\\\\;')
    description = ev.get('description', '').replace(',', '\\\\,').replace(';', '\\\\;').replace(chr(10), '\\\\n')

    ics = f'''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//mail2cal//EN
BEGIN:VEVENT
UID:{uid}
DTSTART;TZID={tz}:{sd}T{st}00
DTEND;TZID={tz}:{ed}T{et}00
SUMMARY:{title}
LOCATION:{location}
DESCRIPTION:{description}
END:VEVENT
END:VCALENDAR'''

    path = os.path.join(ics_dir, f'event_{i}.ics')
    with open(path, 'w') as f:
        f.write(ics)

    subprocess.run(['open', path])
"

osascript -e 'display dialog "カレンダーイベントを開きました。\nOutlookで「保存」を押して登録してください。" buttons {"OK"} default button "OK" with icon note with title "mail2cal"'
