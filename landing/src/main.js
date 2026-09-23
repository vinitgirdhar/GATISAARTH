/**
 * GATISAARTH HIGH-ENERGY INTERACTIVE ENGINE
 * - Synthesized futuristic audio effects (Web Audio API)
 * - Interactive cursor follower glow
 * - 3D card tilt & parallax
 * - Real-time Outage Drift Calculator
 * - 16:9 Uncropped Video Theater with scrubber & chapter markers
 * - Scroll-driven reveal animations
 * - Interactive mobile phone APK emulator
 * - Side-by-side Outage Arena simulation canvas
 */

document.addEventListener('DOMContentLoaded', () => {
  initAudioSFX();
  initCursorGlow();
  initScrollProgress();
  initAmbientCanvas();
  initScrollRevealAnimations();
  initCardMicroInteractions();
  initDriftCalculator();
  initTheaterVideo();
  initApkSimulator();
  initOutageSimulation();
  initMetricsCountUp();
  initApkDownloadModal();
});

/* ==========================================================================
   1. SYNTHESIZED WEB AUDIO SFX (ZERO-DEPENDENCY HAPTIC AUDIO FEEDBACK)
   ========================================================================== */
let audioCtx = null;
let sfxEnabled = true;

function ensureAudioCtx() {
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (AudioContextClass) {
      audioCtx = new AudioContextClass();
    }
  }
  if (audioCtx && audioCtx.state === 'suspended') {
    audioCtx.resume();
  }
}

function playTone(freq, type, duration, gainLevel) {
  if (!sfxEnabled) return;
  try {
    ensureAudioCtx();
    if (!audioCtx) return;

    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();

    osc.type = type || 'sine';
    osc.frequency.setValueAtTime(freq, audioCtx.currentTime);

    gain.gain.setValueAtTime(gainLevel || 0.05, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);

    osc.connect(gain);
    gain.connect(audioCtx.destination);

    osc.start();
    osc.stop(audioCtx.currentTime + duration);
  } catch (_) {}
}

// Soft high-tech hover sound
function playHoverSound() {
  playTone(780, 'sine', 0.06, 0.02);
}

// Crisp futuristic click sound
function playClickSound() {
  playTone(1050, 'triangle', 0.08, 0.06);
  setTimeout(() => playTone(1420, 'sine', 0.06, 0.04), 30);
}

function initAudioSFX() {
  const sfxToggleBtn = document.getElementById('sfxToggleBtn');
  const sfxStatusText = document.getElementById('sfxStatusText');

  // Attach sound triggers to interactive elements
  document.querySelectorAll('[data-sound="hover"]').forEach(el => {
    el.addEventListener('mouseenter', () => playHoverSound());
  });

  document.querySelectorAll('[data-sound="click"], .btn-primary-hero, .btn-primary-large, .btn-primary-sm, .hud-btn, .chapter-pill-btn, .nav-tab, .map-mode-chip, .btn-scenario, .btn-cut-gnss, .btn-mount').forEach(el => {
    el.addEventListener('click', () => {
      ensureAudioCtx();
      playClickSound();
    });
  });

  // Toggle button
  if (sfxToggleBtn) {
    sfxToggleBtn.addEventListener('click', () => {
      sfxEnabled = !sfxEnabled;
      if (sfxStatusText) {
        sfxStatusText.textContent = sfxEnabled ? 'SFX: ON' : 'SFX: OFF';
      }
      sfxToggleBtn.style.background = sfxEnabled ? 'var(--surface-subtle)' : 'transparent';
      if (sfxEnabled) {
        ensureAudioCtx();
        playClickSound();
      }
    });
  }
}

/* ==========================================================================
   2. CURSOR GLOW FOLLOWER
   ========================================================================== */
