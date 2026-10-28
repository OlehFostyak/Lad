#!/usr/bin/env python3
"""Builds Resources/Dictionaries/{uk,en}.tsv, the word lists Lad's language models use.

Run with `make dictionaries` (python3 -I). Sources are downloaded once into tools/.cache:

- FrequencyWords 2018 (OpenSubtitles) by Hermit Dave: uk_full.txt and en_50k.txt.
  Code MIT, word lists CC-BY-SA-4.0.
- VESUM (dict_uk by brown-uk) v6.8.6, dictionary data CC-BY-NC-SA-4.0 (its code is GPL-3.0):
  dict_corp_vis.txt.bz2. Only real Ukrainian word forms are kept (the subtitle list carries many
  Russian words), and it adds the apostrophe forms the subtitle tokenizer split apart.
- Ukrainian Wikipedia word counts (dump of 2022-08-30) from wikipedia-word-frequency by Ilya
  Semenov (code MIT; Wikipedia text CC-BY-SA): ukwiki-2022-08-30.txt. It adds the common words
  films rarely say (ківі, смартфон); the subtitle words keep their own counts.

Resources/Licenses.txt credits both sources and says what changed; keep it in step.

Output lines are `word<TAB>count`, most frequent first, after `#` header lines.
"""

import bz2
import hashlib
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
OUT = ROOT / "Resources" / "Dictionaries"

# Pinned: FrequencyWords at commit 525f9b5 (2022-02-07), VESUM at release v6.8.6, the Wikipedia
# counts at commit b49c2ea (2022-09-06). Every file is
# checked against its SHA-256, downloaded or cached, so a changed upstream fails loudly.
FREQUENCY_WORDS = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018"
SOURCES = {
    "uk_full.txt": (
        f"{FREQUENCY_WORDS}/uk/uk_full.txt",
        "bfa15b3512a41771ac8ecf47f5ef8314badb76f867fb9a6afbb409265b41709f",
    ),
    "en_50k.txt": (
        f"{FREQUENCY_WORDS}/en/en_50k.txt",
        "5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458",
    ),
    "dict_corp_vis.txt.bz2": (
        "https://github.com/brown-uk/dict_uk/releases/download/v6.8.6/dict_corp_vis.txt.bz2",
        "e33803783ac138e6f3af2cf0e9428ba146c0ecfda7f5c41fe83ae00c7af24be9",
    ),
    "ukwiki-2022-08-30.txt": (
        "https://raw.githubusercontent.com/IlyaSemenov/wikipedia-word-frequency/"
        "b49c2ea1554d87094959ba15a41b3f383795434d/results/ukwiki-2022-08-30.txt",
        "5bf9a83681d138a6db663b3d618e96e668a7e20a9c9d2812c39c7704d28cd784",
    ),
}

UK_LETTERS = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя"
UK_WORD = re.compile(f"^[{UK_LETTERS}]+(?:'[{UK_LETTERS}]+)*$")
EN_WORD = re.compile(r"^[a-z]+$")
APOSTROPHES = str.maketrans({"’": "'", "ʼ": "'", "`": "'"})

# Subtitle counts below this are mostly typos and noise.
UK_MIN_COUNT = 2
# VESUM forms that are only non-normative (bad), substandard (subst) or abbreviations are not words
# Lad should convert into.
VESUM_REJECT_TAGS = ("bad", "subst", "abbr")
# Counts are written as parts per billion of the subtitles' running text, so words that only
# Wikipedia has can be rarer than one subtitle use.
UK_SCALE = 1e9
# Wikipedia adds words it uses at least this often, with at least this many letters unless they
# have an apostrophe (its short tokens are mostly letters and symbols: «фі» is the Greek phi), at
# this share of its frequency (an encyclopedia's words are rarer in typing).
WIKI_MIN_COUNT = 50
WIKI_MIN_LETTERS = 4
WIKI_WEIGHT = 0.5
# Apostrophe forms that neither corpus has come from VESUM alone; they get the smallest count.
UK_APOSTROPHE_COUNT = 1

EN_SINGLE_LETTERS = {"a", "i"}
# The subtitle list has hundreds of two-letter tokens; most are noise (oj, ls, lt). Only real words
# (the Scrabble TWL two-letter list) and common abbreviations are kept.
EN_TWO_LETTER = set("""
    aa ab ad ae ag ah ai al am an ar as at aw ax ay ba be bi bo by da de do ed ef eh el em en er es
    et ex fa fe gi go ha he hi hm ho id if in is it jo ka ki la li lo ma me mi mm mo mu my na ne no
    nu od oe of oh oi ok om on op or os ow ox oy pa pe pi po qi re sh si so ta te ti to uh um un up
    us ut we wo xi xu ya ye yo za
    tv mr ms dr st jr pm uk eu pc dj hq iq ip vs pr
""".split())
# Three-letter tokens without a vowel are mostly abbreviations or noise (ghb, cnn), except these.
EN_VOWELS = set("aeiouy")
EN_THREE_LETTER_NO_VOWEL = {"hmm", "shh", "brr", "nth", "tsk", "pst", "mrs"}
# The subtitle tokenizer splits contractions ("don" + "'t"), so they are listed here. Each gets
# the count of the English word at EN_CONTRACTION_RANK, a common-word frequency.
EN_CONTRACTIONS = """
    ain't aren't can't couldn't didn't doesn't don't hadn't hasn't haven't he'd he'll he's
    how's i'd i'll i'm i've isn't it'd it'll it's let's mightn't mustn't needn't shan't she'd
    she'll she's shouldn't that'll that's there'd there'll there's they'd they'll they're
    they've wasn't we'd we'll we're we've weren't what'll what're what's what've where's who'd
    who'll who're who's who've why's won't wouldn't y'all you'd you'll you're you've
""".split()
EN_CONTRACTION_RANK = 300


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(name: str) -> Path:
    url, expected = SOURCES[name]
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        print(f"downloading {url}", file=sys.stderr)
        tmp = path.with_suffix(path.suffix + ".part")
        urllib.request.urlretrieve(url, tmp)
        tmp.rename(path)
    actual = sha256(path)
    if actual != expected:
        sys.exit(f"error: {path} has SHA-256 {actual}, expected {expected}; delete it to download again")
    return path


