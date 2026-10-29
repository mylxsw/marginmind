// Generates a local Chinese PDF for the side-by-side native acceptance fixture.
// swift example/compare_fixture.swift /tmp/marginmind-compare-zh.pdf
import AppKit
import PDFKit

final class ReadingPage: NSView {
    let number: Int
    let english: Bool
    init(number: Int, english: Bool = false) {
        self.number = number
        self.english = english
        super.init(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
    }
    required init?(coder: NSCoder) { fatalError("Programmatic fixture") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 23, weight: .semibold), .foregroundColor: NSColor.black]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black]
        ((english ? "Learning and Memory" : "学习与记忆") as NSString).draw(at: NSPoint(x: 100, y: 100), withAttributes: heading)
        let sections = [
            ["学习如何发生", "学习不是简单地储存信息。理解新的概念，", "需要把它与已有知识联系起来。", "主动回忆帮助我们发现理解中的空白。", "把一个概念讲给别人听，也是一种检验。", "", "长期记忆与练习", "与其把所有练习集中在同一天，", "不如在几天之后重新回顾这些内容。", "每次努力回想，都在加强记忆。", "", "阅读时可以划线、摘录，并记下想法。"],
            ["检索练习", "合上书本，尝试用自己的话概括这一节。", "遇到想不起来的地方，再回到原文核对。", "通过比较原文与译文，可以澄清概念。", "", "迁移与应用", "理解的标志，是能把知识用于新的情境。", "为一个观点找例子，也找一个反例。", "在脑图里整理这些观点之间的联系。"],
            ["间隔重复", "安排下一次回顾，让记忆在时间中巩固。", "学习计划应该允许调整与反馈。", "", "反思", "哪些想法改变了原来的理解？", "哪些问题值得继续研究？", "把这些问题记在页边，稍后再回来。"]
        ]
        let englishSections = [
            ["How learning happens", "Learning connects new ideas to prior knowledge.", "Explaining a concept reveals gaps in understanding.", "Active recall helps us discover what is missing.", "Try to describe the idea in your own words.", "", "Long-term memory and practice", "Spread practice over several days instead of one.", "Each attempt to recall strengthens the memory.", "Make highlights, excerpts, and notes as you read."],
            ["Retrieval practice", "Close the book and summarize the main ideas.", "Return to the text to check what you could not recall.", "Compare the original with a translation to clarify terms.", "", "Transfer and application", "Apply knowledge to a situation you have not seen before.", "Find an example and a counterexample for a claim.", "Organize the relationships between ideas in a mind map."],
            ["Spaced repetition", "Schedule the next review so memory grows over time.", "Allow the learning plan to change with feedback.", "", "Reflection", "Which ideas have changed your understanding?", "Which questions deserve further study?", "Write those questions in the margin and return later."]
        ]
        let lines = english ? englishSections[number - 1] : sections[number - 1]
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 100, y: 170 + i * 29), withAttributes: body)
        }
        ("\(number)" as NSString).draw(at: NSPoint(x: 300, y: 720), withAttributes: body)
    }
}
let document = PDFDocument()
for number in 1...3 {
    let view = ReadingPage(number: number)
    guard let page = PDFDocument(data: view.dataWithPDF(inside: view.bounds))?.page(at: 0) else { fatalError("PDF rendering failed") }
    document.insert(page, at: document.pageCount)
}
let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/marginmind-compare-zh.pdf"
guard document.write(toFile: destination) else { fatalError("PDF write failed") }
print("COMPARE_FIXTURE_OK pages=\(document.pageCount)")

if CommandLine.arguments.count > 2 {
    let original = PDFDocument()
    for number in 1...3 {
        let view = ReadingPage(number: number, english: true)
        guard let page = PDFDocument(data: view.dataWithPDF(inside: view.bounds))?.page(at: 0) else { fatalError("PDF rendering failed") }
        original.insert(page, at: original.pageCount)
    }
    guard original.write(toFile: CommandLine.arguments[2]) else { fatalError("PDF write failed") }
    print("COMPARE_ENGLISH_OK pages=\(original.pageCount)")
}