function initCursorGlow() {
  const glow = document.getElementById('cursorGlow');
  if (!glow) return;

  let mouseX = window.innerWidth / 2;
  let mouseY = window.innerHeight / 2;
  let currentX = mouseX;
  let currentY = mouseY;

  window.addEventListener('mousemove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
  }, { passive: true });

  function renderCursor() {
    currentX += (mouseX - currentX) * 0.15;
    currentY += (mouseY - currentY) * 0.15;
    glow.style.transform = `translate(${currentX}px, ${currentY}px) translate(-50%, -50%)`;
    requestAnimationFrame(renderCursor);
  }
  requestAnimationFrame(renderCursor);
}

/* ==========================================================================
   3. SCROLL PROGRESS BAR
   ========================================================================== */
function initScrollProgress() {
  const progressBar = document.getElementById('scrollProgressBar');
  if (!progressBar) return;

  window.addEventListener('scroll', () => {
    const scrollTop = window.scrollY || document.documentElement.scrollTop;
    const docHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight;
    const pct = docHeight > 0 ? (scrollTop / docHeight) * 100 : 0;
    progressBar.style.width = `${pct}%`;
  }, { passive: true });
}

/* ==========================================================================
   4. AMBIENT CYBERNETIC VECTOR CANVAS
   ========================================================================== */
function initAmbientCanvas() {
  const canvas = document.getElementById('ambientCanvas');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  let w, h;
  let particles = [];
  const particleCount = 42;

  function resize() {
    w = canvas.width = window.innerWidth;
    h = canvas.height = window.innerHeight;
  }
  window.addEventListener('resize', resize);
  resize();

  for (let i = 0; i < particleCount; i++) {
    particles.push({
      x: Math.random() * w,
      y: Math.random() * h,
      vx: (Math.random() - 0.5) * 0.45,
      vy: (Math.random() - 0.5) * 0.45,
      radius: Math.random() * 2 + 1,
      color: Math.random() > 0.5 ? 'rgba(6, 182, 212,' : 'rgba(139, 92, 246,'
    });
  }

  function render() {
    ctx.clearRect(0, 0, w, h);

    for (let i = 0; i < particleCount; i++) {
      const p = particles[i];
      p.x += p.vx;
      p.y += p.vy;

      if (p.x < 0) p.x = w;
      if (p.x > w) p.x = 0;
      if (p.y < 0) p.y = h;
      if (p.y > h) p.y = 0;

      ctx.beginPath();
      ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
      ctx.fillStyle = `${p.color} 0.7)`;
      ctx.fill();

      for (let j = i + 1; j < particleCount; j++) {
        const p2 = particles[j];
        const dx = p.x - p2.x;
        const dy = p.y - p2.y;
        const dist = Math.sqrt(dx * dx + dy * dy);

        if (dist < 140) {
          ctx.beginPath();
          ctx.strokeStyle = `rgba(6, 182, 212, ${0.16 * (1 - dist / 140)})`;
          ctx.lineWidth = 1;
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(p2.x, p2.y);
          ctx.stroke();
        }
      }
    }

    requestAnimationFrame(render);
  }
  requestAnimationFrame(render);
}

/* ==========================================================================
   5. SCROLL-DRIVEN REVEAL ANIMATIONS
   ========================================================================== */
function initScrollRevealAnimations() {
  const reveals = document.querySelectorAll('.scroll-reveal');
  if (!reveals.length) return;

  const observer = new IntersectionObserver((entries, obs) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-revealed');
        obs.unobserve(entry.target);
      }
    });
  }, {
    threshold: 0.1,
    rootMargin: '0px 0px -40px 0px'
  });

  reveals.forEach(el => observer.observe(el));
}

/* ==========================================================================
   6. PRECISION CARD MICRO-INTERACTIONS (SUBTLE & TACTILE, ZERO FLOATING)
   ========================================================================== */
function initCardMicroInteractions() {
  const cards = document.querySelectorAll('.feature-card, .callout-card, .result-tile');
  cards.forEach(card => {
    card.addEventListener('mouseenter', () => {
      card.classList.add('card-focused');
      // Subtle haptic tick if audio is active
      if (typeof playHoverSound === 'function') {
        playHoverSound();
      }
    });

    card.addEventListener('mouseleave', () => {
      card.classList.remove('card-focused');
    });
  });
}

