import json, glob, os, random, jiwer, importlib.util
spec = importlib.util.spec_from_file_location("s2", "score2.py"); src = open("score2.py").read()
ns = {}; exec(src.split("res = {}")[0], ns)            # reuse norm(), ref, clips
norm, ref, clips = ns["norm"], ns["ref"], ns["clips"]
E = ("apple", "parakeet", "turbo")
errs = {e: {} for e in E}   # (clip, ref_idx) -> hyp text
for e in E:
    for c in clips:
        h = norm(open(f"out/{e}-{c}.txt").read())
        o = jiwer.process_words(ref[c], h)
        rw, hw = o.references[0], o.hypotheses[0]
        for a in o.alignments[0]:
            if a.type == "equal": continue
            idxs = range(a.ref_start_idx, max(a.ref_end_idx, a.ref_start_idx + 1))
            for i in idxs: errs[e][(c, i)] = " ".join(hw[a.hyp_start_idx:a.hyp_end_idx]) or "∅"
allk = set().union(*[set(v) for v in errs.values()])
shared3 = [k for k in allk if all(k in errs[e] for e in E)]
print("ref positions all three disagree with (likely reference mistakes):", len(shared3))
random.seed(3)
for e in E:
    others = [x for x in E if x != e]
    uniq = sorted(k for k in errs[e] if not any(k in errs[o] for o in others))
    print(f"\n=== {e}: positions only {e} gets wrong: {len(uniq)} (of {len(errs[e])} differing)")
    # group consecutive positions, show 14 random snippets
    groups, cur = [], []
    for k in uniq:
        if cur and k[0] == cur[-1][0] and k[1] <= cur[-1][1] + 1: cur.append(k)
        else:
            if cur: groups.append(cur)
            cur = [k]
    if cur: groups.append(cur)
    print("  error spots:", len(groups))
    for g in random.sample(groups, min(14, len(groups))):
        c, i0, i1 = g[0][0], g[0][1], g[-1][1]
        rw = ref[c].split()
        ctx = " ".join(rw[max(0, i0-4):i0]) + " [" + " ".join(rw[i0:i1+1]) + "] " + " ".join(rw[i1+1:i1+4])
        hyp = " ".join(dict.fromkeys(errs[e][k] for k in g))
        print(f"   {ctx}  →  {hyp}")
print("\nexamples of shared (reference) mistakes:")
for k in random.sample(sorted(shared3), 8):
    c, i = k; rw = ref[c].split()
    print("  ", " ".join(rw[max(0,i-4):i]), "[", rw[i] if i < len(rw) else "", "]", " ".join(rw[i+1:i+4]), "→", {e: errs[e][k] for e in E})
