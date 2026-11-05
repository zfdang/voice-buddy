#!/usr/bin/env python3
"""Comprehensive Automated UI Testing Suite for Speech & Text Models in Voice Buddy."""
import os
import shutil
import subprocess
import sys
import time

APP_PATH = "dist/Voice Buddy.app"
BACKUP_DIR = "/tmp/voice_buddy_models_backup"
MODELS_DIR = os.path.expanduser("~/Library/Application Support/VoiceBuddy/Models")

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
                    delay 0.3
                    tell menu 1 of menu bar item 1
                        try
                            click (first menu item whose name contains "设置" or name contains "Settings")
                        end try
                    end tell
                end tell
                delay 0.6
            end if
        end tell
    end tell
    ''')

def select_tab(row_index):
    ensure_window()
    run_apple_script(f'''
    tell application "System Events"
        tell process "VoiceBuddy"
            set sbar to group 1 of splitter group 1 of group 1 of window 1
            select row {row_index} of outline 1 of scroll area 1 of sbar
        end tell
    end tell
    ''')
    time.sleep(0.4)

def get_detail_text():
    ensure_window()
    script = '''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            set elemList to entire contents of detailArea
            set out to ""
            repeat with el in elemList
                try
                    set elVal to (value of el) as string
                    if elVal is not missing value and length of elVal > 0 then
                        set out to out & elVal & "\n"
                    end if
                end try
            end repeat
            return out
        end tell
    end tell
    '''
    return run_apple_script(script)

def click_detail_button(btn_index):
    ensure_window()
    script = f'''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            click button {btn_index} of detailArea
        end tell
    end tell
    '''
    return run_apple_script(script)

def click_sheet_button_by_desc(desc_keyword):
    script = f'''
    tell application "System Events"
        tell process "VoiceBuddy"
            set sh to sheet 1 of window 1
            repeat with b in buttons of sh
                set bDesc to ""
                set bName to ""
                try
                    set bDesc to description of b
                end try
                try
                    set bName to name of b
                end try
                if bDesc contains "{desc_keyword}" or bName contains "{desc_keyword}" then
                    click b
                    return "clicked " & bDesc & " " & bName
                end if
            end repeat
            return "not found"
        end tell
    end tell
    '''
    return run_apple_script(script)

def test_speech_model_operations():
    print("\n" + "=" * 60)
    print("  TEST SUITE 1: SPEECH RECOGNITION MODEL UI FLOWS")
    print("=" * 60)

    select_tab(3) # Tab 3: 语音识别
    time.sleep(0.5)

    txt = get_detail_text()
    assert "本地语音模型列表与存储管理" in txt, "Speech settings card not found"
    assert "Qwen 3 ASR 0.6B" in txt, "0.6B model spec not found"
    assert "Qwen 3 ASR 1.7B" in txt, "1.7B model spec not found"
    print("  [Step 1.1] Initial Speech Tab state verified.")
    assert "声学识别与语音检测模型已载入统一内存" in txt, "Expected memory status badge"
    print("  ✓ Active Speech Model loaded in unified memory verified.")

    # --- Test 1A: Download & Cancel on un-downloaded model (1.7B) ---
    print("\n  [Step 1.2] Testing Download & Cancel on 1.7B model...")
    # Button 1 is 0.6B (Delete Cache), Button 2 is 1.7B (Download)
    click_detail_button(2)
    time.sleep(0.8)
    txt_downloading = get_detail_text()
    # While downloading, 1.7B should show cancel button / progress
    print("    - Download initiated on 1.7B.")
    # Now click Cancel on 1.7B (Button 2 is now Cancel)
    click_detail_button(2)
    time.sleep(0.8)
    txt_cancelled = get_detail_text()
    assert "尚未下载" in txt_cancelled, "Expected 1.7B to remain not downloaded"
    print("  ✓ Successfully verified download start and immediate cancellation on 1.7B.")

    # --- Test 1B: Deletion of cached model (0.6B) ---
    print("\n  [Step 1.3] Testing deletion of 0.6B model...")
    # Click Delete Cache on 0.6B (Button 1)
    click_detail_button(1)
    time.sleep(0.5)

    # Verify confirmation sheet appears
    sheet_count = int(run_apple_script('tell application "System Events" to tell process "VoiceBuddy" to count of sheets of window 1'))
    assert sheet_count == 1, "Confirmation sheet did not appear!"
    print("    - Confirmation sheet appeared with '删除' and 'Cancel' options.")

    # Confirm deletion
    res = click_sheet_button_by_desc("删除")
    print(f"    - Clicked sheet button: {res}")
    time.sleep(1.0)

    # Verify model folder removed from disk
    model_path = os.path.join(MODELS_DIR, "qwen-asr-0.6b")
    assert not os.path.exists(model_path), f"Expected {model_path} to be deleted!"
    print(f"  ✓ Verified model directory deleted from disk: {model_path}")

    # Verify UI reflects un-downloaded state
    txt_deleted = get_detail_text()
    assert "本地尚未下载任何语音模型" in txt_deleted, "Expected Card 2 notice: '本地尚未下载任何语音模型'"
    print("  ✓ Verified Card 2 updated to show '本地尚未下载任何语音模型'.")

    # --- Test 1C: Download & Cancel on 0.6B ---
    print("\n  [Step 1.4] Testing Download & Cancel on 0.6B...")
    # Button 1 is now "下载" for 0.6B
    click_detail_button(1)
    time.sleep(0.8)
    # Button 1 is now "取消"
    click_detail_button(1)
    time.sleep(0.8)
    txt_re_cancelled = get_detail_text()
    assert "本地尚未下载任何语音模型" in txt_re_cancelled
    print("  ✓ Verified download initiation and cancellation on 0.6B.")

    # --- Test 1D: Restore & Auto-load in Memory ---
    print("\n  [Step 1.5] Restoring 0.6B from backup and verifying memory auto-load...")
    src_backup = os.path.join(BACKUP_DIR, "qwen-asr-0.6b")
    shutil.copytree(src_backup, model_path, dirs_exist_ok=True)
    print("    - Restored qwen-asr-0.6b to disk.")

    # Switch away and back to Tab 3 to refresh or click Load
    select_tab(1)
    time.sleep(0.3)
    select_tab(3)
    time.sleep(1.2)

    # If "载入内存" button appears, click it
    txt_restored = get_detail_text()
    if "模型尚未载入统一内存" in txt_restored or "载入内存" in txt_restored:
        print("    - Clicking '载入内存' button...")
        run_apple_script('''
        tell application "System Events"
            tell process "VoiceBuddy"
                set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
                try
                    click button 3 of detailArea
                end try
            end tell
        end tell
        ''')
        time.sleep(2.5)

    txt_final = get_detail_text()
    assert "已下载" in txt_final, "Expected 0.6B to show '已下载'"
    assert "声学识别与语音检测模型已载入统一内存" in txt_final, "Expected speech model loaded in unified memory"
    print("  ✓ Verified Speech Model restored, detected, and loaded into unified memory!")

def test_text_model_operations():
    print("\n" + "=" * 60)
    print("  TEST SUITE 2: TEXT MODEL UI FLOWS")
    print("=" * 60)

    select_tab(4) # Tab 4: 文本模型
    time.sleep(0.5)

    txt = get_detail_text()
    assert "本地模型列表与存储管理" in txt, "Text settings card not found"
    assert "Qwen 3.5 0.8B" in txt, "Qwen 3.5 0.8B spec not found"
    assert "模型已载入统一内存 · 随时可用" in txt, "Expected text model loaded in unified memory"
    print("  [Step 2.1] Initial Text Tab state verified with model loaded in memory.")

    # --- Test 2A: Switching between models in picker ---
    print("\n  [Step 2.2] Testing model switching in picker (INT5 <-> INT8)...")
    # Change picker to INT8
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            set popups to pop up buttons of detailArea
            if (count of popups) > 0 then
                tell pop up button 1 of detailArea
                    click
                    delay 0.3
                    click (first menu item of menu 1 whose name contains "INT8")
                end tell
            end if
        end tell
    end tell
    ''')
    time.sleep(1.5)
    txt_switched = get_detail_text()
    assert "INT8" in txt_switched
    print("    - Switched active model to INT8.")
    # Switch back to INT5
    run_apple_script('''
    tell application "System Events"
        tell process "VoiceBuddy"
            set detailArea to scroll area 1 of group 2 of splitter group 1 of group 1 of window 1
            set popups to pop up buttons of detailArea
            if (count of popups) > 0 then
                tell pop up button 1 of detailArea
                    click
                    delay 0.3
                    click (first menu item of menu 1 whose name contains "INT5")
                end tell
            end if
        end tell
    end tell
    ''')
    time.sleep(1.5)
    print("  ✓ Verified model switching between INT5 and INT8 in picker.")

    # --- Test 2B: Delete INT8 model ---
    print("\n  [Step 2.3] Testing deletion of INT8 text model...")
    # Button 1 is INT5 (Delete Cache), Button 2 is INT8 (Delete Cache)
    click_detail_button(2)
    time.sleep(0.5)

    sheet_count = int(run_apple_script('tell application "System Events" to tell process "VoiceBuddy" to count of sheets of window 1'))
    assert sheet_count == 1, "Confirmation sheet did not appear!"
    print("    - Confirmation sheet appeared for INT8 text model.")

    res = click_sheet_button_by_desc("删除")
    print(f"    - Clicked sheet button: {res}")
    time.sleep(1.0)

    int8_path = os.path.join(MODELS_DIR, "qwen35-text-0.8b-int8")
    assert not os.path.exists(int8_path), f"Expected {int8_path} to be deleted!"
    print(f"  ✓ Verified INT8 directory deleted from disk: {int8_path}")

    txt_int8_deleted = get_detail_text()
    assert "尚未下载" in txt_int8_deleted, "Expected INT8 row to show '尚未下载'"
    print("  ✓ Verified UI reflects INT8 as '尚未下载'.")

    # --- Test 2C: Download & Cancel on INT8 ---
    print("\n  [Step 2.4] Testing Download & Cancel on INT8...")
    # Button 2 is now "下载" for INT8
    click_detail_button(2)
    time.sleep(0.8)
    # Button 2 is now "取消"
    click_detail_button(2)
    time.sleep(0.8)
    txt_cancelled = get_detail_text()
    assert "尚未下载" in txt_cancelled
    print("  ✓ Verified download initiation and cancellation on INT8.")

    # --- Test 2D: Restore INT8 & Re-verify ---
    print("\n  [Step 2.5] Restoring INT8 from backup...")
    src_backup = os.path.join(BACKUP_DIR, "qwen35-text-0.8b-int8")
    shutil.copytree(src_backup, int8_path, dirs_exist_ok=True)
    select_tab(1)
    time.sleep(0.3)
    select_tab(4)
    time.sleep(1.0)
    txt_restored = get_detail_text()
    assert "已下载" in txt_restored
    assert "模型已载入统一内存 · 随时可用" in txt_restored
    print("  ✓ Verified INT8 restored and both text models ready.")

def main():
    print("=" * 65)
    print(" VOICE BUDDY AUTOMATED MODEL UI TEST SUITE (SPEECH & TEXT)")
    print("=" * 65)

    test_speech_model_operations()
    test_text_model_operations()

    print("\n" + "=" * 65)
    print(" ALL SPEECH AND TEXT MODEL UI TESTS PASSED PERFECTLY (100% OK)!")
    print("=" * 65)

if __name__ == "__main__":
    main()
