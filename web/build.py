"""Turns the full-screen demo's beat list into the web walkthrough's data.

Usage: build.py <beats.txt> <personas.json> <captions.json> <out.json>

beats.txt is what `Recommender --stage-test --render <dir> --clean` prints.
Each beat there matches a rendered frame named <persona>-<nn>-<label>.png.
The walkthrough keeps the frames a tester needs, stops at every card to ask
what they'd do, and writes the list of frames it uses next to the JSON.
"""

import json
import re
import sys

BEAT = re.compile(r"^\s+(\d\d) (.+?)  \[windows: .*?\] \[card: (.*?)\](.*)$")
STARTS_STEP = {"scene", "leave call", "next morning"}
LEAD_BEATS = {"notification", "switching", "call"}
LOOK_TEXT = "The coach takes a look at the window, on the Mac. It keeps one short line about it and drops the picture."
SKIP = {"scene", "got it", "close the menu", "end"}


def read_beats(path, personas):
    """Returns {persona id: [(number, label, card), ...]} in the order printed."""
    ids_by_name = {p["name"]: p["id"] for p in personas}
    beats, current = {}, None
    for line in open(path, encoding="utf-8"):
        match = BEAT.match(line)
        header = line.split(": ", 1)[0]
        if match and current is not None:
            number, label, card, _ = match.groups()
            beats[current].append((int(number), label, card))
        elif header in ids_by_name:
            current = ids_by_name[header]
            beats[current] = []
    return beats


def clock(step):
    hour, minute = (int(part) for part in step["at"].split(":"))
    suffix = "AM" if hour < 12 else "PM"
    text = f"{(hour - 1) % 12 + 1}:{minute:02d} {suffix}"
    return f"Next day, {text}" if step.get("day", 0) or step["type"] == "nextMorning" else text


def moment_title(step, text):
    """How the end-of-day summary names the moment a card was for."""
    if "title" in text:
        return text["title"]
    if step["type"] == "appSwitch":
        return f"Switching to {step['title']}"
    return step.get("title") or text["lead"]


def frame_name(persona_id, number, label):
    return f"{persona_id}-{number:02d}-{label.replace(' ', '-')}.jpg"


def slides_for(persona, beats, captions):
    steps, slides = persona["steps"], []
    step_index = -1
    lead_used = set()
    for number, label, card in beats:
        if label in STARTS_STEP:
            step_index += 1
        step = steps[step_index]
        text = captions[step_index]
        frame = frame_name(persona["id"], number, label)
        base = {"frame": frame, "time": clock(step), "step": step_index}
        kind, _, tool = card.partition(" ")

        if label in SKIP:
            continue
        if label in LEAD_BEATS:
            lead_used.add(step_index)
            slides.append({**base, "type": "view", "text": text["lead"]})
        elif label == "glimpse":
            # Screen steps: the lead goes on the first slide of the step.
            first = step_index not in lead_used
            lead_used.add(step_index)
            look = text.get("look", LOOK_TEXT)
            slides.append({**base, "type": "view", "text": f"{text['lead']} {look}" if first else look})
        elif kind in ("suggest", "coach", "tip") and label in ("react", "leave call", "next morning"):
            slides.append({
                **base,
                "type": "choice",
                "zoom": "card",
                "lead": text["lead"] if label != "react" else "",
                "card": {"kind": kind, "tool": tool},
                "title": moment_title(step, text),
                "scripted": "never" if step.get("click") == "notForMe" else "accept",
            })
        elif label == "react":
            continue
        elif label == "click Set it up":
            slides.append({**base, "type": "view", "zoom": "card", "text": f"Setting up {tool}."})
        elif label == "run setup":
            slides.append({**base, "type": "view", "zoom": "card", "text": "It does the steps it can on its own and lists the ones you'd do yourself."})
        elif label == "finish setup":
            slides.append({**base, "type": "view", "zoom": "card", "text": "Done. Then a one-minute rundown for this exact moment."})
        elif label == "click Show me how":
            slides.append({**base, "type": "view", "zoom": "card", "text": f"A one-minute rundown of {tool} for this moment."})
        elif label == "click Show me":
            slides.append({**base, "type": "view", "zoom": "card", "text": f"The steps, and a prompt for {tool} that's already filled in."})
        elif label == "copy prompt":
            slides.append({**base, "type": "view", "zoom": "card", "text": "Copy prompt puts it on the clipboard, ready to paste. The details in it, like the company, were filled in on the Mac."})
        elif label == "open the menu":
            slides.append({**base, "type": "view", "zoom": "menu", "text": text["outcome"]})
        elif label in ("click Not for me", "open the tool"):
            slides.append({**base, "type": "view", "text": text["outcome"]})
        else:
            raise SystemExit(f"{persona['id']} beat {number}: no rule for '{label}'")
    return slides


def main():
    beats_path, personas_path, captions_path, out_path = sys.argv[1:5]
    personas = json.load(open(personas_path, encoding="utf-8"))["personas"]
    captions = json.load(open(captions_path, encoding="utf-8"))
    beats = read_beats(beats_path, personas)

    walkthrough, frames = [], []
    for persona in personas:
        if len(captions[persona["id"]]) != len(persona["steps"]):
            raise SystemExit(f"captions.json has the wrong number of steps for {persona['id']}")
        slides = slides_for(persona, beats[persona["id"]], captions[persona["id"]])
        frames += [s["frame"] for s in slides]
        walkthrough.append({
            "id": persona["id"],
            "name": persona["name"],
            "tagline": persona["tagline"],
            "about": persona["about"],
            "slides": slides,
        })

    with open(out_path, "w", encoding="utf-8") as out:
        json.dump({"personas": walkthrough}, out, indent=1, ensure_ascii=False)
    with open(out_path.rsplit("/", 1)[0] + "/frames.txt", "w", encoding="utf-8") as out:
        out.write("\n".join(frames) + "\n")
    print(f"{sum(len(p['slides']) for p in walkthrough)} slides, {len(frames)} frames")


if __name__ == "__main__":
    main()
