# Background AI Coach

**This is a proof of concept.** It's an early test build of the idea. The code is rough and isn't meant to be installed. The best way to see it is the live demo:

### [Try the demo: background-ai-coach.vercel.app](https://background-ai-coach.vercel.app)

Background AI Coach is a Mac app that lives in the menu bar and notices the moments where an AI tool would actually help, like a coffee chat in 15 minutes, a mock interview tomorrow or a deadline tonight. If you don't have a good tool for that moment, it suggests one and sets it up for you. If you already own one and haven't been using it, it shows you how in about a minute. If you're already covered, it stays quiet.

It's designed for college students who are curious about AI but aren't technical, and who are getting ready for internships and jobs.

## The demo

The demo plays a day on a made-up student's Mac. You pick the student most like you and step through their day. Each time the app shows a card, you choose what you'd do: set it up, "Later" or "Not for me". After two students there's a short survey.

Each student shows a different part of the product.

| Student | Who they are | What their day shows |
| --- | --- | --- |
| Maya | Econ junior recruiting for consulting, uses ChatGPT's free plan | Granola suggested before a coffee chat, the one-card-a-day limit holding two later cards, and the held interview card showing up the next morning |
| Theo | Architecture sophomore who does most of his thinking in Claude | Coaching on tools inside Claude before anything new: Figma's connector for Claude, Claude Projects and Claude Slides. Then "Not for me" sticking for the rest of the day |
| Ines | Sociology senior who's careful about privacy | Four quiet moments in a row, then one card all day for Big Interview, which Yale's career office gives students free |
| Dev | Cognitive Science junior with tools he never opens | Coaching on Grammarly, Cursor and Gemini that he already has, with no new installs |
| Grace | First-year with nothing set up | Nothing popping up during a Zoom call, and only one card on a day full of gaps |

The students are made up. Each one mixes patterns from several of our user interviews. The decisions in the demo come from the real app logic. Only the students, their apps and their calendars are pretend.

## The problem

New AI tools and features come out every week. For a student who isn't technical, it's hard to tell which ones are worth learning, and guessing wrong costs time they don't have. These are the pain points that kept coming up in our interviews.

- There's too much to keep up with. Students told us the hard part is knowing what's out there and which of it is actually good. So they either ignore tools that would help them or spend hours on ones that go nowhere.
- Hearing about a tool doesn't get anyone to use it. People try something new when it clearly fits a task they're doing right now. Separate tutorials feel like homework, so they get skipped.
- Setup gets in the way. Finding the right tool, signing up, installing it and configuring it all land right before the thing they needed it for. Many students also told us they won't download another app or pay for another subscription.
- They already own tools they don't use. A feature inside ChatGPT or Claude, or an app they installed once, sits there because nobody showed them when to reach for it.
- A bad first try sends them back to doing it by hand. If the first attempt takes more effort than the manual way, they give up on the tool.
- They don't want something watching them. Privacy came up again and again, from not wanting to give an AI access to their files to distrusting apps that ask for too much.
- It matters for getting hired. We heard that employers increasingly expect candidates to explain how they've actually used AI, and knowing a tool exists doesn't count as experience.

## What it does

Students shouldn't have to go looking for the right tool. The app brings it to them at the moment they need it and handles the setup. It runs the same loop every time something happens on the Mac.

1. It notices a moment. It reads the titles and times of your calendar events, and Apple's on-device model decides what kind of moment each one is, like a coffee chat, an interview, an exam or a presentation. Going back and forth to the same app counts too, so switching to Figma four times in 15 minutes is a design moment.
2. It checks what you already have. Tools are grouped into eight areas: AI meeting notes, interview practice, reading and research, study and exam prep, slide drafting, writing feedback, design and AI coding. For each area it works out whether you have nothing, own something you haven't opened in 30 days, or already use something.
3. It decides. If the area is empty, it suggests the tool that fits best. If you own something you haven't been using, it coaches you on that before selling you anything new. If you're covered, or you've said "not for me", it does nothing.
4. It picks the right time. By default you get at most one card a day, and nothing pops up during a call or while you've paused it. A held card waits in the menu bar until the next calm moment.
5. It shows a card that explains why this tool, what it costs, what it can see, and any consent note, like asking before you record someone.
6. It sets the tool up for you, then walks you through using it for that exact moment.
7. It keeps a small log on your Mac of what happened to each card, including whether you came back to the tool within a week.

## Why it works this way

Each design choice answers one of the pain points above.

- It shows up at the moment of need, so the tool is tied to something you're about to do. That's when people are actually willing to try something new.
- It coaches you on what you already own before suggesting anything new. A lot of students already have the right tool and just never learned when to use it, and many won't add another app.
- It does the setup and gives you a walkthrough for that exact task, so the first try goes well and doesn't push you back to doing it by hand.
- It stays quiet most of the time. One card a day, nothing during calls, and "Not for me" sticks. If it interrupted all the time, people would turn it off.
- Everything personal stays on your Mac. Event titles are read by Apple's on-device model, and every card says what the tool can see. Nothing about you is uploaded.

## Planned system architecture

The full system diagram is on the [FigJam board](https://www.figma.com/board/DanmId5kR63iVwQ1qfaFuu/Product-System-Diagram?node-id=0-1&t=M3LBlZ7thfZx55GX-1). The full design has three parts.

1. The student's Mac. This is where everything personal lives. It notices moments, checks which tools you have, decides whether to suggest, coach or stay quiet, shows the card, runs the setup and keeps the log. None of that data leaves the Mac.
2. A shared catalog service in the cloud. Once a day it gathers new AI tools and features from launch feeds, product changelogs and vendor pages. It pulls out facts like price and permissions, tests each tool hands-on, scores how well it fits each kind of moment, and writes the setup steps. A person reviews the result before it goes out. Every Mac downloads the same public catalog, so the service never needs to know anything about you.
3. An opt-in feedback loop. If you allow it, your Mac sends back only which tool was suggested, whether you set it up and whether you came back to it within a week. No calendar, files or content. That helps the catalog score tools better for everyone.

The design also leaves room for an optional private cloud model for harder decisions. It would run in a sealed environment that keeps no logs and that we can't read.

## What the proof of concept covers

- It builds the Mac half of the design. The daily catalog service isn't built yet. In its place is a hand-picked catalog of 31 tools across the eight areas, with prices, plans and links checked against vendor pages on Oct 15, 2026. Some of those will have changed since.
- The feedback loop and the private cloud model are designed but not built.
- It has been tested on one Mac. It isn't signed or notarized, so it isn't set up for anyone else to install. The demo is the way to try it.
- A next version that also notices how you work, if you turn it on, is in progress on the `screen-aware` branch. It reads the title of the window you're in and takes an occasional look at the window itself, all on your Mac, then suggests better ways to use apps you already have.
