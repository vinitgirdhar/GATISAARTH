"""One-off edit: insert Urban canyon + Edge AI scenes after the tunnel scene,
shift the later scenes by +10.87 s and swap the bed for the original score."""
import re

P = "index.html"
SH = 10.87
s = open(P, encoding="utf-8").read()


def rep(a, b):
    global s
    assert a in s, a[:90]
    s = s.replace(a, b, 1)


rep('data-duration="30.5" data-width', 'data-duration="41.4" data-width')
rep('data-start="2.97" data-duration="11.76" data-track-index="2"',
    'data-start="2.97" data-duration="22.63" data-track-index="2"')
rep('<div id="tap"></div>', '''<img class="scr" id="i-uc2" src="assets/shots/uc2.jpg" alt="Simulating an urban canyon, weak multipath GNSS" />
          <img class="scr" id="i-uc6" src="assets/shots/uc6.jpg" alt="GNSS degraded, plus or minus 75 metres" />
          <img class="scr" id="i-uc11" src="assets/shots/uc11.jpg" alt="Marker holds the street in an urban canyon" />
          <img class="scr" id="i-ai0" src="assets/shots/ai0.jpg" alt="Home: Urban canyon, weak GNSS, fusing IMU plus NavIC" />
          <img class="scr" id="i-ai1" src="assets/shots/ai1.jpg" alt="Edge AI and Telemetry section" />
          <div id="tap"></div><div id="tap2"></div>''')
rep('#tap { position: absolute; left: 52px; top: 761px;',
    '#tap2 { position: absolute; left: 178px; top: 756px; width: 64px; height: 64px; border-radius: 50%; border: 4px solid #fff; opacity: 0; }\n      #tap { position: absolute; left: 52px; top: 761px;')

rep('      /* scene 5 cards */', '''      /* urban canyon + edge AI stat tiles */
      .tiles { display: flex; gap: 22px; margin-top: 40px; }
      .tile2 { background: var(--surface); border: 2px solid var(--border); border-radius: 28px; padding: 24px 30px; min-width: 250px; }
      .tile2 b { display: block; font-size: 72px; font-weight: 800; letter-spacing: -0.035em; line-height: 1; }
      .tile2 b small { font-size: 34px; font-weight: 700; margin-left: 6px; }
      .tile2 span { display: block; font-size: 25px; color: var(--muted); margin-top: 12px; }
      .chips { display: flex; flex-wrap: wrap; gap: 14px; margin-top: 26px; max-width: 1060px; }
      .chp { font-size: 27px; font-weight: 600; padding: 12px 22px; border-radius: 40px; }
      .chp.am { color: var(--amber); background: rgba(255,149,0,0.14); }
      .chp.gy { color: #e5e5ea; background: var(--surface2); }
      .note { font-size: 25px; color: var(--muted); margin-top: 26px; max-width: 1000px; line-height: 1.38; border-left: 4px solid var(--blue); padding-left: 20px; }
      #s4b .h, #s4c .h { font-size: 94px; }
      /* scene 5 cards */''')

rep('      <!-- Scene 5: voice + integrity -->', '''      <!-- Scene 4b: urban canyon -->
      <section id="s4b" class="scene clip" data-start="14.43" data-duration="5.77" data-track-index="1">
        <div class="wrap" id="s4bw"><div class="col" style="width:1080px">
          <p class="eyebrow" id="s4b-e" style="color:#ff9500">Urban canyon</p>
          <h2 class="h" id="s4b-h"><span class="ln">Towers bounce GPS.</span><span class="ln" style="color:#98989f">It leans on the IMU.</span></h2>
          <div class="tiles">
            <div class="tile2" id="u1"><b class="a">±75<small>m</small></b><span>GNSS fix · degraded</span></div>
            <div class="tile2" id="u2"><b style="color:#0a84ff">50<small>%</small></b><span>Confidence</span></div>
            <div class="tile2" id="u3"><b>30<small>km/h</small></b><span>Holding the street</span></div>
          </div>
          <div class="chips">
            <span class="chp am" id="uc-c1">GNSS degraded · IMU assisted</span>
            <span class="chp gy" id="uc-c2">Fusing IMU + NavIC</span>
          </div>
          <p class="fine" id="s4b-f">Urban canyon test · simulated weak, multipath GNSS</p>
        </div></div>
      </section>

      <!-- Scene 4c: edge AI & telemetry -->
      <section id="s4c" class="scene clip" data-start="19.9" data-duration="5.7" data-track-index="1">
        <div class="wrap" id="s4cw"><div class="col" style="width:1080px">
          <p class="eyebrow" id="s4c-e">Edge AI &amp; Telemetry</p>
          <h2 class="h" id="s4c-h"><span class="ln">Neural inference.</span><span class="ln" style="color:#98989f">On the phone.</span></h2>
          <div class="tiles">
            <div class="tile2" id="a1"><b>1<small>ms</small></b><span>Speed model latency</span></div>
            <div class="tile2" id="a2"><b class="g">98<small>%</small></b><span>AI conf</span></div>
            <div class="tile2" id="a3"><b style="font-size:60px">25.0<small>°C</small></b><span>IMU temperature · bias</span></div>
          </div>
          <div class="chips">
            <span class="chp gy" id="ai-c1">Road vibration · Smooth · 0.00 g</span>
            <span class="chp gy" id="ai-c2">Detected road anomalies: bumps &amp; potholes</span>
          </div>
          <p class="note" id="s4c-n">Advisory: not used for position until it beats the outage benchmark on recorded drives.</p>
        </div></div>
      </section>

      <!-- Scene 5: voice + integrity -->''')

