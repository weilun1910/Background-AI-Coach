"""Turns downloaded survey responses into two CSV files.

Usage: export_responses.py <raw folder> <survey.json> <out folder> <name>

<name>-responses.csv has one row per tester, with a column per question.
<name>-picks.csv has one row per card pick, for counting what people chose.
"""

import csv
import json
import pathlib
import sys


def main():
    raw, survey_path, out, name = sys.argv[1:5]
    questions = json.load(open(survey_path, encoding="utf-8"))["questions"]
    responses = sorted(
        (json.load(open(path, encoding="utf-8")) for path in pathlib.Path(raw).glob("*.json")),
        key=lambda r: r.get("receivedAt", ""),
    )

    ids = [q["id"] for q in questions]
    extra = sorted({k for r in responses for k in r.get("answers", {})} - set(ids))
    with open(pathlib.Path(out) / f"{name}-responses.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["receivedAt", "students", "picks"] + ids + extra)
        for r in responses:
            answers = r.get("answers", {})
            picks = "; ".join(f"{p.get('student')}: {p.get('moment')} -> {p.get('picked')}" for p in r.get("picks", []))
            row = [r.get("receivedAt"), ", ".join(r.get("students", [])), picks]
            for key in ids + extra:
                value = answers.get(key)
                row.append("; ".join(value) if isinstance(value, list) else ("" if value is None else value))
            writer.writerow(row)

    with open(pathlib.Path(out) / f"{name}-picks.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["receivedAt", "student", "moment", "card", "picked", "demo"])
        for r in responses:
            for p in r.get("picks", []):
                writer.writerow([r.get("receivedAt"), p.get("student"), p.get("moment"), p.get("card"), p.get("picked"), p.get("demo")])

    print(f"{len(responses)} responses, {sum(len(r.get('picks', [])) for r in responses)} card picks -> {out}")


if __name__ == "__main__":
    main()
