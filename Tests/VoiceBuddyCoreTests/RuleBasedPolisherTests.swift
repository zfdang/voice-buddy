import XCTest
import ChineseITN
@testable import VoiceBuddyCore

final class RuleBasedPolisherTests: XCTestCase {
    
    func testChineseHesitationsAndFillers() {
        // 拟声词与逗号消除
        XCTAssertEqual(RuleBasedPolisher.polish("嗯，今天天气真好"), "今天天气真好")
        XCTAssertEqual(RuleBasedPolisher.polish("呃，你好"), "你好")
        XCTAssertEqual(RuleBasedPolisher.polish("啊啊，原来是这样"), "原来是这样")
        
        // 标点锚定的口头禅（带逗号删除，句中实词保护）
        XCTAssertEqual(RuleBasedPolisher.polish("那个，请把报表发给我"), "请把报表发给我")
        XCTAssertEqual(RuleBasedPolisher.polish("请把那个报表发给我"), "请把那个报表发给我")
        XCTAssertEqual(RuleBasedPolisher.polish("就是说，这件事我们可以下周再讨论"), "这件事我们可以下周再讨论")
        XCTAssertEqual(RuleBasedPolisher.polish("怎么说呢，感觉还可以"), "感觉还可以")
    }
    
    func testStutterDeduplicationAndMeaningfulWordsPreserved() {
        // Issue 3: 避免无间隔重叠误伤成语/固定搭配
        XCTAssertEqual(RuleBasedPolisher.polish("这是是非非的问题"), "这是是非非的问题")
        
        // Issue 3: 避免跨分句逗号误伤代词造成语法篡改
        XCTAssertEqual(RuleBasedPolisher.polish("这个是我，我的朋友"), "这个是我，我的朋友")
        XCTAssertEqual(RuleBasedPolisher.polish("你是我的一切，一切都在改变"), "你是我的一切，一切都在改变")
        
        // 真正的代词与连词口吃应当正常去重
        XCTAssertEqual(RuleBasedPolisher.polish("我、我、我想去看看"), "我想去看看")
        XCTAssertEqual(RuleBasedPolisher.polish("我 我 我想去看看"), "我想去看看")
        XCTAssertEqual(RuleBasedPolisher.polish("因为、因为这个原因"), "因为这个原因")
        XCTAssertEqual(RuleBasedPolisher.polish("因为，因为这个原因"), "因为这个原因")
        XCTAssertEqual(RuleBasedPolisher.polish("然后 然后我们就出发了"), "然后我们就出发了")
        
        // 正常重叠动词不应误删
        XCTAssertEqual(RuleBasedPolisher.polish("讨论讨论这个方案"), "讨论讨论这个方案")
        XCTAssertEqual(RuleBasedPolisher.polish("考虑考虑"), "考虑考虑")
    }
    
    func testRepeatedDigitsAndProlongedSoundPreserved() {
        // Issue 1: 中文重复数字编号不得被机械卡顿规则压缩破坏
        XCTAssertEqual(RuleBasedPolisher.polish("这是一一一二三号"), "这是一一一二三号")
        XCTAssertEqual(TextCleanup.light("这是一一一二三号"), "这是11123号")
        
        // Issue 1: 日文长音符ー不得被压缩
        XCTAssertEqual(RuleBasedPolisher.polish("ワーーーーイ"), "ワーーーーイ")
        
        // 热切回应与正常叠词保护
        XCTAssertEqual(RuleBasedPolisher.polish("好好好，没问题"), "好好好，没问题")
        XCTAssertEqual(RuleBasedPolisher.polish("对对对，就是这样"), "对对对，就是这样")
        XCTAssertEqual(RuleBasedPolisher.polish("行行行，我马上办"), "行行行，我马上办")
        XCTAssertEqual(RuleBasedPolisher.polish("哈哈哈哈太搞笑了"), "哈哈哈哈太搞笑了")
        
        // 真正的机械无意义字符卡顿压缩
        XCTAssertEqual(RuleBasedPolisher.polish("等等等一下"), "等一下")
    }
    
    func testUrlAndEmailProtectedFromEnglishFillers() {
        // Issue 2: 英文 filler 清理绝不破坏 URL 和 Email 地址
        XCTAssertEqual(RuleBasedPolisher.polish("邮箱 um@example.com"), "邮箱 um@example.com")
        XCTAssertEqual(RuleBasedPolisher.polish("请访问 https://example.com/um 查看详情"), "请访问 https://example.com/um 查看详情")
        XCTAssertEqual(RuleBasedPolisher.polish("发送邮件至 uh_user@domain.com，谢谢"), "发送邮件至 uh_user@domain.com，谢谢")
        
        // 正常文本中的英文填充词依然被正确清除
        XCTAssertEqual(RuleBasedPolisher.polish("Um, send it, uh, tomorrow."), "send it, tomorrow.")
        XCTAssertEqual(RuleBasedPolisher.polish("I, I think we should go."), "I think we should go.")
        XCTAssertEqual(RuleBasedPolisher.polish("This is, you know, very important."), "This is, very important.")
    }
    
    func testParagraphBreaksPreserved() {
        // Issue 4: 段落换行与多行空白绝不被合并为单个空格
        let multiLine = "早上好\n\n下午见"
        XCTAssertEqual(RuleBasedPolisher.polish(multiLine), multiLine)
        
        let formattedList = "任务列表：\n1. 第一项\n2. 第二项"
        XCTAssertEqual(RuleBasedPolisher.polish(formattedList), formattedList)
    }
    
    func testEnglishAndJapaneseFillers() {
        // 日文填充词
        XCTAssertEqual(RuleBasedPolisher.polish("えーと、はじめまして"), "はじめまして")
        XCTAssertEqual(RuleBasedPolisher.polish("あのー、すみません"), "すみません")
    }
    
    func testPunctuationStitchingAndFallback() {
        // 连续逗号合并与句首标点清理
        XCTAssertEqual(RuleBasedPolisher.polish("，，今天开会"), "今天开会")
        XCTAssertEqual(RuleBasedPolisher.polish("讨论，，继续"), "讨论，继续")
        
        // 纯语气词兜底（不吞字）
        XCTAssertEqual(RuleBasedPolisher.polish("嗯"), "嗯")
        XCTAssertEqual(RuleBasedPolisher.polish("Uh..."), "Uh...")
    }
    
    func testTextCleanupLightWithITN() {
        // 验证两阶段流水线：去口癖 + ITN 数字/时间/百分比/单位归一化
        let input = "呃那个李经理，下周排期定在下午三点四十五分，大概需要百分之三十的时间"
        let output = TextCleanup.light(input)
        
        // 验证去除了口头禅，且“下午三点四十五分”转为“下午3:45”，“百分之三十”转为“30%”
        XCTAssertTrue(output.contains("3:45") || output.contains("3点45分"))
        XCTAssertTrue(output.contains("30%"))
        XCTAssertFalse(output.contains("呃那个"))
        
        // 成语保护验证（不可转换为数字）
        let idiomInput = "祝你一帆风顺，万无一失"
        XCTAssertEqual(TextCleanup.light(idiomInput), "祝你一帆风顺，万无一失")
    }
}
