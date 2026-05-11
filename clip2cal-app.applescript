-- clip2cal: クリップボードのテキストから予定を抽出してカレンダーに登録
-- 使い方: 予定を含むテキストをコピーした後にこのアプリを起動

set clipText to the clipboard as text

if clipText is "" then
	display dialog "クリップボードが空です。" & return & return & "予定を含むテキストをコピーしてから起動してください。" buttons {"OK"} default button "OK" with icon caution with title "clip2cal"
	return
end if

-- install.sh がビルド時に実際のパスを埋め込みます
set scriptPath to "INSTALL_DIR/clip2cal-service.sh"

try
	do shell script "export PATH=/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH; echo " & quoted form of clipText & " | " & quoted form of scriptPath
on error errMsg number errNum
	if errNum is not -128 then
		display dialog "エラー: " & errMsg buttons {"OK"} default button "OK" with icon caution with title "clip2cal"
	end if
end try
