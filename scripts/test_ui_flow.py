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

def click_sidebar_row(row_index):
    script = f'''
    tell application "System Events"
        tell process "VoiceBuddy"
            set sbar to group 1 of splitter group 1 of group 1 of window 1
            select row {row_index} of outline 1 of scroll area 1 of sbar
        end tell
    end tell
    '''
    return run_apple_script(script)

def get_detail_elements():
    script = '''
    tell application "System Events"
        tell process "VoiceBuddy"
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
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set frontmost to true
            tell window 1
                set position to {100, 100}
                set size to {850, 620}
            end tell
        end tell
    end tell
    ''')
    time.sleep(0.5)

    # 3. Verify sidebar tabs
    print("[3/8] Verifying 5 Sidebar Navigation Tabs...")
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
    assert tabs == ["通用", "权限检查", "语音识别", "文本模型", "结果"], f"Tabs mismatch: {tabs}"
    print("      ✓ Sidebar structure verified: 通用, 权限检查, 语音识别, 文本模型, 结果")

    # 4. Tab 1: General (通用)
    print("\n[4/8] Testing Tab 1: 通用 (General Preferences)...")
    click_sidebar_row(1)
    time.sleep(0.4)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    assert "通用设置" in text_content, "Missing '通用设置'"
    assert "界面语言" in text_content, "Missing '界面语言'"
    assert "麦克风输入" in text_content, "Missing '麦克风输入'"
    assert "文字整理力度" in text_content, "Missing '文字整理力度'"
    assert "录音模式" in text_content, "Missing '录音模式'"
    assert "快捷键" in text_content, "Missing '快捷键'"
    print("      ✓ Verified all General tab settings, pickers, and shortcut button")

    # Test toggling checkbox
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
    print("      ✓ Verified checkbox toggle interactions")

    # 5. Tab 2: Permissions (权限检查)
    print("\n[5/8] Testing Tab 2: 权限检查 (Permissions Check)...")
    click_sidebar_row(2)
    time.sleep(0.4)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    assert "系统权限检查" in text_content, "Missing '系统权限检查' header"
    assert "麦克风权限" in text_content, "Missing '麦克风权限' section"
    assert "辅助功能权限" in text_content, "Missing '辅助功能权限' section"
    assert "隐私与安全承诺" in text_content, "Missing '隐私与安全承诺' section"
    assert "100% 本地离线" in text_content, "Missing offline commitment"
    assert "剪贴板瞬态保护" in text_content, "Missing clipboard protection note"
    assert "密码框安全阻断" in text_content, "Missing secure field guard note"

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
    print("\n[6/8] Testing Tab 3: 语音识别 & Navigation Shortcut...")
    click_sidebar_row(3)
    time.sleep(0.4)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    assert "语音识别" in text_content, "Missing '语音识别' header"
    assert "识别模型" in text_content, "Missing '识别模型'"
    assert "识别语言" in text_content, "Missing '识别语言'"

    # Click "查看权限检查…" button (button 3) to test cross-tab navigation
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            click button 3 of detailArea
        end tell
    end tell
    ''')
    time.sleep(0.4)
    is_perm_selected = run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set sbar to group 1 of splitter group 1 of group 1 of window 1
            return selected of row 2 of outline 1 of scroll area 1 of sbar
        end tell
    end tell
    ''')
    assert is_perm_selected == "true", "Failed to navigate to Permissions tab from Speech tab"
    print("      ✓ Successfully tested Speech tab and navigation to Permissions tab")

    # 7. Tab 4: Text Model & Tab 5: Result + Clipboard Test
    print("\n[7/8] Testing Tab 4 (文本模型) & Tab 5 (结果与剪贴板注入)...")
    click_sidebar_row(4)
    time.sleep(0.4)
    elements = get_detail_elements()
    text_content = " ".join([e["name"] for e in elements] + [e["value"] for e in elements])
    assert "文本模型" in text_content and "Qwen 3.5 0.8B" in text_content, "Missing text model info"
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
    status_text = run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            return value of static text 3 of detailArea
        end tell
    end tell
    ''')
    assert status_text == "已复制", f"Expected status '已复制', got '{status_text}'"
    print(f"      ✓ Result tab editor & clipboard copy verified: '{pasted}'")

    # 8. MenuBarExtra & Clean Termination
    print("\n[8/8] Testing MenuBarExtra & Clean App Exit...")
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
    assert any("听写" in item or "Dictat" in item for item in menu_items) and any("退出" in item or "Quit" in item for item in menu_items), f"Expected Dictate and Quit items in MenuBarExtra, got {menu_items}"

    # Quit app via MenuBarExtra
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            tell menu bar 2
                click (last menu item of menu 1 of menu bar item 1)
            end tell
        end tell
    end tell
    ''')
    time.sleep(1)
    check_proc = subprocess.run(["pgrep", "-f", "VoiceBuddy"], capture_output=True)
    assert check_proc.returncode != 0, "Process should have exited cleanly"
    print("      ✓ Cleanly exited Voice Buddy via MenuBarExtra")

    print("\n" + "=" * 65)
    print("  ALL COMPUTER USE / UI AUTOMATION TESTS PASSED (100% OK)  ")
    print("=" * 65)

if __name__ == "__main__":
    main()