def read_counts(path: Path):
    with path.open(encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2 and parts[1].isdigit():
                yield parts[0], int(parts[1])


def normalize(word: str) -> str:
    return word.lower().translate(APOSTROPHES)


def vesum_forms(path: Path):
    """Yields (form, tags) for every form line."""
    with bz2.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) < 2:
                continue
            yield normalize(parts[0]), parts[1].split(":")


def ukrainian_counts(name: str) -> tuple:
    """The counts of Ukrainian-looking words in a frequency list, and the list's total."""
    counts = {}
    for word, count in read_counts(fetch(name)):
        word = normalize(word)
        if UK_WORD.match(word):
            counts[word] = counts.get(word, 0) + count
    return counts, sum(counts.values())


def build_uk() -> dict:
    subtitles, subtitle_total = ukrainian_counts("uk_full.txt")
    subtitles = {w: c for w, c in subtitles.items() if c >= UK_MIN_COUNT}
    wikipedia, wikipedia_total = ukrainian_counts("ukwiki-2022-08-30.txt")
    common, proper = set(), set()
    for form, tags in vesum_forms(fetch("dict_corp_vis.txt.bz2")):
        if UK_WORD.match(form) and not any(t in VESUM_REJECT_TAGS for t in tags):
            (proper if "prop" in tags else common).add(form)
    words = {}
    added = apostrophe_forms = 0
    for form in common | proper:
        if form in subtitles:
            words[form] = max(1, round(subtitles[form] / subtitle_total * UK_SCALE))
        elif (form in common and wikipedia.get(form, 0) >= WIKI_MIN_COUNT
              and ("'" in form or len(form) >= WIKI_MIN_LETTERS)):
            words[form] = max(1, round(WIKI_WEIGHT * wikipedia[form] / wikipedia_total * UK_SCALE))
            added += 1
        elif "'" in form:
            words[form] = UK_APOSTROPHE_COUNT
            apostrophe_forms += 1
    dropped = sorted((c, w) for w, c in subtitles.items() if w not in words)[::-1][:25]
    print(f"uk: {len(subtitles)} subtitle words, {len(words) - added - apostrophe_forms} in VESUM, "
          f"{added} from Wikipedia, {apostrophe_forms} apostrophe forms", file=sys.stderr)
    print("uk: most frequent dropped: " + " ".join(f"{w}:{c}" for c, w in dropped), file=sys.stderr)
    return words


def is_english_word(word: str) -> bool:
    if not EN_WORD.match(word):
        return False
    if len(word) == 1:
        return word in EN_SINGLE_LETTERS
    if len(word) == 2:
        return word in EN_TWO_LETTER
    if len(word) == 3:
        return bool(EN_VOWELS & set(word)) or word in EN_THREE_LETTER_NO_VOWEL
    return True


def build_en() -> dict:
    words = {}
    for word, count in read_counts(fetch("en_50k.txt")):
        word = normalize(word)
        if is_english_word(word):
            words[word] = words.get(word, 0) + count
    ranked = sorted(words.values(), reverse=True)
    contraction_count = ranked[min(EN_CONTRACTION_RANK, len(ranked) - 1)]
    for word in EN_CONTRACTIONS:
        words.setdefault(word, contraction_count)
    print(f"en: {len(words)} words ({len(EN_CONTRACTIONS)} contractions at {contraction_count})",
          file=sys.stderr)
    return words


def write(path: Path, words: dict, header: list) -> None:
    rows = sorted(words.items(), key=lambda item: (-item[1], item[0]))
    with path.open("w", encoding="utf-8", newline="\n") as f:
        for line in header:
            f.write(f"# {line}\n")
        for word, count in rows:
            f.write(f"{word}\t{count}\n")
    print(f"wrote {path.relative_to(ROOT)} ({len(rows)} words)", file=sys.stderr)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write(OUT / "uk.tsv", build_uk(), [
        "Ukrainian word forms with OpenSubtitles 2018 counts (FrequencyWords, CC-BY-SA-4.0) and Ukrainian",
        "Wikipedia counts (wikipedia-word-frequency, CC-BY-SA), per billion subtitle words, filtered by",
        "VESUM / dict_uk v6.8.6 (brown-uk, CC-BY-NC-SA-4.0), which adds its apostrophe forms.",
        "Non-commercial use only. Built by tools/build_dictionaries.py; sources in Resources/Licenses.txt.",
    ])
    write(OUT / "en.tsv", build_en(), [
        "English words with OpenSubtitles 2018 counts (FrequencyWords, CC-BY-SA-4.0).",
        "Built by tools/build_dictionaries.py; sources in Resources/Licenses.txt.",
    ])


if __name__ == "__main__":
    main()
