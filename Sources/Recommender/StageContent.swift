import Foundation

/// Made-up text for the pretend apps' windows.
enum StageContent {
    static func document(_ key: String?) -> (title: String, paragraphs: [String]) {
        switch key {
        case "coverBain":
            return ("Cover letter: Bain & Company, Associate Consultant Intern", [
                "Dear Bain Recruiting Team,",
                "I'm a junior at Yale studying Economics, and I'm applying for the Associate Consultant Intern role in Boston. Last summer I helped a regional grocery chain rethink its weekly pricing, and I found I loved the part where the numbers turn into a decision someone can act on.",
                "At Yale I lead the market research team in the Yale Undergraduate Consulting Group. This fall we sized a campus coffee subscription for a local business and recommended a smaller launch than they had planned.",
                "I'd love to bring that same habit of asking what would change the decision to Bain's case teams.",
            ])
        case "coverJaneStreet":
            return ("Cover letter: Jane Street, Trading Intern", [
                "Dear Jane Street team,",
                "I'm a junior in Cognitive Science with a strong interest in how people make decisions under uncertainty. I am very interested in the trading internship and I think I would be a great fit.",
                "In my lab I build small experiments on how people update their guesses when new information arrives, and I analyze the results in Python.",
                "I am passionate about learning and I work well in teams.",
            ])
        case "thesis":
            return ("Chapter 3: Mutual aid networks after the 2020 lockdowns", [
                "Between March and June 2020, at least 41 mutual aid groups formed in New Haven, most of them organized through group chats and shared spreadsheets rather than formal nonprofits.",
                "This chapter follows three of those groups through their first year. It asks why two of them dissolved within months while the third became a standing tenants' association.",
                "Drawing on 22 interviews and the groups' own records, I argue that the difference lay less in resources than in how each group handled the first disagreement over who should get help.",
            ])
        case "coverMcKinsey":
            return ("Cover letter: McKinsey & Company, Business Analyst Intern", [
                "Dear McKinsey Recruiting Team,",
                "I'm a junior at Yale studying Political Science, and I'm applying for the Business Analyst internship. I've spent two summers working on housing policy, first at a city council office and then at a tenants' rights nonprofit.",
                "At the nonprofit I helped analyze eviction filings across four neighborhoods and presented the findings to the board, which changed where it sent its two staff lawyers.",
                "I want to learn how to break messy problems into pieces a client can act on, and I think McKinsey's public sector practice is where I'd learn that fastest.",
            ])
        case "fellowship":
            return ("Personal statement: Fulbright research grant", [
                "When I started interviewing organizers in New Haven, I expected to study resources. I ended up studying trust.",
                "This year in Lisbon I want to ask the same question of neighborhood associations that formed during the city's housing crisis.",
            ])
        case "essay":
            return ("ENGL 114: What counts as a home?", [
                "My grandmother has lived in four countries and calls none of them home. She uses the word for her kitchen instead.",
                "This essay asks whether a home is a place, a set of habits, or the people who notice when you're gone.",
            ])
        default:
            return ("Untitled", ["Start typing here."])
        }
    }

    static let readingParagraphs = [
        "This week's readings take up the same question from three directions: how much of what we call a style is a set of rules, and how much is a habit nobody wrote down.",
        "The first reading argues that design follows from a small number of principles stated in advance. The second answers that most of those principles were written after the buildings, to explain choices that had already been made.",
        "The third reading is a field study. It follows a studio through one semester and counts how often students cite a rule versus a precedent when defending a decision.",
    ]

    /// What the student pastes into their AI app for a tip: the prompt, plus what it asked for.
    static func tipMessage(_ workflow: String, prompt: String) -> String {
        switch workflow {
        case "coffee-chat-questions":
            return prompt.replacingOccurrences(of: "[paste it here]", with: "Engagement Manager, public sector practice. Yale College, Political Science. Before McKinsey, two years at a city budget office.")
        default:
            return prompt.replacingOccurrences(of: "[paste it here]", with: "...").replacingOccurrences(of: "[paste them here]", with: "...")
        }
    }