/* ==========================================================================
   7. LIVE REAL-TIME OUTAGE DRIFT CALCULATOR
   ========================================================================== */
function initDriftCalculator() {
  const lengthSlider = document.getElementById('tunnelLengthSlider');
  const speedSlider = document.getElementById('vehicleSpeedSlider');
  const lengthVal = document.getElementById('tunnelLengthVal');
  const speedVal = document.getElementById('vehicleSpeedVal');
  const mountBtns = document.querySelectorAll('.btn-mount');
  const mountVal = document.getElementById('mountStateVal');

  const calcTradDrift = document.getElementById('calcTradDrift');
  const calcTradStatus = document.getElementById('calcTradStatus');
  const calcTradBar = document.getElementById('calcTradBar');

  const calcGatiDrift = document.getElementById('calcGatiDrift');
  const calcGatiStatus = document.getElementById('calcGatiStatus');
  const calcGatiBar = document.getElementById('calcGatiBar');

  if (!lengthSlider || !speedSlider) return;

  let currentMount = 'windshield';

  function updateCalculator() {
    const km = parseFloat(lengthSlider.value);
    const speed = parseFloat(speedSlider.value);

    // Label names
    let tunnelName = '';
    if (km === 9.0) tunnelName = ' (Atal Tunnel)';
    else if (km === 2.0) tunnelName = ' (Mumbai Undersea Tunnel)';
    else if (km >= 12.0) tunnelName = ' (Deep Mountain Corridor)';
    else if (km <= 1.0) tunnelName = ' (City Underpass)';

    lengthVal.textContent = `${km.toFixed(1)} km${tunnelName}`;
    speedVal.textContent = `${speed} km/h`;

    // Standard GPS Drift calculation:
    // Without satellite lock, GPS drift grows rapidly or freezes.
    const tradDriftMeters = Math.round(km * 80 * (speed / 60) + Math.min(km * 40, 400));
    calcTradDrift.textContent = `+${tradDriftMeters} m`;
    calcTradStatus.textContent = `Position marker teleports ${tradDriftMeters}m off-road into mountain rock or freezes blindly.`;
    const tradBarPct = Math.min(100, Math.max(30, (tradDriftMeters / 1500) * 100));
    calcTradBar.style.width = `${tradBarPct}%`;

    // GatiSaarth 15-State ES-EKF calculation:
    // Sub-2% drift rate with Non-Holonomic Constraints (NHC) and Zero Velocity Updates (ZUPT)
    let driftRatePct = 1.6;
    if (currentMount === 'vent') driftRatePct = 1.8;
    if (currentMount === 'cupholder') driftRatePct = 1.95;

    const corridorErrorMeters = ((km * 1000) * (driftRatePct / 100) * 0.1).toFixed(1);
    calcGatiDrift.textContent = `±${corridorErrorMeters} m`;
    calcGatiStatus.textContent = `${driftRatePct}% drift · vehicle holds lane center throughout ${km.toFixed(1)} km outage without satellite lock.`;
    const gatiBarPct = Math.min(40, Math.max(8, (parseFloat(corridorErrorMeters) / 80) * 100));
    calcGatiBar.style.width = `${gatiBarPct}%`;
  }

  lengthSlider.addEventListener('input', updateCalculator);
  speedSlider.addEventListener('input', updateCalculator);

  mountBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      mountBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentMount = btn.dataset.mount;
      if (currentMount === 'windshield') mountVal.textContent = 'Windshield / Dashboard';
      else if (currentMount === 'vent') mountVal.textContent = 'AC Vent Mount';
      else mountVal.textContent = 'Cup Holder / Console';
      updateCalculator();
    });
  });

  updateCalculator();
}

/* ==========================================================================
   8. 16:9 WIDESCREEN CINEMATIC THEATER VIDEO PLAYER
   ========================================================================== */
