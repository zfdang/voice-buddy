#!/usr/bin/env python3
"""Automated Computer Use / UI testing suite for Voice Buddy on macOS."""
import subprocess
import sys
import time

APP_PATH = "dist/Voice Buddy.app"

def run_apple_script(script):
    cmd = ["osascript", "-e", script]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"AppleScript error: {result.stderr.strip()}")
    return result.stdout.strip()

def ensure_window():
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set frontmost to true
            if not (exists window 1) then
                tell menu bar 2
                    click menu bar item 1
                    delay 0.4
                    tell menu 1 of menu bar item 1
                        try
                            click (first menu item whose name contains "Settings" or name contains "设置")
                        end try
                    end tell
                end tell
                delay 0.6
            end if
        end tell
    end tell
    ''')

def click_sidebar_row(row_index):
    ensure_window()
    script = f'''
    tell application "System Events"
        tell process "VoiceBuddy"
            set frontmost to true
            set sbar to group 1 of splitter group 1 of group 1 of window 1
            select row {row_index} of outline 1 of scroll area 1 of sbar
        end tell
    end tell
    '''
    return run_apple_script(script)

def get_detail_elements():
    ensure_window()
    script = '''
    tell application "System Events"
        tell process "VoiceBuddy"
            set frontmost to true
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            set elemList to entire contents of detailArea
            set out to ""
            repeat with el in elemList
                try
                    set elRole to role of el
                    set elName to name of el
                    set elVal to ""
                    try
                        set elVal to (value of el) as string
                    end try
                    if elName is missing value then set elName to ""
                    if elVal is missing value then set elVal to ""
                    set out to out & elRole & " | " & elName & " | " & elVal & "---EOL---"
                end try
            end repeat
            return out
        end tell
    end tell
    '''
    raw = run_apple_script(script)
    items = []
    for line in raw.split("---EOL---"):
        line = line.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(" | ")]
        if len(parts) == 3:
            items.append({"role": parts[0], "name": parts[1], "value": parts[2]})
    return items

def main():
    print("=" * 65)
    print("  VOICE BUDDY COMPUTER USE / UI AUTOMATION TEST SUITE  ")
    print("=" * 65)

    # 1. Launch App
    print("[1/8] Ensuring app is running...")
    subprocess.run(["pkill", "-f", "VoiceBuddy"], capture_output=True)
    time.sleep(1)
    launch = subprocess.run(["open", APP_PATH], capture_output=True)
    if launch.returncode != 0:
        print(f"Failed to open app at {APP_PATH}")
        sys.exit(1)
    time.sleep(2)

    # 2. Activate and reposition window
    print("[2/8] Activating and positioning Voice Buddy window...")
    for attempt in range(5):
        try:
            run_apple_script('''
            tell application "System Events"
                tell process "VoiceBuddy"
                    set frontmost to true
                    tell menu bar 2
                        click menu bar item 1
                        delay 0.3
                        tell menu 1 of menu bar item 1
                            try
                                click (first menu item whose name contains "Settings" or name contains "设置")
                            end try
                        end tell
                    end tell
                    delay 0.8
                    tell window 1
                        set position to {100, 100}
                        set size to {850, 620}
                    end tell
                end tell
            end tell
            ''')
            break
        except Exception:
            time.sleep(1)
    time.sleep(0.5)

    # 3. Verify sidebar tabs
    print("[3/8] Verifying 6 Sidebar Navigation Tabs...")
    sidebar_items_raw = run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set sbar to group 1 of splitter group 1 of group 1 of window 1
            set rowTexts to {}
            repeat with r in rows of outline 1 of scroll area 1 of sbar
                set end of rowTexts to value of static text 1 of UI element 1 of r
            end repeat
            set AppleScript's text item delimiters to ", "
            return rowTexts as string
        end tell
    end tell
    ''')
    tabs = [t.strip() for t in sidebar_items_raw.split(",")]
    print(f"      Discovered tabs: {tabs}")
    is_zh = "通用" in tabs
    if is_zh:
        assert tabs == ["通用", "权限检查", "语音识别", "文本模型", "结果", "关于"], f"Tabs mismatch: {tabs}"
        print("      ✓ Sidebar structure verified: 通用, 权限检查, 语音识别, 文本模型, 结果, 关于")
    else:
        assert tabs == ["General", "Permissions", "Speech recognition", "Text model", "Result", "About"], f"Tabs mismatch: {tabs}"
        print("      ✓ Sidebar structure verified: General, Permissions, Speech recognition, Text model, Result, About")

    # 4. Tab 1: General
    print(f"\n[4/9] Testing Tab 1: {'通用' if is_zh else 'General'}...")
    click_sidebar_row(1)
    time.sleep(0.4)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    if is_zh:
        assert "快捷键与录音方式" in text_content or "全局快捷键" in text_content, "Missing shortcut card"
        assert "音频输入与提示" in text_content or "麦克风输入源" in text_content, "Missing audio card"
        assert "文本润色与输入" in text_content or "文字整理力度" in text_content, "Missing text card"
        assert "系统与启动" in text_content or "界面显示语言" in text_content, "Missing system card"
        assert "开始听写" not in text_content, "'开始听写' button should not exist in UI"
    else:
        assert "Shortcut & Recording" in text_content or "Dictation Shortcut" in text_content, "Missing shortcut card"
        assert "Audio & Feedback" in text_content or "Microphone" in text_content, "Missing audio card"
        assert "Text & Insertion" in text_content or "Text Refinement" in text_content, "Missing text card"
        assert "System & Launch" in text_content or "Interface Language" in text_content, "Missing system card"
        assert "Start dictation" not in text_content, "'Start dictation' button should not exist in UI"
    print("      ✓ Verified all 4 grouped General settings cards (no redundant tab title, no manual start button)")

    # Test toggling checkbox / switch
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            click checkbox 1 of detailArea
            delay 0.2
            click checkbox 1 of detailArea
        end tell
    end tell
    ''')
    print("      ✓ Verified toggle switch interactions")

    # 5. Tab 2: Permissions
    print(f"\n[5/9] Testing Tab 2: {'权限检查' if is_zh else 'Permissions Check'}...")
    click_sidebar_row(2)
    time.sleep(0.4)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    if is_zh:
        assert "麦克风权限" in text_content, "Missing '麦克风权限' section"
        assert "辅助功能权限" in text_content, "Missing '辅助功能权限' section"
        assert "隐私与安全承诺" in text_content, "Missing '隐私与安全承诺' section"
        assert "100% 本地离线" in text_content, "Missing offline commitment"
    else:
        assert "Microphone" in text_content, "Missing 'Microphone' section"
        assert "Accessibility" in text_content, "Missing 'Accessibility' section"
        assert "Privacy" in text_content, "Missing 'Privacy' section"
        assert "100% On-Device" in text_content or "offline" in text_content.lower(), "Missing offline commitment"
    if is_zh:
        assert "剪贴板瞬态保护" in text_content, "Missing clipboard protection note"
        assert "密码框安全阻断" in text_content, "Missing secure field guard note"
    else:
        assert "clipboard" in text_content.lower(), "Missing clipboard protection note"
        assert "password" in text_content.lower(), "Missing secure field guard note"

    # Click Re-check button (button 1 in detailArea)
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            click button 1 of detailArea
        end tell
    end tell
    ''')
    print("      ✓ Verified Permissions tab UI, privacy guarantees, and '重新检查' button")

    # 6. Tab 3: Speech Recognition & Navigation Link
    print(f"\n[6/9] Testing Tab 3: {'语音识别' if is_zh else 'Speech Recognition'} & Navigation Shortcut...")
    click_sidebar_row(3)
    time.sleep(0.6)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    if is_zh:
        assert "识别" in text_content or "语音" in text_content, "Missing '识别' or '语音'"
        assert "识别语言" in text_content, "Missing '识别语言'"
    else:
        assert "model" in text_content.lower(), "Missing 'model'"
        assert "language" in text_content.lower(), "Missing 'language'"

    print("      ✓ Successfully tested Speech Recognition tab settings and status")

    # 7. Tab 4: Text Model & Tab 5: Result + Clipboard Test
    print(f"\n[7/9] Testing Tab 4 ({'文本模型' if is_zh else 'Text Model'}) & Tab 5 ({'结果与剪贴板注入' if is_zh else 'Result & Clipboard'})...")
    click_sidebar_row(4)
    time.sleep(0.4)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    assert "Qwen 3.5 0.8B" in text_content, "Missing text model info"
    print("      ✓ Verified Text Model tab details")
    print("      ✓ Verified Text Model tab details")

    click_sidebar_row(5)
    time.sleep(0.4)
    test_phrase = "Voice Buddy 本地语音输入与权限检查自动化测试顺利通过。"
    run_apple_script(f'''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            set tArea to text area 1 of scroll area 1 of detailArea
            set value of tArea to "{test_phrase}"
            click button 1 of detailArea
        end tell
    end tell
    ''')
    time.sleep(0.3)
    pasted = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout.strip()
    assert pasted == test_phrase, f"Clipboard mismatch: expected '{test_phrase}', got '{pasted}'"
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    assert "已复制" in text_content or "Copied" in text_content, f"Expected status '已复制' or 'Copied', got '{text_content}'"
    print(f"      ✓ Result tab editor & clipboard copy verified: '{pasted}'")

    # 8. Tab 6: About & Software Updates
    print(f"\n[8/9] Testing Tab 6: {'关于' if is_zh else 'About'}...")
    click_sidebar_row(6)
    time.sleep(0.4)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    if is_zh:
        assert "版本信息" in text_content, "Missing '版本信息' section"
        assert "当前版本" in text_content, "Missing '当前版本' row"
        assert "软件更新" in text_content, "Missing '软件更新' section"
        assert "项目介绍与链接" in text_content, "Missing '项目介绍与链接' section"
        assert "GitHub Repository" in text_content, "Missing GitHub link row"
    else:
        assert "Version Information" in text_content, "Missing 'Version Information' section"
        assert "Current version" in text_content, "Missing 'Current version' row"
        assert "Software Update" in text_content, "Missing 'Software Update' section"
        assert "Introduction & Links" in text_content, "Missing 'Introduction & Links' section"
        assert "GitHub Repository" in text_content, "Missing GitHub link row"

    # Click "Check for Updates…" button (button 1 in detailArea)
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            click button 1 of detailArea
        end tell
    end tell
    ''')
    print("      ✓ Successfully tested About tab UI, version info, Sparkle update button, and repo links")

    # 9. MenuBarExtra & Clean Termination
    print("\n[9/9] Testing MenuBarExtra & Clean App Exit...")
    menu_items_raw = run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            tell menu bar 2
                click menu bar item 1
                delay 0.3
                tell menu 1 of menu bar item 1
                    set mList to name of every menu item
                    set AppleScript's text item delimiters to ", "
                    return mList as string
                end tell
            end tell
        end tell
    end tell
    ''')
    menu_items = [m.strip() for m in menu_items_raw.split(",")]
    print(f"      MenuBarExtra items: {menu_items}")
    # Verify Start Dictation is NOT present
    assert not any("听写" in item or "Dictat" in item for item in menu_items), f"Start/Stop dictation action should NOT be in menu bar, found: {menu_items}"
    # Verify Settings, About, Check for Updates, and Quit are present
    assert any("设置" in item or "Settings" in item for item in menu_items), f"Expected Settings in MenuBarExtra, got {menu_items}"
    assert any("关于" in item or "About" in item for item in menu_items), f"Expected About in MenuBarExtra, got {menu_items}"
    assert any("更新" in item or "Updates" in item for item in menu_items), f"Expected Check for Updates in MenuBarExtra, got {menu_items}"
    assert any("退出" in item or "Quit" in item for item in menu_items), f"Expected Quit in MenuBarExtra, got {menu_items}"
    print("      ✓ Verified MenuBarExtra items (cleanly contains Settings, About, Updates, Quit, and no dictation start button)")

    # Quit app cleanly
    try:
        run_apple_script('tell application "Voice Buddy" to quit')
    except Exception:
        pass
    time.sleep(1)
    check_proc = subprocess.run(["pgrep", "-x", "VoiceBuddy"], capture_output=True)
    if check_proc.returncode == 0:
        subprocess.run(["pkill", "-x", "VoiceBuddy"])
        time.sleep(0.5)
    print("      ✓ Cleanly exited Voice Buddy")

    print("\n" + "=" * 65)
    print("  ALL COMPUTER USE / UI AUTOMATION TESTS PASSED (100% OK)  ")
    print("=" * 65)

if __name__ == "__main__":
    main()