    static func chatReply(_ app: String, flag: String?) -> [String] {
        if flag == "shuttle" {
            return ["Here's a more confident version: \"At the nonprofit, I analyzed eviction filings across four neighborhoods and presented findings that changed where the board sent its lawyers.\""]
        }
        if flag == "tip:feedback-in-one-go" {
            return [
                "1. \"I've spent two summers working on housing policy\" says where you were, not what you did. What's one decision your work changed?",
                "2. \"I think McKinsey's public sector practice is where I'd learn that fastest\" could be in anyone's letter. What did you hear from someone there that made you want it?",
                "3. The eviction analysis is your strongest line. What did the board do differently because of it?",
            ]
        }
        if flag == "tip:coffee-chat-questions" {
            return [
                "1. What made you move from a city budget office to consulting, and what did you miss about the public side?",
                "2. How did you get staffed on your first public sector cases, and what would you do differently in your first year?",
                "3. When a client is a city government, who actually owns the decision at the end of a project?",
            ]
        }
        if flag == "tip:posting-check" {
            return [
                "1. Problem solving with data: shown. \"I helped analyze eviction filings across four neighborhoods.\"",
                "2. Working with clients or stakeholders: missing. When did you have to change someone's mind with your findings?",
                "3. Leadership: missing. Have you led a team or a project, even a small one?",
            ]
        }
        if flag == "guided" {
            return ["Let's start with what you already know. In one sentence, what's the difference between working memory and long-term memory?"]
        }
        if flag?.hasPrefix("connector:") == true {
            return [
                "Board 2 has three blocks: two side by side and a long bar below them. The two on top use your Massing / Block component, but the bar is detached from it.",
                "The bar also sits 40 px below the others while your spacing variable is 24 px, so it reads as a separate building. Snap it to the component and the grid and the three will read as one scheme.",
            ]
        }
        switch app {
        case "claude":
            return [
                "Reading 1 argues that good design follows a few principles you can state ahead of time. It leans on the passage about \"the plan as generator\".",
                "Reading 2 pushes back. It says most principles are written afterwards to justify choices already made, citing the studio records in section 3.",
            ]
        case "gemini":
            return ["Here's a quick overview to get you started, then we'll practice."]
        default:
            return ["Sure. Tell me the role first, and I'll ask one question at a time."]
        }
    }

    static func codeLines(agent: Bool) -> [[(String, CodeTone)]] {
        [
            [("import", .keyword), (" pandas ", .plain), ("as", .keyword), (" pd", .plain)],
            [("import", .keyword), (" numpy ", .plain), ("as", .keyword), (" np", .plain)],
            [],
            [("# Load the reaction-time data from the lab study", .comment)],
            [("df", .plain), (" = ", .plain), ("pd", .plain), (".read_csv(", .plain), ("\"data/rt_trials.csv\"", .string), (")", .plain)],
            [("df", .plain), (" = ", .plain), ("df", .plain), ("[", .plain), ("df", .plain), ("[", .plain), ("\"rt\"", .string), ("] < ", .plain), ("2000", .number), ("]", .plain)],
            [],
            [("def", .keyword), (" summarize", .function), ("(group):", .plain)],
            [("    return", .keyword), (" group", .plain), ("[", .plain), ("\"rt\"", .string), ("].agg([", .plain), ("\"mean\"", .string), (", ", .plain), ("\"std\"", .string), ("])", .plain)],
            [],
            [("by_condition", .plain), (" = ", .plain), ("df", .plain), (".groupby(", .plain), ("\"condition\"", .string), (").apply(", .plain), ("summarize", .function), (")", .plain)],
            [("print", .function), ("(by_condition)", .plain)],
        ] + (agent ? [[], [("# Agent: moved loading into load_trials() and added a docstring", .comment)]] : [])
    }
}

enum CodeTone {
    case plain, keyword, string, comment, number, function
}