function initTheaterVideo() {
  const video = document.getElementById('theaterVideo');
  if (!video) return;

  const playBtn = document.getElementById('theaterPlayBtn');
  const bigPlayBtn = document.getElementById('theaterBigPlayBtn');
  const playIcon = document.getElementById('theaterPlayIcon');
  const pauseIcon = document.getElementById('theaterPauseIcon');
  const soundBtn = document.getElementById('theaterSoundBtn');
  const soundOff = document.getElementById('theaterSoundOff');
  const soundOn = document.getElementById('theaterSoundOn');
  const fullscreenBtn = document.getElementById('theaterFullscreenBtn');
  const progressWrap = document.getElementById('theaterProgressWrap');
  const progressFill = document.getElementById('theaterProgressFill');
  const timestamp = document.getElementById('theaterTimestamp');
  const chapterBtns = document.querySelectorAll('.chapter-pill-btn');

  video.muted = true;
  video.play().then(() => {
    if (bigPlayBtn) bigPlayBtn.style.display = 'none';
    if (playIcon) playIcon.classList.add('hidden');
    if (pauseIcon) pauseIcon.classList.remove('hidden');
  }).catch(() => {
    if (bigPlayBtn) bigPlayBtn.style.display = 'flex';
    if (playIcon) playIcon.classList.remove('hidden');
    if (pauseIcon) pauseIcon.classList.add('hidden');
  });

  function togglePlay() {
    if (video.paused) {
      video.play();
      if (bigPlayBtn) bigPlayBtn.style.display = 'none';
      if (playIcon) playIcon.classList.add('hidden');
      if (pauseIcon) pauseIcon.classList.remove('hidden');
    } else {
      video.pause();
      if (bigPlayBtn) bigPlayBtn.style.display = 'flex';
      if (playIcon) playIcon.classList.remove('hidden');
      if (pauseIcon) pauseIcon.classList.add('hidden');
    }
  }

  if (playBtn) playBtn.addEventListener('click', togglePlay);
  if (bigPlayBtn) bigPlayBtn.addEventListener('click', togglePlay);

  if (soundBtn) {
    soundBtn.addEventListener('click', () => {
      video.muted = !video.muted;
      if (video.muted) {
        soundOff.classList.remove('hidden');
        soundOn.classList.add('hidden');
      } else {
        soundOff.classList.add('hidden');
        soundOn.classList.remove('hidden');
      }
    });
  }

  if (fullscreenBtn) {
    fullscreenBtn.addEventListener('click', () => {
      if (!document.fullscreenElement) {
        video.requestFullscreen().catch(() => {});
      } else {
        document.exitFullscreen().catch(() => {});
      }
    });
  }

  video.addEventListener('timeupdate', () => {
    if (video.duration) {
      const pct = (video.currentTime / video.duration) * 100;
      if (progressFill) progressFill.style.width = `${pct}%`;

      const curM = Math.floor(video.currentTime / 60);
      const curS = Math.floor(video.currentTime % 60).toString().padStart(2, '0');
      const durM = Math.floor(video.duration / 60);
      const durS = Math.floor(video.duration % 60).toString().padStart(2, '0');
      if (timestamp) timestamp.textContent = `${curM}:${curS} / ${durM}:${durS}`;

      chapterBtns.forEach(btn => {
        const t = parseFloat(btn.dataset.time || '0');
        if (video.currentTime >= t && video.currentTime < t + 5) {
          chapterBtns.forEach(b => b.classList.remove('active'));
          btn.classList.add('active');
        }
      });
    }
  });

  if (progressWrap) {
    progressWrap.addEventListener('click', (e) => {
      const rect = progressWrap.getBoundingClientRect();
      const pos = (e.clientX - rect.left) / rect.width;
      video.currentTime = pos * video.duration;
    });
  }

  chapterBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      chapterBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const time = parseFloat(btn.dataset.time || '0');
      video.currentTime = time;
      video.play();
      if (bigPlayBtn) bigPlayBtn.style.display = 'none';
      if (playIcon) playIcon.classList.add('hidden');
      if (pauseIcon) pauseIcon.classList.remove('hidden');
    });
  });
}

