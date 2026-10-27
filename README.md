# Background AI Coach

My solution prototype for the ENAS 3110 Solution / Design milestone, for AI-forward, non-technical Yale students getting ready for internships and jobs.

It's a Mac app that lives in the menu bar and notices the moments where an AI tool would actually help, like a coffee chat in 15 minutes, a mock interview tomorrow or a deadline tonight. If you don't have a good tool for that moment, it suggests one and walks you through setting it up. If you already own one and haven't been using it, it shows you how in about a minute. If you're already covered, it stays quiet.


## How it works

The app runs the same loop every time something happens on your Mac.

1. First it notices a moment. It reads the titles and times of your calendar events and notices which app is in front. Apple's on-device model reads each event title and decides what kind of moment it is, such as a coffee chat, an interview, an exam or a presentation. Going back and forth to the same app counts too, so switching to Figma four times in 15 minutes is a design moment.
2. Then it checks what you already have. Tools are grouped into eight areas, like AI meeting notes, interview practice and study prep. For each area the app works out whether you have nothing, own a tool you haven't opened in 30 days, or already use something. It can see your installed apps and your Claude Code setup. Websites and features inside other apps can't be seen from the Mac, so you tick those during onboarding.
3. If the area is empty, it suggests the tool that fits best. If you own something you haven't been using, it coaches you on that instead of selling you something new. If you're covered, or you've said "not for me", it does nothing.
4. Timing matters as much as the suggestion. By default you get at most one card a day, and nothing pops up while you're paused or while Zoom, Teams or FaceTime is the app in front. A held card waits in the menu bar and shows up at the next calm moment.
5. The card explains why this tool, what it costs, what it can see, and any consent note, like asking before you record someone. "Set it up" installs the app through Homebrew where it can, adds MCP servers to Claude Code, or opens the right page with a short checklist. A quick walkthrough for that exact moment comes after.
6. Finally, it keeps a small log on your Mac of every card shown, accepted, dismissed, or followed by you reopening the tool within a week.

None of this leaves your Mac. Event titles are read by Apple's model on the device, or by keyword rules on Macs without it, and nothing about you is uploaded.

The list of tools is a catalog of 29 tools across the eight areas, written by hand in `Resources/catalog.json`. In the full design a shared service would refresh that list every day. Here it's picked by hand, and its prices, plans and links were checked against vendor pages on Oct 15, 2026.

