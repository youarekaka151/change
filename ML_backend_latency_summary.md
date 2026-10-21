# ML backend latency test: old code vs new code

**Date:** 21 Oct 2026
**Old code:** `Videos\docker-compose (3)\docker-compose`
**New code:** `Downloads\Telegram Desktop\all_zipped` (version 2, with the Verdict Explorer changes ML1–ML7)
**Full report with charts:** `Downloads\ML_backend_latency_old_vs_new.html`

---

## 1. Bottom line

The new code adds time to **one job only**: scoring (`POST /nav/ai/predict`) with the explanation switched on, which is how the new `.env` ships it (`ML_EXPLAIN=true`).

| What the explanation adds | Time |
|---|---|
| Accepted session (no counterfactual) | **+0.4 ms** (0.2% of the request) |
| Rejected session (counterfactual runs) | **+8.2 ms** median, p99 14.7 ms, max 38 ms (4.2% of the request) |
| Response size | 712 B → 3.8 KB |

In the head-to-head run, old and new workers took the same requests in turn, which removes laptop drift:

| Requests | Old median | New, explain ON | New, explain OFF |
|---|---|---|---|
| Recorded sessions | 167.2 ms | 172.8 ms (**+6.4 ms**, ratio 1.035) | 168.5 ms (+0.3 ms, none) |
| Extra-large sessions (9–12 MB) | 506.5 ms | 512.8 ms (+4.1 ms, ratio 1.009) | 507.9 ms (−0.2 ms) |
| Rejected sessions | 174.3 ms | 185.8 ms (+9.0 ms) | 174.0 ms |
| Accepted sessions | 166.9 ms | 166.9 ms (+0.7 ms) | 164.6 ms |

- **Verdicts:** `is_genuine`, `score` and `risk_score` were identical in 288 of 288 head-to-head requests, and in 384 of 384 research-model pairs on the full grid.
- **Unchanged:** worker start-up, every other route, HTTP transfer, parallel throughput, and training up to 50 sessions.
- **Training above 50 sessions is faster.** A 60-session user takes 118 s instead of 134 s, because the new code trains on the first 50 (`ML_ENROL_MAX_SESSIONS=50`). Applying that limit costs about 9 s itself, and that part can be cut to under a second (section 5).
- **New endpoints:** the model card (`GET /nav/ai/card/<user>`) takes 2.5–13 ms. ML6 (`rebuild_train_values.py`) takes 2–12 s per user, run once by hand.

---

## 2. What was tested, and how

### 2.1 Safety
- Both code bases were tested as copies in a temporary scratch folder. Neither original folder was changed: I re-checked after the tests, and both are identical to before with no file modified.
- Timers were wrappers added in memory while the tests ran; no file was edited to measure anything.
- Each copy got a test-only `.env` with the original `ML_*` settings and test keys.
- The DB backend was not called. Training fetched sessions from a local stand-in for its sessions API.

### 2.2 Environment
- **Machine:** this laptop, Intel i5-1235U (2 performance + 8 efficiency cores), on AC power, about 5 GB RAM free throughout.
- **Software:** Python 3.10.11 with the production library versions: NumPy 2.2.6, SciPy 1.15.3, scikit-learn 1.7.2, pandas 2.3.3, tslearn 0.8.1 with compiled (numba) DTW, Flask 3.0.3 and Werkzeug 3.0.6 as pinned.
- **Settings:** as in both `.env` files: `ML_SELECTION=v8`, `ML_EXTRACT_NARROW=1`, `ML_CACHE_MAX=256`, `ML_WARM_MAX=50`. The new code adds `ML_ENROL_MAX_SESSIONS=50` and `ML_EXPLAIN=true`.

