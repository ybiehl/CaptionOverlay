import sys, time, os, json, glob
eng = sys.argv[1]
files = sorted(glob.glob("audio/*.wav"))
times = {}
if eng == "parakeet":
    from parakeet_mlx import from_pretrained
    m = from_pretrained("mlx-community/parakeet-tdt-0.6b-v3")
    for f in files:
        t0 = time.time(); r = m.transcribe(f, chunk_duration=120, overlap_duration=15)
        times[f] = time.time() - t0
        open(f"out/parakeet-{os.path.basename(f)[:-4]}.txt", "w").write(r.text)
        print(eng, f, round(times[f], 1), flush=True)
elif eng == "turbo":
    import mlx_whisper
    for f in files:
        t0 = time.time()
        r = mlx_whisper.transcribe(f, path_or_hf_repo="mlx-community/whisper-large-v3-turbo", language="de",
                                   condition_on_previous_text=False)
        times[f] = time.time() - t0
        open(f"out/turbo-{os.path.basename(f)[:-4]}.txt", "w").write(r["text"])
        print(eng, f, round(times[f], 1), flush=True)
json.dump(times, open(f"out/times-{eng}.json", "w"), indent=1)