/* ==========================================================================
   9. INTERACTIVE MOBILE APK PAGE SIMULATOR
   ========================================================================== */
function initApkSimulator() {
  const navTabs = document.querySelectorAll('.apk-bottom-nav .nav-tab');
  const apkPages = document.querySelectorAll('.apk-page');
  const apkTriggerTunnelBtn = document.getElementById('apkTriggerTunnelBtn');
  const apkResetGnssBtn = document.getElementById('apkResetGnssBtn');
  const simTunnelOverlay = document.getElementById('simTunnelOverlay');
  const mapStatusText = document.getElementById('mapStatusText');
  const mapAccuracyVal = document.getElementById('mapAccuracyVal');
  const mapStatusPill = document.getElementById('mapStatusPill');

  const btnChipTunnel = document.getElementById('btnChipTunnel');
  const btnChipCanyon = document.getElementById('btnChipCanyon');
  const btnChipRestore = document.getElementById('btnChipRestore');

  navTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      navTabs.forEach(t => t.classList.remove('active'));
      apkPages.forEach(p => p.classList.remove('active-page'));

      tab.classList.add('active');
      const targetPageId = tab.dataset.page;
      const targetPage = document.getElementById(targetPageId);
      if (targetPage) {
        targetPage.classList.add('active-page');
      }
    });
  });

  function activateApkTunnelMode() {
    navTabs.forEach(t => t.classList.remove('active'));
    apkPages.forEach(p => p.classList.remove('active-page'));
    const mapTab = document.querySelector('.apk-bottom-nav [data-page="pageMap"]');
    const mapPage = document.getElementById('pageMap');
    if (mapTab && mapPage) {
      mapTab.classList.add('active');
      mapPage.classList.add('active-page');
    }

    if (simTunnelOverlay) simTunnelOverlay.style.display = 'block';
    if (mapStatusText) mapStatusText.textContent = 'Outage: 15-State Dead Reckoning';
    if (mapAccuracyVal) mapAccuracyVal.textContent = '±7m';
    if (mapStatusPill) {
      mapStatusPill.style.borderColor = 'rgba(255, 59, 48, 0.5)';
      mapStatusPill.querySelector('.map-status-dot').style.backgroundColor = '#FF3B30';
    }
  }

  function resetApkGnssMode() {
    if (simTunnelOverlay) simTunnelOverlay.style.display = 'none';
    if (mapStatusText) mapStatusText.textContent = 'Exact Localise · GNSS LOCKED';
    if (mapAccuracyVal) mapAccuracyVal.textContent = '±5m';
    if (mapStatusPill) {
      mapStatusPill.style.borderColor = 'rgba(52, 199, 89, 0.5)';
      mapStatusPill.querySelector('.map-status-dot').style.backgroundColor = '#34C759';
    }
  }

  if (apkTriggerTunnelBtn) apkTriggerTunnelBtn.addEventListener('click', activateApkTunnelMode);
  if (apkResetGnssBtn) apkResetGnssBtn.addEventListener('click', resetApkGnssMode);
  if (btnChipTunnel) btnChipTunnel.addEventListener('click', activateApkTunnelMode);
  if (btnChipRestore) btnChipRestore.addEventListener('click', resetApkGnssMode);
  if (btnChipCanyon) {
    btnChipCanyon.addEventListener('click', () => {
      if (simTunnelOverlay) simTunnelOverlay.style.display = 'none';
      if (mapStatusText) mapStatusText.textContent = 'Urban Canyon · Multipath Rejection';
      if (mapAccuracyVal) mapAccuracyVal.textContent = '±8m';
      if (mapStatusPill) {
        mapStatusPill.style.borderColor = 'rgba(255, 149, 0, 0.5)';
        mapStatusPill.querySelector('.map-status-dot').style.backgroundColor = '#FF9500';
      }
    });
  }
}

