#!/bin/bash
# clip2cal インストールスクリプト
# cloneしたディレクトリで実行してください

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "clip2cal をインストールします"
echo "ソースディレクトリ: $SCRIPT_DIR"
echo ""

# 実行権限を付与
chmod +x "$SCRIPT_DIR/clip2cal-service.sh" "$SCRIPT_DIR/clip2cal.sh" "$SCRIPT_DIR/clip2cal-extract.py"

# 設定ファイルがなければサンプルからコピー
if [ ! -f "$SCRIPT_DIR/clip2cal-config.json" ]; then
    cp "$SCRIPT_DIR/clip2cal-config.json.example" "$SCRIPT_DIR/clip2cal-config.json"
    echo "設定ファイルを作成しました: clip2cal-config.json"
    echo "必要に応じて時限表などを編集してください。"
    echo ""
fi

# AppleScriptにこのディレクトリのパスを埋め込んでビルド
APPLESCRIPT_CONTENT="-- clip2cal: クリップボードのテキストから予定を抽出してカレンダーに登録
-- 使い方: 予定を含むテキストをコピーした後にこのアプリを起動

set clipText to the clipboard as text

if clipText is \"\" then
	display dialog \"クリップボードが空です。\" & return & return & \"予定を含むテキストをコピーしてから起動してください。\" buttons {\"OK\"} default button \"OK\" with icon caution with title \"clip2cal\"
	return
end if

set scriptPath to \"$SCRIPT_DIR/clip2cal-service.sh\"

try
	do shell script \"export PATH=/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:\$PATH; echo \" & quoted form of clipText & \" | \" & quoted form of scriptPath
on error errMsg number errNum
	if errNum is not -128 then
		display dialog \"エラー: \" & errMsg buttons {\"OK\"} default button \"OK\" with icon caution with title \"clip2cal\"
	end if
end try"

mkdir -p ~/Applications
echo "$APPLESCRIPT_CONTENT" | osacompile -o ~/Applications/clip2cal.app

echo "インストール完了!"
echo ""
echo "使い方:"
echo "  1. 予定を含むテキストをコピー (Cmd+C)"
echo "  2. Cmd+Space →「clip2cal」→ Enter"
echo ""
echo "ターミナルからも使えます:"
echo "  $SCRIPT_DIR/clip2cal.sh"