for sid in ("s5", "s6", "s7", "s8"):
    m = re.search(r'<section id="%s" class="scene clip" data-start="([\d.]+)"' % sid, s)
    s = s.replace(m.group(0), m.group(0).replace(m.group(1), "%.2f" % (float(m.group(1)) + SH)))


def shift_sfx(m):
    n = int(m.group(1))
    if n >= 11:
        return 'id="sx%d" data-start="%.2f"' % (n, float(m.group(2)) + SH)
    return m.group(0)


s = re.sub(r'id="sx(\d+)" data-start="([\d.]+)"', shift_sfx, s)

a = s.index("// ---------- Scene 5")
b = s.index("// ---------- audio-reactive")
blk = re.sub(r", (\d+(?:\.\d+)?)\);", lambda m: ", %.2f);" % (float(m.group(1)) + SH), s[a:b])
blk = (blk.replace("(accept on strong cue 19.66s)", "(accept at 30.53s, score accent)")
          .replace("// beat-locked: 19.66s", "// accent: portal accept")
          .replace("(beat-locked: 26.20s)", "(score hit 37.08s)"))
s = s[:a] + blk + s[b:]

rep('tl.to("#phoneA", { opacity: 0, x: 120, duration: 0.3, ease: "power2.in" }, 14.43);',
    '''tl.set("#tap2", { opacity: 0.95, scale: 0.4 }, 15.0);
      tl.to("#tap2", { opacity: 0, scale: 1.8, duration: 0.55, ease: "power2.out" }, 15.01);
      tl.fromTo("#i-uc2", { opacity: 0 }, { opacity: 1, duration: 0.2 }, 15.2);
      tl.fromTo("#i-uc6", { opacity: 0 }, { opacity: 1, duration: 0.3 }, 16.3);
      tl.fromTo("#i-uc11", { opacity: 0 }, { opacity: 1, duration: 0.3 }, 17.4);
      tl.fromTo("#i-ai0", { opacity: 0, y: 70 }, { opacity: 1, y: 0, duration: 0.45, ease: E }, 18.5);
      tl.fromTo("#i-ai1", { opacity: 0, y: 90 }, { opacity: 1, y: 0, duration: 0.5, ease: E }, 20.2);
      tl.to("#phoneA", { opacity: 0, x: 120, duration: 0.3, ease: "power2.in" }, 25.3);''')

rep("      // ---------- Scene 5", '''      // ---------- Scene 4b: urban canyon
      tl.fromTo("#s4b-e", { opacity: 0, x: -30 }, { opacity: 1, x: 0, duration: 0.4, ease: E }, 14.73);
      tl.fromTo("#s4b-h .ln", { opacity: 0, y: 50 }, { opacity: 1, y: 0, duration: 0.5, ease: "expo.out", stagger: 0.16 }, 14.8);
      tl.fromTo(["#u1", "#u2", "#u3"], { opacity: 0, y: 40 }, { opacity: 1, y: 0, duration: 0.45, ease: "back.out(1.4)", stagger: 0.35 }, 15.5);
      tl.fromTo(["#uc-c1", "#uc-c2"], { opacity: 0, x: -30 }, { opacity: 1, x: 0, duration: 0.4, ease: E, stagger: 0.3 }, 16.6);
      tl.fromTo("#s4b-f", { opacity: 0 }, { opacity: 1, duration: 0.4 }, 17.2);
      tl.to("#s4bw", { opacity: 0, x: -60, duration: 0.3, ease: "power2.in" }, 19.9);

      // ---------- Scene 4c: edge AI & telemetry
      tl.fromTo("#s4c-e", { opacity: 0, x: -30 }, { opacity: 1, x: 0, duration: 0.4, ease: E }, 20.2);
      tl.fromTo("#s4c-h .ln", { opacity: 0, y: 50 }, { opacity: 1, y: 0, duration: 0.5, ease: "expo.out", stagger: 0.16 }, 20.27);
      tl.fromTo(["#a1", "#a2", "#a3"], { opacity: 0, y: 40 }, { opacity: 1, y: 0, duration: 0.45, ease: "back.out(1.4)", stagger: 0.4 }, 20.9);
      tl.fromTo(["#ai-c1", "#ai-c2"], { opacity: 0, x: -30 }, { opacity: 1, x: 0, duration: 0.4, ease: E, stagger: 0.3 }, 22.2);
      tl.fromTo("#s4c-n", { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.45, ease: E }, 22.9);
      tl.to("#s4cw", { opacity: 0, x: -60, duration: 0.3, ease: "power2.in" }, 25.3);

      // ---------- Scene 5''')

s = re.sub(r'<audio id="music"[^>]*></audio>',
           '<audio id="music" data-start="0" data-duration="41.4" data-track-index="10" data-volume="0.8" src="assets/music/score.wav"></audio>', s)
rep("    </div>\n\n    <script>", '''      <audio id="sx19" data-start="15.0" data-duration="0.05" data-track-index="15" data-volume="0.7" src="assets/sfx/interface/click_003.ogg"></audio>
      <audio id="sx20" data-start="18.46" data-duration="0.8" data-track-index="16" data-volume="0.45" src="assets/sfx/casino/card-slide-1.ogg"></audio>
      <audio id="sx21" data-start="20.16" data-duration="0.8" data-track-index="15" data-volume="0.5" src="assets/sfx/casino/card-slide-1.ogg"></audio>
    </div>

    <script>''')
s = s.replace("f / AD.fps < 30.5", "f / AD.fps < 41.4")
s = s.replace('{ x: -90, y: -40, duration: 30.5, ease: "none" }', '{ x: -90, y: -40, duration: 41.4, ease: "none" }')
open(P, "w", encoding="utf-8").write(s)
print("edited")