The system diagram is on the [FigJam board](https://www.figma.com/board/DanmId5kR63iVwQ1qfaFuu). This prototype covers the "Student Mac" half of it.

## Install and try it

You need a Mac with macOS 14 or later and Xcode's command-line tools (`xcode-select --install`). To have Apple's model read event titles, you also need an M1 or later Mac on macOS 26 or later with Apple Intelligence turned on. Without it the app uses keyword rules, which work but miss more.

Get the code and build the app:

```bash
git clone https://github.com/weilun1910/Background-AI-Coach.git
cd Background-AI-Coach
./scripts/build-app.sh
```

The build goes to `~/Library/Developer/Background AI Coach` on your Mac. There are four ways to run it.

| Command | What you get |
| --- | --- |
| `./scripts/run-stage.sh` | The full-screen demo with five pretend students. This is the one to show people. |
| `./scripts/run-demo.sh` | The real app in demo mode. It starts at onboarding, pretends your Mac is fresh, and never installs anything. |
| `./scripts/run.sh` | The real app on your real Mac. "Install it for me" really runs Homebrew. |
| `./scripts/run-personas.sh` | The five pretend students with a presenter window on the left, without taking over the screen. |

In demo and real mode, click the sparkle icon in the menu bar. "Try a moment" runs a sample event, like a coffee chat in 15 minutes, through the whole app, including Apple's model. In real mode you'll be asked to allow calendar access the first time. Settings has a button that opens the app's data folder.

## How the demo works

`./scripts/run-stage.sh` turns your screen into a made-up student's Mac. It has their wallpaper, their menu bar and clock, a dock with their apps, and real-looking windows for apps like Word, Zoom, Figma, ChatGPT and Calendar. The app deciding what to show is the real one. Only the student's apps, calendar and clock are pretend.

Click the screen once so it has focus, then use the keyboard.

| Key | What it does |
| --- | --- |
| Right arrow or space | Next step |
| Left arrow | Back one step |
| 1 to 5 | Switch student |
| R | Restart the day |
| N | Show or hide the presenter notes at the bottom |
| H | Show or hide the key hints |
| Esc | Switch between full screen and a window |
| Cmd+Q | Quit |

Each moment in a student's day plays in a few steps. Their desktop appears with whatever they're working on. A calendar notification slides in. Then the app's card appears in the corner, and a cursor clicks through setup or "Show me how" until the tool opens on their desktop. When the app stays quiet or holds a card, the cursor opens the menu-bar menu to show what it noticed and why. The notes at the bottom say what to point out at each step.

The five students each show a different part of the product.

| Student | Who they are | What their day shows |
| --- | --- | --- |
| Maya | Econ junior recruiting for consulting, uses ChatGPT's free plan | Granola suggested before a coffee chat, the one-card-a-day limit holding two later cards, and the held interview card showing up the next morning |
| Theo | Architecture sophomore who does most of his thinking in Claude | Coaching on Figma Make and Claude Projects before anything new, and "Not for me" sticking for the rest of the day |
| Ines | Sociology senior who's careful about privacy | Four quiet moments in a row, then one card all day for Big Interview, which Yale's career office gives students free |
| Dev | Cognitive Science junior with tools he never opens | Coaching on Grammarly, Cursor and Gemini that he already has, with no new installs |
| Grace | First-year with nothing set up | Nothing popping up during a Zoom call, and only one card on a day full of gaps |

The students are made up. Each one mixes patterns from several of our user interviews and doesn't stand for any one person. Their days are in `Resources/personas.json`.

## What it does today

- Reads calendar event titles and times through macOS Calendar, and turns them into moments with Apple's on-device model or keyword rules.
- Notices repeated switching to Figma, Canva, coding tools, Keynote, PowerPoint, Word, Pages and Preview.
- Checks installed apps and when they were last opened, Claude Code MCP servers, and the `claude` and `codex` command-line tools.
- Suggests, coaches or stays quiet for each of the eight areas, respecting free-only, "not for me" and your main AI app.
- Shows at most one card a day by default, holds cards during calls and pauses, and brings back cards you pushed to "Later".
- Installs apps with Homebrew, adds the Figma MCP server to Claude Code, or opens the right page, then shows a short walkthrough.
- Keeps a log of what happened to each card, and notices when you reopen a tool within a week of setting it up.
- Has onboarding, settings, a pause button and a coverage view in the menu bar.
- Ships three demos: the full-screen student demo, a side-window version of it, and a demo mode of the real app.

## Limitations

- The catalog is hand-made. The daily service that would gather, test and score new tools isn't built, so the 29 tools were picked and scored by hand. Their facts were checked once, on Oct 15, 2026, and prices and plans will drift. One thing couldn't be confirmed: whether Claude's Learning style is still available to regular accounts.
- The app only sees calendars that are added to macOS Calendar. A Google or Outlook calendar has to be added in System Settings first.
- Websites and features inside other apps, like ChatGPT study mode, only count if you tick them in onboarding. "Unused" relies on when macOS last saw an app opened, which can be wrong.
- App-switching detection watches a short list of apps and counts switches. By design it doesn't read window titles or the screen.
- Apple's model needs an M1 or later Mac with Apple Intelligence on. Other Macs fall back to keyword rules, which miss titles like "Coffee w/ Yale alum at BCG". Apple's model sometimes misreads a title too, so a few clear keywords like "interview" override it.
- Tools that need you to sign in, like claude.ai connectors or a Google account, still need you to do that part yourself. In real mode, "Install it for me" really installs apps through Homebrew.
- It doesn't learn yet. The log stays on your Mac. Sharing results to improve the scores, and suggesting you remove tools you never use, are designed but not built.
- It isn't signed or notarized for sharing as a download, so each person builds it from source on their own Mac.
- It has been tested on one Mac, an M4 Pro on macOS 27. A self-test checks the decision flow, and every step of the demos was played through and checked as images.
- In the demos, the decisions are made live by the real app, but the students, their apps and their calendars are made up.

## For developers

The code is a Swift package in `Sources/Recommender`. The main pieces are:

| File | What it does |
| --- | --- |
| `Sensing.swift` | Calendar and active-app sensing, and the inventory of what's installed |
| `MomentDetector.swift` | Apple's on-device model and the keyword rules |
| `GapEngine.swift` | The suggest, coach or stay quiet decision for each area |
| `AppModel.swift` | Scheduling, card actions and the log |
| `PanelViews.swift`, `MenuView.swift`, `OnboardingView.swift`, `SettingsViews.swift` | The card, menu, onboarding and settings |
| `Personas.swift`, `PersonaViews.swift` | The pretend students and the side-window demo |
| `StageDirector.swift`, `StageView.swift`, `StageWindows.swift` | The full-screen demo |

There are four testing flags. Run them with `RECOMMENDER_DATA_DIR` set to a scratch folder so your real settings aren't touched.

- `--selftest` prints what the app sees on your Mac, how Apple's model reads 19 sample titles, and what it would decide for each sample moment. It then clicks through the card flow in code and checks 18 things.
- `--persona-test` plays every student's day and prints each decision.
- `--stage-test --render <folder>` plays the full-screen demo and saves every step as an image.
- `--snapshot <folder>` saves every screen of the real app as an image, in light and dark mode.

For example:

```bash
RECOMMENDER_DATA_DIR="$TMPDIR/coach-test" "$HOME/Library/Developer/Background AI Coach/Background AI Coach.app/Contents/MacOS/Recommender" --selftest
```

Build files stay out of the repo, in `~/Library/Developer/Background AI Coach`. Set `RECOMMENDER_BUILD_DIR` to use another folder.