### 2.3 Data
- **Requests:** the exact bytes the DB backend posts (`json.dumps` of its own `payload_from_request_session`, backend (5)):
  - **43 recorded sessions** (bala 10, harshit 10, hemanth 13, satyasri 10): 1.2–8.9 MB each, median 2.5 MB; 3,600–29,000 sensor samples, median 7,900; 35–91 touches; 28–78 keys.
  - **5 extra-large sessions** (harekrishna): 9.4–12.4 MB each, 31,000–40,000 sensor samples (the SDK's cap).
- **Models:** the 8 research v8 models, plus 6 trained by each code base's own enrolment: bala, harshit, hemanth, satyasri, pool43 (all 43 sessions) and pool60 (the 43 plus 17 repeats under new IDs, to cross the 50-session limit).

### 2.4 Phases, run once for the old code, then once for the new code

| Phase | What it measures | Size |
|---|---|---|
| Training ×2 | The real `enrol()` for 6 users, step by step | 12 enrolments per code base |
| Boot | 5 fresh worker starts, 3 with timers on boot steps, 2 with `-X importtime` | 10 processes |
| Scoring grid | Every model × every session × 3 repeats, shuffled, through the Flask app | old 2,016 requests; new 4,032 (each with explain ON and OFF) |
| zstd | Compressed request bodies | 172 requests |
| Profile | cProfile over 2 models × 48 sessions | 96 requests |
| Endpoints | health, info, train (4 branches), status (3), card (new) | 200 calls each |
| HTTP | Real HTTP server in another process, new TCP connection per request | 516 requests |
| Concurrency | 1, 2 and 4 workers scoring at the same time | 210 requests |
| ML6, microbenchmarks | New code only | 6 users; 672 pairs |
| Head-to-head | Old and new workers alternating on the same requests | 288 × 3 arms |
| Levers | Possible speed-ups, each checked for an identical result | |

A calibration workload (JSON parse, NumPy, pure Python) ran between every phase to track machine speed.

---

## 3. Results

### 3.1 Scoring: `POST /nav/ai/predict`

**Distribution (full grid).** The old and new grids ran an hour apart, with the laptop about 5% faster during the new one. Compare old with new in the head-to-head table (section 1), and compare new ON with new OFF here.

| Code | Sessions | Requests | Median ms | Mean | p90 | p99 | Max | Response |
|---|---|---|---|---|---|---|---|---|
| Old | recorded | 1,806 | 174.3 | 187.5 | 243.0 | 391.9 | 430.9 | 712 B |
| Old | extra-large | 210 | 527.4 | 509.0 | 550.0 | 574.4 | 583.0 | 716 B |
| New, explain ON | recorded | 1,806 | 168.5 | 182.2 | 241.2 | 389.0 | 739.8 | 3.8 KB |
| New, explain ON | extra-large | 210 | 505.1 | 488.6 | 531.8 | 561.2 | 600.3 | 3.8 KB |
| New, explain OFF | recorded | 1,806 | 162.7 | 176.4 | 233.4 | 374.8 | 881.5 | 712 B |
| New, explain OFF | extra-large | 210 | 495.5 | 483.5 | 524.3 | 643.9 | 873.3 | 716 B |

- CPU/wall is 0.98 everywhere, so the time is pure computation, with no waiting on memory or disk.
- There were no errors.
- The model makes no difference: per-model medians were 171–177 ms.

**Where the time goes: mean exclusive ms per stage.** The parts add up to the mean request time.

| Stage | Old, recorded | New ON, recorded | Old, extra-large | New ON, extra-large |
|---|---|---|---|---|
| JSON body read + parse | 42.3 (22.5%) | 39.2 | 171.2 (33.6%) | 163.0 |
| Session parse + 50 Hz alignment (`SessionView`) | 27.9 (14.9%) | 25.8 | 104.4 (20.5%) | 97.3 |
| Sensor sanitiser | 13.9 (7.4%) | 13.1 | 51.6 (10.1%) | 48.2 |
| Behaviour cleaner | 3.3 (1.8%) | 3.0 | 8.2 (1.6%) | 7.8 |
| Feature families | 95.1 (50.7%) | 90.9 | 160.5 (31.5%) | 152.8 |
| Family plan + row fix-ups | 0.9 | 0.8 | 1.2 | 1.1 |
| SVM scoring | 0.4 (0.2%) | 0.4 | 0.4 | 0.4 |
| Explain block (new) | – | 0.3 | – | 0.3 |
| Counterfactual (new, rejected only) | – | 4.9 (2.7%) | – | 6.4 (1.3%) |
| Service code, cache, risk score, log | 1.1 | 1.0 | 2.2 | 2.2 |
| Response JSON | 0.08 | 0.17 | 0.08 | 0.17 |
| Flask/Werkzeug request handling | 2.6 | 2.6 | 9.2 | 8.9 |
| **Total (mean)** | **187.5** | **182.2** | **509.0** | **488.6** |

**Feature families v8 needs: median / mean ms, recorded sessions, old code** (the new code runs the same code):

| tap_locked_narrow | tap_spectral | keystrokes | stage2 | correlations | touch | key_locked | sensor_spectral |
|---|---|---|---|---|---|---|---|
| 15.4 / 16.1 | 11.6 / 12.3 | 11.5 / 11.8 | 9.3 / 10.3 | 8.7 / 9.3 | 7.7 / 7.9 | 6.8 / 7.3 | 5.4 / 5.7 |

| derived_motion | sensor_stats | orientation | field_segments | field_contrasts | touch_paths | nonkbd |
|---|---|---|---|---|---|---|
| 3.9 / 4.1 | 3.8 / 4.1 | 2.1 / 2.2 | 1.4 / 1.4 | 1.2 / 1.3 | 0.7 / 0.9 | 0.6 / 0.6 |

**The explanation's cost, paired: the same model, session and repeat with explain ON minus OFF.**

| Sessions | Pairs | Explain code, median / mean / p99 ms | Counterfactual, median / max ms | Share of request |
|---|---|---|---|---|
| Accepted | 609 | 0.37 / 0.39 / 0.88 | 0 / 0 | 0.23% |
| Rejected | 1,407 | 8.20 / 7.69 / 14.71 | 7.74 / 37.61 | 4.18% |
| Rejected, extra-large | 210 | 7.16 / 6.81 / 13.21 | 6.77 / 13.72 | 1.50% |
| All | 2,016 | 6.08 / 5.49 / 13.78 | 5.68 / 37.61 | 2.27% |

- The counterfactual resets features one at a time until the model accepts: a median of 14 steps, max 25. Each step re-scores every remaining feature, about 610 kernel evaluations per rejected session at the median.
- Most grid pairs score a session against another person's model, so 70% are rejected. That's the worst case for the counterfactual; with real traffic most sessions are the owner's and accepted.

**Other scoring facts**
- **First request of a fresh worker:** 563 ms old, 518 ms new. About 390 ms of it is the one-time "family plan" learning. The first request for each further model is 145–153 ms.
- **zstd bodies (`ML_PREDICT_ZSTD=true`):** 2,468 KB → 322 KB, 7.7× smaller. Parse time is the same (36.0 vs 35.9 ms), because decompression is nearly free.
- **Scaling:** request time ≈ 84 ms + **11.1 ms per 1,000 sensor samples**. JSON parsing ≈ 14.6 ms per MB of request body. Sensor samples drive the cost; the slowest sessions are the 40,000-sample ones at about 534 ms.
- **Hot functions (cProfile):**
  - JSON `raw_decode`: 13% of own time.
  - `SessionView.__init__`: 12% own and 27% cumulative, with its per-sample helper `_f` called about 100,000 times per request (8.9%).
  - NumPy reductions: 4.7%.
  - Per file, `new_adapid_schema.py` takes 26% of all own time.

### 3.2 Worker start-up

`gunicorn.config.py` runs `cpu_count × 2 + 1` gevent workers with no `preload_app`, so every worker builds the service itself after each deploy or restart.

| | Old | New |
|---|---|---|
| Import app, `.pyc` present (median of 4) | 9.21 s | 8.83 s |
| First boot after a deploy (no `.pyc`) | 10.02 s | 9.45 s |
| Of which: DTW kernel compile (numba prime) | 6.08 s | 5.82 s |
| Of which: importing the vendored feature code and libraries | ~2.9 s | ~2.8 s |
| Of which: loading 14 models (warm) | 0.12 s | 0.12 s |
| Boot checks | 0 ms | 0 ms |
| Memory after boot / after 5 requests | 290 / 312 MB | 291 / 312 MB |
| Modules imported | 2,282 | 2,285 |

- **Import self-time by package:** SciPy 0.74 s, scikit-learn 0.46 s, pandas 0.39 s, numba 0.34 s, NumPy 0.23 s.
- **pytest is imported at boot** (about 0.09 s of its own): tslearn imports scikit-learn's test helpers, which import pytest.
- **The DTW compile is unused:** v8 has no `dtw_*` features, so scoring never calls DTW.

### 3.3 Training job (`enrol()`, run by `train_jobs.py`)

| User | Sessions | Old trains on | Old | New trains on | New | Change |
|---|---|---|---|---|---|---|
| bala | 10 | 10 | 19.8 s | 10 | 18.7 s | same code (laptop speed) |
| harshit | 10 | 10 | 19.3 s | 10 | 18.6 s | same code |
| hemanth | 13 | 13 | 26.5 s | 13 | 25.2 s | same code |
| satyasri | 10 | 10 | 18.9 s | 10 | 16.8 s | same code |
| pool43 | 43 | 43 | 100.6 s | 43 | 91.8 s | same code |
| pool60 | 60 | 60 | 133.7 s | **50** | **117.9 s** | **−12%, new limit** |

Times are the mean of 2 runs. The first job of every trainer process also pays **6.6–7.2 s** of numba compile (DTW + DBA), because `train_jobs.py` doesn't prime it.

**Step breakdown (seconds)**

| Step | bala old | pool43 old | pool43 new | pool60 old | pool60 new |
|---|---|---|---|---|---|
| DTW templates (per-channel medoid/DBA) | 6.96 | 49.41 | 44.54 | 63.39 | 52.36 |
| DTW templates (rest) | 0.75 | 3.10 | 2.77 | 4.66 | 3.70 |
| Feature extraction: families | 4.54 | 19.74 | 18.30 | 26.31 | 20.86 |
| Feature extraction: rest | 2.08 | 8.43 | 7.72 | 11.44 | 8.93 |
| Census (session file read ×3) | 1.33 | 5.38 | 5.08 | 7.46 | 5.76 |
| Availability totals (read ×4) | 1.24 | 4.79 | 4.47 | 6.88 | 5.24 |
| Session parse, clean, sanitise | 0.97 | 3.91 | 3.62 | 5.62 | 4.30 |
| Fetch from backend (HTTP + JSON) | 0.69 | 2.61 | 2.33 | 3.65 | 3.50 |
| Filter + write envelope | 0.58 | 2.43 | 2.15 | 3.52 | 6.06 |
| **New: apply the 50-session limit** | – | – | – | – | **6.42** |
| Holdout scoring | 0.51 | 0.46 | 0.49 | 0.44 | 0.40 |
| SVM fit + calibration | 0.00 | 0.01 | 0.01 | 0.01 | 0.00 |
| Save, validate, publish, clean up | 0.15 | 0.19 | 0.18 | 0.19 | 0.20 |
| **Total** | **19.82** | **100.56** | **91.76** | **133.72** | **117.88** |
| Garbage collection (inside the above) | 1.41 | 4.99 | 4.81 | 7.22 | 7.78 |

- **DTW templates take about half of the training time.** The SVM fit itself takes about 10 ms.
- **The session file is read 4 times:** census ×3 and availability ×1.
- **The 50-session limit costs about 9 s.** It is 6.4 s in `narrow_envelope` plus 2.5 s of extra envelope writing, and `narrow_envelope` alone measured 8.4 s on the 182 MB file. It still saves about 25 s of DTW and feature work.

### 3.4 Other routes (median / p99 ms)

| Route | Old | New | Response |
|---|---|---|---|
| `GET /nav/ai/health` | 0.22 / 0.46 | 0.20 / 0.82 | 18 B |
| `GET /nav/ai/info` | 0.56 / 0.82 | 0.56 / 0.88 | 7.0 KB |
| `POST /nav/ai/train`: model exists | 0.43 / 0.70 | 0.43 / 0.65 | 131 B |
| `POST /nav/ai/train`: queue new user | 14.78 / 17.50 | 14.13 / 16.94 | 121 B |
| `POST /nav/ai/train`: already queued | 0.92 / 1.24 | 0.91 / 1.77 | 121 B |
| `POST /nav/ai/train`: bad key | 0.28 / 0.50 | 0.25 / 0.53 | 44 B |
| `GET /nav/ai/train/<user>`: ready / queued / none | 0.56 / 0.54 / 0.45 | 0.46 / 0.53 / 0.43 | ~120 B |
| `GET /nav/ai/card/<user>`, model without training rows | – | 2.5–2.8 | ~20 KB |
| … with 10 / 13 rows | – | 4.1–4.3 / 5.2 | 25 / 30 KB |
| … with 43 / 50 rows | – | 12.2 / 12.9 | 71 / 77 KB |
| … unknown user | – | 0.35 | 76 B |

Queueing a new user writes two small JSON files with fsync, which is why it is the only route above 1 ms besides the card.

### 3.5 Over real HTTP (separate client process, new TCP connection per request)

| Code | Body | Size | Client ms | Server ms | HTTP + transport (median / p90) | Response |
|---|---|---|---|---|---|---|
| Old | JSON | 2,468 KB | 197.6 | 179.4 | 18.1 / 25.8 ms | 712 B |
| Old | zstd | 322 KB | 189.4 | 174.1 | 15.9 / 25.1 ms | 712 B |
| New | JSON | 2,468 KB | 194.8 | 178.2 | 18.6 / 25.6 ms | 3.8 KB |
| New | zstd | 322 KB | 191.4 | 174.3 | 18.1 / 25.5 ms | 3.8 KB |

### 3.6 Several workers at once

| Workers | Old req/s | Old median | New req/s | New median |
|---|---|---|---|---|
| 1 | 5.48 | 161 ms | 5.28 | 164 ms |
| 2 | 9.83 | 178 ms | 9.54 | 178 ms |
| 4 | 14.13 | 253 ms | 14.31 | 252 ms |

Beyond 2 workers, extra workers land on this laptop's efficiency cores; a server with uniform cores scales closer to linear.

### 3.7 New code only

**Functions timed in isolation (672 model × session pairs)**

| Function | Median | Max |
|---|---|---|
| `breakdown()`, accepted session | 0.23 ms | 0.30 ms |
| `breakdown()`, rejected session | 8.17 ms | 13.44 ms |
| `explain()` decomposition | 0.083 ms | 0.51 ms |
| `vectorise()` (run a second time) | 0.037 ms | 0.11 ms |
| `counterfactual()` | 7.82 ms | 13.85 ms |
| `consistency_problem()` | < 0.001 ms | |
| Response JSON with / without the block | 0.063 / 0.004 ms | |
| Explain block size | 3.0 KB | 3.1 KB |

**Model card internals**
- Without training rows, `model_card()` takes 0.09 ms.
- With 43–50 rows it takes 4.4–4.6 ms, because it explains every training row.
- `jsonable()` takes 0.6–2.1 ms and `json.dumps` 0.4–1.8 ms.

**Bundle load:** the new training-rows proof adds 0.06–0.11 ms per model load, against `joblib.load` at 1.0–1.3 ms.

**ML6 (`rebuild_train_values.py`) on the 6 models the old code trained.** All were proven, with differences at most 1e-13, and written.

| User | Dry run (prove only) | Real run | Of which fetch / extraction / refit |
|---|---|---|---|
| bala | 2.4 s | 2.0 s | 0.6 s / 1.4 s / 4 ms |
| harshit | 1.9 s | 1.9 s | 0.5 / 1.4 s / 3 ms |
| hemanth | 2.5 s | 2.4 s | 0.7 / 1.7 s / 4 ms |
| satyasri | 1.7 s | 1.8 s | 0.4 / 1.3 s / 4 ms |
| pool43 | 8.0 s | 8.0 s | 2.2 / 5.6 s / 5 ms |
| pool60 | 11.3 s | 11.5 s | 3.2 / 8.1 s / 4 ms |

ML6 runs once per old model, by hand. It never runs on a scoring request.

---

## 4. Where the time goes, in one view

**A typical recorded scoring request (~188 ms mean):**
- feature families 51%;
- JSON parsing 22%;
- session parsing 15%;
- sensor sanitiser 7%;
- the new counterfactual 2.7% on average (rejected sessions only);
- the SVM itself 0.2%.

**A worker start (~9 s):** DTW compile 6.1 s, unused by v8; imports ~2.9 s; models 0.1 s.

**A training job:** DTW templates ~50%, feature extraction ~30%, re-reading the session file ~10%, everything else ~10%.

---

## 5. What can be reduced

Every measured lever was checked for an identical result: the same parsed objects, verdicts, trained models or templates. None of them changes a feature value or a score. None has been applied to the code.

### Scoring requests

| Lever | Costs today | Saving | Evidence |
|---|---|---|---|
| Parse the request body with orjson in the predict view (`orjson.loads(request.get_data())`) | 36.6 ms per recorded request, 250 ms extra-large | **−20.2 ms per request (12%)**, −87 ms extra-large | Measured; parsed objects identical 48/48 |
| Column-wise sensor streams in `SessionView` | 27.9 ms per recorded request, 104 ms extra-large | −12 to −14 ms | Measured in the 16 Oct study; arrays identical 43/43 |
| Vectorised counterfactual (new code; prototype written in this study) | 7.8 ms median, 13.9 ms max per rejected session | **−7.0 ms per rejected session** (9.4× faster; the explanation drops to ~1 ms) | Measured; identical result on 469/469 rejected sessions |
| Higher gen-0 GC threshold in the workers (`gc.set_threshold(50000, 20, 20)`) | GC 2.7 ms per request | −2.5 ms median (`gc.freeze` alone: no gain) | Measured; verdicts identical |
| Compress the backend → ML request (`ML_PREDICT_ZSTD=true` in the backend) | 2,468 KB per request on the wire | 322 KB; saves ~18 ms of transfer at 1 Gbit/s, ~176 ms at 100 Mbit/s | Measured sizes; backend setting only |

### Worker start-up and first request

| Lever | Costs today | Saving | Evidence |
|---|---|---|---|
| `preload_app = True` in `gunicorn.config.py` (`service_registry.py` already assumes it) | Every worker builds the service itself: ~9 s each | Built once in the master, then workers fork ready | Not measurable on Windows; test it with the gevent workers |
| Skip the DTW compile at boot when the selection has no `dtw_*` column (v8 has none) | 6.1 s per worker start | **−6.1 s per worker** | Measured; v8 scoring never calls DTW |
| Import tslearn only when DTW is needed (it pulls in scikit-learn's test helpers and pytest) | 0.74 s per worker start | −0.74 s | Measured; needs a change in the vendored code |
| Learn the family plan during boot instead of on the first request | 390 ms on the first request of every worker | First request 563 → ~173 ms | Measured; same plan, same features |

### Training job

| Lever | Costs today | Saving | Evidence |
|---|---|---|---|
| Build the census once and count availability in the same pass (the session file is read 4 times) | 7.5 s + 6.9 s for 60 sessions | **about −11.9 s** per 60-session enrolment | Estimate from measured step times |
| DTW templates on 2 processes (`n_jobs=2`; today 1) | 53.7 s for 43 sessions | **−9.9 s** (4 processes: −10.9 s) | Measured; templates identical; uses a core the scoring workers would otherwise get |
| Apply the 50-session limit with a byte copy instead of re-parsing and re-writing (new code) | ~9 s per enrolment above 50 sessions | about −8.5 s | Measured cost; saving estimated |
| Higher gen-0 GC threshold in the trainer | GC 4.8 s of an 86.7 s enrolment | −3.6 s (4%); `gc.freeze`: −3.1 s | Measured; trained models identical |
| Parse each session once for both the DTW builder and the feature pipeline | 5.6 s of parsing for 60 sessions (done twice) | about −2.8 s | Estimate from measured step times |
| Prime the DTW kernels when `train_jobs.py` starts | 6.6–7.2 s on the first enrolment after every restart | Moves it off the first user's wait | Measured |

---

## 6. Limits of this test

- **Laptop, not the production server.** Absolute milliseconds will differ on the server. The old-vs-new differences are reliable, because they come from the alternating head-to-head run on one machine.
- **Machine drift.** This CPU (2 performance + 8 efficiency cores) ran up to ~20% slower in the first minutes and was about 5% faster during the new-code run than the old-code run. The calibration workload shows this, which is why the head-to-head run is used for the comparison.
- **No production web stack.** gunicorn, gevent and nginx can't run on Windows, so their own overhead isn't included. The HTTP test used Werkzeug's server.
- **Model versions.** The research models were saved with scikit-learn 1.9.0 and loaded under 1.7.2, with a version warning. This doesn't affect timing, and both code bases ran in the same environment.
- **Data.** The sessions come from one app flow (add-payee, one screen change each). pool60 contains 17 repeated sessions under new IDs. Production sessions may be shorter or longer; the scaling of 11 ms per 1,000 sensor samples lets you estimate.
- **Worst case for the counterfactual.** Most grid pairs score another person's session, so 70% are rejected. With real traffic most sessions are accepted, and the average explanation cost is lower than the "all" figure.

---

## 7. Files

| File | What it is |
|---|---|
| `Downloads\ML_backend_latency_old_vs_new.html` | Full report with charts, every table, dark mode |
| `Downloads\ML_backend_latency_summary.md` | This summary |
| Scratch folder `...\196b2ae8-9c56-44f4-8cf3-95d95559063c\scratchpad\lat\` | Test scripts (`tools\`), raw results per request (`results\old`, `results\new`, `results\ab`, `results\levers`), test data (`data\`) |
