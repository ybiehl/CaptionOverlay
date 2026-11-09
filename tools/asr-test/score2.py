import json, re, glob, os, collections, jiwer
LIB = "/Users/yannickbiehl/Documents/ChatGPT/DisplayBridge/media/library/clips"
clips = [os.path.basename(f)[:-4] for f in sorted(glob.glob("audio/*.wav"))]
NUM = "null eins zwei drei vier fünf sechs sieben acht neun zehn elf zwölf".split()
REP = [("€", " euro "), ("$", " dollar "), ("%", " prozent "), (" hz", " hertz"), (" ms ", " millisekunden "), (" w ", " watt "),
       (" gb ", " gigabit "), ("d h ", "das heißt "), ("z b ", "zum beispiel "), ("display bridge", "displaybridge"),
       ("display pridge", "displaybridge"), ("displaypridge", "displaybridge"), ("mac os", "macos"), ("imax", "imacs"),
       ("usb c", "usbc"), ("noch mal", "nochmal"), (" ok ", " okay "), ("thunderbolt", "thunderbolt")]
def norm(t):
    t = " " + t.lower().replace("-", " ").replace("–", " ") + " "
    t = re.sub(r"(\d)\.(\d{3})", r"\1\2", t)
    t = re.sub(r"[^\w\s€$%]", " ", t); t = re.sub(r"\s+", " ", " " + t + " ")
    for a, b in REP: t = t.replace(a, b); t = re.sub(r"\s+", " ", t)
    t = " ".join(str(NUM.index(w)) if w in NUM else w for w in t.split())
    t = re.sub(r"(\d) (\d)", r"\1\2", t) if False else t
    return t.strip()
def _old(t):
    t = t.lower().replace("-", " ").replace("–", " ")
    t = re.sub(r"[^\w\s]", " ", t)
    return re.sub(r"\s+", " ", t).strip()
ref = {c: norm(" ".join(s["text"] for s in json.load(open(f"{LIB}/{c}/transcript.json"))["segments"])) for c in clips}
times = {"apple": {}, "parakeet": json.load(open("out/times-parakeet.json")), "turbo": json.load(open("out/times-turbo.json"))}
for l in open("out/times-apple.log"):
    p = l.split(); times["apple"]["audio/" + p[1]] = float(p[2])
dur = {c: os.path.getsize(f"audio/{c}.wav") / 32000 for c in clips}
res = {}
for eng in ("apple", "parakeet", "turbo"):
    hyp = {c: norm(open(f"out/{eng}-{c}.txt").read()) for c in clips}
    R, H = [ref[c] for c in clips], [hyp[c] for c in clips]
    o = jiwer.process_words(R, H)
    cer = jiwer.cer([r.replace(" ", "") for r in R], [h.replace(" ", "") for h in H])
    subs = collections.Counter(); ins = collections.Counter(); dels = collections.Counter()
    for i, al in enumerate(o.alignments):
        rw, hw = o.references[i], o.hypotheses[i]
        for a in al:
            if a.type == "substitute":
                subs[(" ".join(rw[a.ref_start_idx:a.ref_end_idx]), " ".join(hw[a.hyp_start_idx:a.hyp_end_idx]))] += 1
            elif a.type == "insert": ins[" ".join(hw[a.hyp_start_idx:a.hyp_end_idx])] += 1
            elif a.type == "delete": dels[" ".join(rw[a.ref_start_idx:a.ref_end_idx])] += 1
    per = {c: round(jiwer.wer(ref[c], hyp[c]) * 100, 1) for c in clips}
    sec = sum(times[eng][f"audio/{c}.wav"] for c in clips)
    res[eng] = dict(wer=round(o.wer * 100, 2), cer_nospace=round(cer * 100, 2), S=o.substitutions, D=o.deletions, I=o.insertions,
                    words=sum(len(r.split()) for r in R), per=per, sec=round(sec, 1), x_realtime=round(sum(dur.values()) / sec))
    json.dump(dict(subs=[[a, b, n] for (a, b), n in subs.most_common()], ins=ins.most_common(), dels=dels.most_common()),
              open(f"out/errors2-{eng}.json", "w"), ensure_ascii=False, indent=0)
    print(eng, json.dumps(res[eng], ensure_ascii=False))
print("audio minutes", round(sum(dur.values()) / 60, 1))
json.dump(res, open("out/summary2.json", "w"), indent=1)
