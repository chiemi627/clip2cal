#!/bin/bash
# mail2cal.sh — メール本文から予定を抽出してOutlookカレンダーに登録する
# 使い方: メールの本文をコピー(Cmd+C)してから実行

set -euo pipefail

# 1. クリップボードからメール本文を取得
EMAIL_DATA=$(pbpaste)

if [ -z "$EMAIL_DATA" ]; then
    echo "エラー: クリップボードが空です。"
    echo "Outlookでメールを開き、本文を Cmd+A → Cmd+C でコピーしてから再実行してください。"
    exit 1
fi

echo "=== クリップボードの内容（先頭5行） ==="
echo "$EMAIL_DATA" | head -5
echo "..."
echo ""

# 2. 正規表現で予定情報を抽出
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "予定を抽出中..."
JSON=$(echo "$EMAIL_DATA" | python3 "$SCRIPT_DIR/mail2cal-extract.py")

FOUND=$(echo "$JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('found', False))")

if [ "$FOUND" != "True" ]; then
    echo "このメールには予定情報が見つかりませんでした。"
    exit 0
fi

# 3. 抽出した予定を表示して確認
EVENT_COUNT=$(echo "$JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('events',[])))")

echo ""
echo "=== 抽出された予定 ==="
echo "$JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for i, ev in enumerate(data['events'], 1):
    print(f\"  [{i}] {ev['title']}\")
    print(f\"      日時: {ev['start_date']} {ev['start_time']} 〜 {ev['end_date']} {ev['end_time']}\")
    if ev.get('location'):
        print(f\"      場所: {ev['location']}\")
    if ev.get('description'):
        print(f\"      備考: {ev['description']}\")
    print()
"

echo -n "カレンダーに登録しますか？ (y/n): "
read -r CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "キャンセルしました。"
    exit 0
fi

# 4. .icsファイルを生成してOutlookで開く
ICS_DIR=$(mktemp -d)

echo "$JSON" | python3 -c "
import sys, json, os, subprocess, uuid
from datetime import datetime

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
DTSTART;TZID=Asia/Tokyo:{sd}T{st}00
DTEND;TZID=Asia/Tokyo:{ed}T{et}00
SUMMARY:{title}
LOCATION:{location}
DESCRIPTION:{description}
END:VEVENT
END:VCALENDAR'''

    path = os.path.join(ics_dir, f'event_{i}.ics')
    with open(path, 'w') as f:
        f.write(ics)

    subprocess.run(['open', path])
    print(f'  → Outlookでインポートダイアログを開きました: {ev[\"title\"]}')
"

echo ""
echo ".icsファイルがOutlookで開かれます。「保存」を押してカレンダーに登録してください。"
echo "一時ファイル: $ICS_DIR"
