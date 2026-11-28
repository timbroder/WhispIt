#!/usr/bin/env python3
"""Turns bake-off output into the markdown tables in docs/qa/asr-bakeoff.md.

    Scripts/asr-bakeoff-table.py run-*.log > table.md

Reads every `BAKEOFF_RESULT {json}` line in the given files (xcodebuild logs
from WhispItIntegrationTests/Bakeoff, or Scripts/asr-bakeoff-mac output).
"""
import json
import sys


def results(paths):
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                marker = line.find("BAKEOFF_RESULT ")
                if marker >= 0:
                    yield json.loads(line[marker + len("BAKEOFF_RESULT "):])


def pct(value):
    return f"{value * 100:.1f}%"


def latency(result, fixture):
    run = next((r for r in result["latency"] if r["fixture"] == fixture), None)
    return f"{run['medianMs'] / 1000:.2f} s" if run else "–"


def silence(result):
    plain, biased = result["silenceText"], result["silenceBiasedText"]
    if not plain and not biased:
        return "clean"
    return f"“{plain}” / “{biased}”"


def main(paths):
    rows = list(results(paths))
    if not rows:
        sys.exit("no BAKEOFF_RESULT lines found")
    print(f"Host: {rows[0]['host']}\n")
    print("| Engine | WER (all speech) | Proper nouns plain → biased | Rare names plain → biased | "
          "Decoy “twist” kept | Dictionary leaks | Silence | Stop→text 6 s clip | Stop→text 41 s clip | "
          "Peak app memory | Model on disk | Cold load | Relaunch load |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        disk = f"{r['diskMB']:.0f} MB" if r.get("diskMB") is not None else "system-managed"
        peak = max(r["peakDuringLoadMB"], r["peakDuringTranscriptionMB"])
        leaks = ", ".join(r["vocabularyLeaks"]) or "none"
        relaunch = r.get("relaunchLoadSeconds")
        decoy = "yes" if r.get("decoyKeptBiased") else "**no**"
        print(f"| {r['engine']} | {pct(r['overallWER'])} | {r['properNounsPlain']}/3 → {r['properNounsBiased']}/3 | "
              f"{r.get('namesPlain', 0)}/5 → {r.get('namesBiased', 0)}/5 | {decoy} | "
              f"{leaks} | {silence(r)} | {latency(r, 'fillers')} | {latency(r, 'long-passage')} | "
              f"{peak:.0f} MB | {disk} | {r['downloadAndLoadSeconds']:.1f} s | "
              f"{f'{relaunch:.1f} s' if relaunch is not None else '–'} |")
    print("\nPer-fixture WER and transcripts:\n")
    for r in rows:
        print(f"- **{r['engine']}**")
        for run in r["accuracy"]:
            print(f"  - {run['fixture']}: {pct(run['wer'])} ({run['errors']}/{run['referenceWords']}) — “{run['text']}”")
        print(f"  - proper nouns with dictionary: “{r['properNounsBiasedText']}”")
        print(f"  - names without / with dictionary: “{r.get('namesPlainText', '')}” / “{r.get('namesBiasedText', '')}”")


if __name__ == "__main__":
    main(sys.argv[1:])
