t's mostly the app. At least 4.8 s of the roughly 7.5 s happens on the phone before any data leaves it. The backend is only part of the last 2.7 s, which it shares with gzip on the phone and the upload. I didn't change any code; I only read it and ran replays on this laptop.

Part of the wait	Time	Side	How sure
Screen frozen while the SDK prepares the upload	4.8 s	App	Certain: the greyed-out button only appears at 20.0 s
gzip on the phone, upload, backend processing	2.7 s	App + network + backend	Split between them is estimated; needs logs to pin down
Main cause: the app sends far more data than the form needs

The Add New Payee screens never call Keydata.startSession(). Only BehaviorBiometricActivity.kt:118 does, and the payee screen's endSession is commented out (AddNewPayeeAccountActivity.kt:458).
The SDK starts recording when the app launches (MyApplication.kt:14) and only clears its buffers when a session starts or ends.
So every payee submit sends everything recorded since app launch, until the limits hit: 40,000 sensor samples (about 2 minutes) and 150 touches.
Your 5 harekrishna payload files in Videos prove this. They come from this exact flow (Main → Add/Manage Payee → Add New Payee → Success):
All 5 start at app launch; the first samples are from the splash screen.
Four are at the 40,000-sample limit (11.4 MB), with 24k–52k later samples thrown away, so the form's own sensor data never got in.
Key events keep growing across submits: 43 → 90 → 124 → 157 → 187.
What that extra size costs, measured on this laptop with the SDK's Gson 2.11.0 and the backend's own store code:

Fresh 13 s form	1st submit after launch	Full buffer
Sensor samples	4,330	31,066	40,000
Upload size (raw → gzip)	1.3 → 0.18 MB	8.7 → 1.07 MB	11.4 → 1.42 MB
SDK work on the screen thread	0.27 s	0.66 s	0.82 s
Upload at 10 Mbit/s (calculated)	0.15 s	0.9 s	1.1 s
Backend Python work (no database)	0.04 s	0.32 s	0.66 s
Database round trips (store step)	56	77	177
The phone took 4.8 s. For a full buffer that's 6x slower than this laptop, which is plausible for a debug build. For a fresh 13 s form the phone would have to be 18x slower, so the video's payload was very likely a big one. The video also starts right after an earlier submit, which means this one carried that attempt's data too.

Second cause: the SDK does all this work on the screen thread. Keydata.kt:1193 copies the data, makes two indented (pretty-printed) copies, then builds the upload body, all before the upload starts. One indented copy goes to logcat (debug builds only) and one is saved to a file. At full size, the two indented copies (a 19.7-million-character string, twice) are 68% of that work.

Backend: a real cost, but the smaller one. Each upload:

opens 2 new Oracle connections, with no pool;
inserts each touch with its own database round trip (store_user_behaviour_data_svm_pattern.py:345), which is 150 round trips at the limit;
waits for the keystroke AI transform-data call;
parses the whole JSON.
Its own Python work is 0.04 s for a clean form and 0.66 s for a full buffer. On top of that comes the wait for the database: the number of round trips times the latency to Oracle, for example 177 × 5 ms ≈ 0.9 s. I can't measure that from here.

Not yet confirmed. Three checks need no code changes:

Server log around 09:54. The Decompressed gzip: X -> Y bytes line gives the exact upload size: about 11.4 M means a full buffer, about 1.3 M a clean form. The time from that line to pattern result is is the backend's share.
Database. For that session's NAV_SESSIONS row, check SESSION_END_TS − SESSION_START_TS (minutes means the buffer wasn't reset) and SAMPLING_DROPPED_SAMPLE_COUNT (above 0 means the limit was hit).
Phone. Run adb logcat -v threadtime -s Keydata_SDK during one submit. Buffer stats … sensors=N gives the size; POST to API Response Code is the network plus the backend.
Two side findings:

Once the limit is hit, every submit stores the same first 2 minutes after app launch and drops the form's own sensor data. So the model is being trained on the wrong behaviour, not just slowly.
The "Analysis Failed: Something went wrong" toast at the start of the video means the previous submit got an HTTP 500. The backend log line Failed - Pattern: …, Keystroke: … will say why.
The replay scripts are in C:\Users\LOLLAS~1\AppData\Local\Temp\claude\c--Users-LOLLA-SRIKANTH-Videos-docker-compose--3--docker-compose\196b2ae8-9c56-44f4-8cf3-95d95559063c\scratchpad\sdkfreeze.