/* ==========================================================================
   10. SIDE-BY-SIDE OUTAGE SIMULATION ARENA
   ========================================================================== */
function initOutageSimulation() {
  const canvasTrad = document.getElementById('canvasTrad');
  const canvasGati = document.getElementById('canvasGati');
  if (!canvasTrad || !canvasGati) return;

  const ctxTrad = canvasTrad.getContext('2d');
  const ctxGati = canvasGati.getContext('2d');

  const btnCutGnssToggle = document.getElementById('btnCutGnssToggle');
  const btnCutGnssLabel = document.getElementById('btnCutGnssLabel');
  const tradErrorOverlay = document.getElementById('tradErrorOverlay');
  const tradStatusPill = document.getElementById('tradStatusPill');
  const gatiStatusPill = document.getElementById('gatiStatusPill');
  const tradDriftVal = document.getElementById('tradDriftVal');
  const gatiDriftVal = document.getElementById('gatiDriftVal');
  const gatiUncertaintyPill = document.getElementById('gatiUncertaintyPill');
  const scenarioBtns = document.querySelectorAll('.btn-scenario');

  let gnssSevered = true;
  let animFrameId = null;
  let simTime = 0;
  let currentScenario = 'tunnel';

  btnCutGnssToggle.addEventListener('click', () => {
    gnssSevered = !gnssSevered;
    updateSimulationState();
  });

  scenarioBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      scenarioBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentScenario = btn.dataset.scenario;
      if (currentScenario === 'normal') {
        gnssSevered = false;
      } else {
        gnssSevered = true;
      }
      updateSimulationState();
    });
  });

  function updateSimulationState() {
    if (gnssSevered) {
      btnCutGnssLabel.textContent = 'Restore GNSS Fix';
      btnCutGnssToggle.style.background = 'rgba(52, 199, 89, 0.2)';
      btnCutGnssToggle.style.borderColor = '#34C759';
      btnCutGnssToggle.querySelector('.red-zap-icon').textContent = '✓';
      btnCutGnssToggle.querySelector('.red-zap-icon').style.color = '#34C759';

      tradErrorOverlay.style.display = 'block';
      tradStatusPill.className = 'arena-status-pill danger';
      tradStatusPill.innerHTML = '<span>GPS LOST · DRIFTING / FROZEN</span>';
      tradDriftVal.textContent = '+240 m';

      gatiStatusPill.className = 'arena-status-pill success';
      gatiStatusPill.innerHTML = '<span class="pill-dot green"></span><span>DEAD RECKONING ACTIVE (±7m)</span>';
      gatiDriftVal.textContent = '< 1.8%';
      gatiUncertaintyPill.textContent = 'Honest Corridor: ±7.2m';
    } else {
      btnCutGnssLabel.textContent = 'Sever GNSS Signal Now';
      btnCutGnssToggle.style.background = 'rgba(239, 68, 68, 0.2)';
      btnCutGnssToggle.style.borderColor = '#EF4444';
      btnCutGnssToggle.querySelector('.red-zap-icon').textContent = '⚡';
      btnCutGnssToggle.querySelector('.red-zap-icon').style.color = '#FFA39E';

      tradErrorOverlay.style.display = 'none';
      tradStatusPill.className = 'arena-status-pill success';
      tradStatusPill.innerHTML = '<span class="pill-dot green"></span><span>GNSS LOCKED</span>';
      tradDriftVal.textContent = '±4 m';

      gatiStatusPill.className = 'arena-status-pill success';
      gatiStatusPill.innerHTML = '<span class="pill-dot green"></span><span>GNSS LOCKED · EKF CALIBRATED</span>';
      gatiDriftVal.textContent = '0.0%';
      gatiUncertaintyPill.textContent = 'Satellite Fix: ±4.1m';
    }
  }

  function drawSimulation() {
    simTime += 0.02;
    const w = canvasTrad.width;
    const h = canvasTrad.height;

    [ctxTrad, ctxGati].forEach(ctx => {
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = '#080A10';
      ctx.fillRect(0, 0, w, h);

      ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
      ctx.lineWidth = 1;
      for (let x = 0; x < w; x += 30) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, h);
        ctx.stroke();
      }
      for (let y = 0; y < h; y += 30) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
        ctx.stroke();
      }

      ctx.beginPath();
      ctx.strokeStyle = '#1F2636';
      ctx.lineWidth = 28;
      ctx.lineCap = 'round';
      ctx.moveTo(40, 240);
      ctx.bezierCurveTo(120, 240, 160, 60, 260, 60);
      ctx.bezierCurveTo(340, 60, 380, 200, 430, 200);
      ctx.stroke();

      ctx.setLineDash([8, 8]);
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.25)';
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.setLineDash([]);

      if (currentScenario === 'tunnel') {
        ctx.fillStyle = 'rgba(255, 107, 0, 0.18)';
        ctx.fillRect(150, 20, 240, 240);
        ctx.strokeStyle = 'rgba(255, 107, 0, 0.5)';
        ctx.strokeRect(150, 20, 240, 240);

        ctx.font = '10px JetBrains Mono';
        ctx.fillStyle = '#FF9500';
        ctx.fillText('TUNNEL PORTAL ENTRY (GNSS SEVERED)', 160, 38);
      }
    });

    const t = (Math.sin(simTime * 0.5) + 1) / 2;
    const pGroundTruth = getBezierPoint(t, 40, 240, 120, 240, 160, 60, 260, 60, 340, 60, 380, 200, 430, 200);

    let pTrad = { x: pGroundTruth.x, y: pGroundTruth.y };
    if (gnssSevered && t > 0.35) {
      pTrad.x = 180 + (t - 0.35) * 40;
      pTrad.y = 120 + Math.sin(simTime * 4) * 15;
    }

    ctxTrad.beginPath();
    ctxTrad.arc(pTrad.x, pTrad.y, 8, 0, Math.PI * 2);
    ctxTrad.fillStyle = gnssSevered && t > 0.35 ? '#FF3B30' : '#06B6D4';
    ctxTrad.fill();
    ctxTrad.strokeStyle = '#FFFFFF';
    ctxTrad.lineWidth = 2;
    ctxTrad.stroke();

    if (gnssSevered && t > 0.35) {
      ctxTrad.beginPath();
      ctxTrad.setLineDash([4, 4]);
      ctxTrad.strokeStyle = 'rgba(255, 59, 48, 0.6)';
      ctxTrad.moveTo(pGroundTruth.x, pGroundTruth.y);
      ctxTrad.lineTo(pTrad.x, pTrad.y);
      ctxTrad.stroke();
      ctxTrad.setLineDash([]);
    }

    const pGati = { x: pGroundTruth.x, y: pGroundTruth.y };
    ctxGati.beginPath();
    ctxGati.strokeStyle = gnssSevered ? '#FF3B30' : '#06B6D4';
    ctxGati.lineWidth = 3.5;
    ctxGati.moveTo(40, 240);
    for (let step = 0; step <= t; step += 0.02) {
      const pt = getBezierPoint(step, 40, 240, 120, 240, 160, 60, 260, 60, 340, 60, 380, 200, 430, 200);
      ctxGati.lineTo(pt.x, pt.y);
    }
    ctxGati.stroke();

    const radius = gnssSevered ? 14 + Math.sin(simTime * 2) * 3 : 8;
    ctxGati.beginPath();
    ctxGati.arc(pGati.x, pGati.y, radius, 0, Math.PI * 2);
    ctxGati.fillStyle = gnssSevered ? 'rgba(255, 59, 48, 0.2)' : 'rgba(6, 182, 212, 0.2)';
    ctxGati.fill();
    ctxGati.strokeStyle = gnssSevered ? '#FF3B30' : '#06B6D4';
    ctxGati.lineWidth = 1.5;
    ctxGati.stroke();

    ctxGati.beginPath();
    ctxGati.arc(pGati.x, pGati.y, 6, 0, Math.PI * 2);
    ctxGati.fillStyle = '#FFFFFF';
    ctxGati.fill();

    animFrameId = requestAnimationFrame(drawSimulation);
  }

  function getBezierPoint(t, x0, y0, cx1, cy1, cx2, cy2, x1, y1, cx3, cy3, cx4, cy4, x2, y2) {
    if (t <= 0.5) {
      const localT = t * 2;
      return cubicBezier(localT, x0, y0, cx1, cy1, cx2, cy2, x1, y1);
    } else {
      const localT = (t - 0.5) * 2;
      return cubicBezier(localT, x1, y1, cx3, cy3, cx4, cy4, x2, y2);
    }
  }

  function cubicBezier(t, x0, y0, x1, y1, x2, y2, x3, y3) {
    const u = 1 - t;
    const tt = t * t;
    const uu = u * u;
    const uuu = uu * u;
    const ttt = tt * t;

    const x = uuu * x0 + 3 * uu * t * x1 + 3 * u * tt * x2 + ttt * x3;
    const y = uuu * y0 + 3 * uu * t * y1 + 3 * u * tt * y2 + ttt * y3;
    return { x, y };
  }

  updateSimulationState();
  animFrameId = requestAnimationFrame(drawSimulation);
}

/* ==========================================================================
   11. METRIC COUNT-UP ANIMATION
   ========================================================================== */
function initMetricsCountUp() {
  const trustVals = document.querySelectorAll('.trust-val');
  let animated = false;

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting && !animated) {
        animated = true;
        trustVals.forEach(val => {
          val.style.transform = 'scale(1.2)';
          val.style.transition = 'transform 0.3s cubic-bezier(0.16, 1, 0.3, 1)';
          setTimeout(() => { val.style.transform = 'scale(1)'; }, 300);
        });
      }
    });
  }, { threshold: 0.5 });

  const metricsSection = document.querySelector('.hero-trust-metrics');
  if (metricsSection) observer.observe(metricsSection);
}

/* ==========================================================================
   12. APK DOWNLOAD MODAL & SHA-256 COPY
   ========================================================================== */
function initApkDownloadModal() {
  const downloadModal = document.getElementById('downloadModal');
  const modalCloseBtn = document.getElementById('modalCloseBtn');
  const heroDownloadBtn = document.getElementById('heroDownloadBtn');
  const mainApkDownloadBtn = document.getElementById('mainApkDownloadBtn');
  const copyHashBtn = document.getElementById('copyHashBtn');
  const sha256Hash = document.getElementById('sha256Hash');

  function openModal() {
    if (downloadModal) {
      downloadModal.classList.add('active');
      downloadModal.setAttribute('aria-hidden', 'false');
    }
  }

  function closeModal() {
    if (downloadModal) {
      downloadModal.classList.remove('active');
      downloadModal.setAttribute('aria-hidden', 'true');
    }
  }

  if (heroDownloadBtn) heroDownloadBtn.addEventListener('click', openModal);
  if (mainApkDownloadBtn) mainApkDownloadBtn.addEventListener('click', openModal);
  if (modalCloseBtn) modalCloseBtn.addEventListener('click', closeModal);

  if (downloadModal) {
    downloadModal.addEventListener('click', (e) => {
      if (e.target === downloadModal) closeModal();
    });
  }

  if (copyHashBtn && sha256Hash) {
    copyHashBtn.addEventListener('click', () => {
      navigator.clipboard.writeText(sha256Hash.textContent.trim()).then(() => {
        const origText = copyHashBtn.textContent;
        copyHashBtn.textContent = 'Copied!';
        copyHashBtn.style.color = '#34C759';
        setTimeout(() => {
          copyHashBtn.textContent = origText;
          copyHashBtn.style.color = '';
        }, 2000);
      });
    });
  }
}
