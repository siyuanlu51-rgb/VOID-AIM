(() => {
  'use strict';

  const $ = (s) => document.querySelector(s);
  const $$ = (s) => [...document.querySelectorAll(s)];
  const canvas = $('#arena');
  const ctx = canvas.getContext('2d');
  const wrap = $('#arenaWrap');
  const overlay = $('#startOverlay');
  const startButton = $('#startButton');
  const settings = {
    sensitivity: 1,
    fov: 90,
    targetSize: 34,
    duration: 30,
    color: '#ff335f',
    sound: true
  };

  const state = {
    running: false,
    paused: false,
    ended: false,
    score: 0,
    hits: 0,
    shots: 0,
    combo: 0,
    bestCombo: 0,
    timeLeft: 30,
    yaw: 0,
    pitch: 0,
    aimYaw: 0,
    aimPitch: 0,
    pointerWarmup: 0,
    target: null,
    particles: [],
    lastTime: 0,
    timerAccumulator: 0,
    flash: 0,
    recoil: 0,
    muzzleFlash: 0,
  };

  let audioContext = null;
  let toastTimer = 0;
  let dpr = 1;

  function resize() {
    const rect = canvas.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(rect.width * dpr);
    canvas.height = Math.round(rect.height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function rangePercent(input) {
    const pct = ((+input.value - +input.min) / (+input.max - +input.min)) * 100;
    input.style.setProperty('--pct', `${pct}%`);
  }

  function bindRange(id, formatter, onChange) {
    const input = $(`#${id}`);
    const output = $(`#${id}Value`);
    const update = () => {
      settings[id] = +input.value;
      output.textContent = formatter(+input.value);
      rangePercent(input);
      onChange?.(+input.value);
      saveSettings();
    };
    input.addEventListener('input', update);
    update();
  }

  function sizeLabel(v) {
    if (v < 25) return '微小';
    if (v < 39) return '中等';
    return '大型';
  }

  function saveSettings() {
    localStorage.setItem('voidAimSettings', JSON.stringify(settings));
  }

  function loadSettings() {
    try {
      const saved = JSON.parse(localStorage.getItem('voidAimSettings'));
      if (!saved) return;
      Object.assign(settings, saved);
      $('#sensitivity').value = settings.sensitivity;
      $('#fov').value = settings.fov;
      $('#targetSize').value = settings.targetSize;
      $$('[data-value]').forEach(b => b.classList.toggle('active', +b.dataset.value === settings.duration));
      $('#durationValue').textContent = `${settings.duration} 秒`;
      $$('.color').forEach(b => b.classList.toggle('active', b.dataset.color === settings.color));
      $('#soundToggle').classList.toggle('muted', !settings.sound);
    } catch (_) { /* Ignore damaged local preferences. */ }
  }

  function showToast(text) {
    const toast = $('#toast');
    toast.textContent = text;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 1800);
  }

  function beep(frequency = 520, duration = .045, volume = .045) {
    if (!settings.sound) return;
    try {
      audioContext ||= new (window.AudioContext || window.webkitAudioContext)();
      const osc = audioContext.createOscillator();
      const gain = audioContext.createGain();
      osc.type = 'sine';
      osc.frequency.value = frequency;
      gain.gain.setValueAtTime(volume, audioContext.currentTime);
      gain.gain.exponentialRampToValueAtTime(.001, audioContext.currentTime + duration);
      osc.connect(gain).connect(audioContext.destination);
      osc.start();
      osc.stop(audioContext.currentTime + duration);
    } catch (_) { /* Audio is optional. */ }
  }

  // Short, low-pressure suppressed-pistol sound synthesized at runtime.
  function gunshot() {
    if (!settings.sound) return;
    try {
      audioContext ||= new (window.AudioContext || window.webkitAudioContext)();
      const ac = audioContext;
      const now = ac.currentTime;
      const master = ac.createGain();
      master.gain.setValueAtTime(.2, now);
      master.gain.exponentialRampToValueAtTime(.001, now + .13);
      master.connect(ac.destination);

      const length = Math.floor(ac.sampleRate * .13);
      const buffer = ac.createBuffer(1, length, ac.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < length; i++) {
        const t = i / ac.sampleRate;
        data[i] = (Math.random() * 2 - 1) * Math.exp(-t * 42) * (1 - t / .13);
      }
      const noise = ac.createBufferSource();
      const band = ac.createBiquadFilter();
      noise.buffer = buffer;
      band.type = 'bandpass';
      band.frequency.setValueAtTime(820, now);
      band.Q.value = .7;
      noise.connect(band).connect(master);
      noise.start(now);

      const thump = ac.createOscillator();
      const thumpGain = ac.createGain();
      thump.type = 'triangle';
      thump.frequency.setValueAtTime(155, now);
      thump.frequency.exponentialRampToValueAtTime(72, now + .085);
      thumpGain.gain.setValueAtTime(.24, now);
      thumpGain.gain.exponentialRampToValueAtTime(.001, now + .1);
      thump.connect(thumpGain).connect(ac.destination);
      thump.start(now); thump.stop(now + .11);
    } catch (_) { /* Audio is optional. */ }
  }

  function randomTarget() {
    const spreadX = settings.fov * .46;
    const spreadY = Math.min(40, settings.fov * .31);
    let next;
    do {
      next = {
        yaw: state.yaw + (Math.random() - .5) * spreadX,
        pitch: Math.max(-42, Math.min(42, state.pitch + (Math.random() - .5) * spreadY)),
        depth: .72 + Math.random() * .28,
        born: performance.now(),
        pulse: Math.random() * Math.PI * 2
      };
    } while (state.target && Math.hypot(next.yaw - state.target.yaw, next.pitch - state.target.pitch) < 13);
    state.target = next;
  }

  function project(yaw, pitch, depth = 1) {
    const rect = canvas.getBoundingClientRect();
    const f = rect.width / (2 * Math.tan(settings.fov * Math.PI / 360));
    const relYaw = (yaw - state.yaw) * Math.PI / 180;
    const relPitch = (pitch - state.pitch) * Math.PI / 180;
    return {
      x: rect.width / 2 + Math.tan(relYaw) * f,
      y: rect.height / 2 - Math.tan(relPitch) * f,
      radius: settings.targetSize * (1.12 - depth * .22),
      visible: Math.abs(relYaw) < Math.PI / 2 && Math.abs(relPitch) < Math.PI / 2
    };
  }

  function shoot() {
    if (!state.running || state.paused || !state.target) return;
    state.shots++;
    state.recoil = 1;
    state.muzzleFlash = 1;
    gunshot();
    const p = project(state.target.yaw, state.target.pitch, state.target.depth);
    const rect = canvas.getBoundingClientRect();
    const distance = Math.hypot(p.x - rect.width / 2, p.y - rect.height / 2);
    if (p.visible && distance <= p.radius) {
      const precision = Math.max(0, 1 - distance / p.radius);
      const gained = Math.round(100 + precision * 75 + Math.min(state.combo, 20) * 3);
      state.score += gained;
      state.hits++;
      state.combo++;
      state.bestCombo = Math.max(state.bestCombo, state.combo);
      burst(p.x, p.y);
      state.flash = 1;
      beep(610 + Math.min(state.combo, 10) * 18, .035, .025);
      randomTarget();
    } else {
      state.combo = 0;
    }
    updateHud();
  }

  function burst(x, y) {
    for (let i = 0; i < 15; i++) {
      const a = Math.random() * Math.PI * 2;
      const speed = 35 + Math.random() * 90;
      state.particles.push({ x, y, vx: Math.cos(a) * speed, vy: Math.sin(a) * speed, life: 1, size: 1 + Math.random() * 2 });
    }
  }

  function updateHud() {
    $('#score').textContent = String(state.score).padStart(6, '0');
    $('#accuracy').textContent = state.shots ? `${Math.round(state.hits / state.shots * 100)}%` : '—';
    $('#combo').textContent = `×${state.combo}`;
    $('#timer').textContent = `00:${String(Math.ceil(state.timeLeft)).padStart(2, '0')}`;
  }

  function startGame() {
    if (state.ended || !state.running) {
      Object.assign(state, { running:true, paused:false, ended:false, score:0, hits:0, shots:0, combo:0, bestCombo:0, timeLeft:settings.duration, yaw:0, pitch:0, aimYaw:0, aimPitch:0, pointerWarmup:2, recoil:0, muzzleFlash:0, timerAccumulator:0 });
      randomTarget();
      updateHud();
    } else {
      state.paused = false;
    }
    overlay.classList.add('hidden');
    $('#pauseBadge').classList.remove('show');
    wrap.classList.add('playing');
    canvas.requestPointerLock?.();
    state.lastTime = performance.now();
  }

  function pauseGame() {
    if (!state.running || state.ended) return;
    state.paused = true;
    wrap.classList.remove('playing');
    $('#pauseBadge').classList.add('show');
  }

  function endGame() {
    state.running = false;
    state.ended = true;
    state.paused = false;
    document.exitPointerLock?.();
    wrap.classList.remove('playing');
    $('#pauseBadge').classList.remove('show');
    const accuracy = state.shots ? Math.round(state.hits / state.shots * 100) : 0;
    const oldBest = +(localStorage.getItem('voidAimBest') || 0);
    if (state.score > oldBest) localStorage.setItem('voidAimBest', state.score);
    $('#bestScore').textContent = Math.max(oldBest, state.score).toLocaleString();
    $('#overlayTitle').textContent = state.score > oldBest ? '新的个人最佳！' : '训练完成';
    $('#overlayText').innerHTML = `得分 <strong>${state.score.toLocaleString()}</strong> · 命中率 <strong>${accuracy}%</strong> · 最高连击 <strong>×${state.bestCombo}</strong>`;
    startButton.querySelector('span').textContent = '再次训练';
    overlay.classList.remove('hidden');
    beep(720, .18, .06);
  }

  function drawRoom(w, h) {
    const horizon = Math.max(h * .25, Math.min(h * .76, h * .51 + state.pitch * 3.1));
    const cx = w / 2 - state.yaw * 4.2;
    const gradient = ctx.createLinearGradient(0, 0, 0, h);
    gradient.addColorStop(0, '#252a2e');
    gradient.addColorStop(.5, '#171b1e');
    gradient.addColorStop(.51, '#17191a');
    gradient.addColorStop(1, '#0c0e0f');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, w, h);

    // Distant concrete slab wall with seams, stains and small surface pits.
    const wallShift = ((state.yaw * 5.2) % 150 + 150) % 150;
    ctx.strokeStyle = 'rgba(5, 7, 8, .33)';
    ctx.lineWidth = 1;
    for (let x = -150 + wallShift; x < w + 150; x += 150) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, horizon); ctx.stroke();
    }
    for (let y = horizon - 100; y > -100; y -= 100) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
    }
    for (let i = 0; i < 105; i++) {
      const x = ((i * 83.17 + wallShift * .37) % (w + 20)) - 10;
      const y = (i * 47.31) % Math.max(1, horizon);
      const a = .025 + (i % 5) * .007;
      ctx.fillStyle = `rgba(0,0,0,${a})`;
      ctx.fillRect(x, y, 1 + i % 3, 1 + (i * 2) % 3);
    }

    // Rough concrete floor: perspective joints plus aggregate highlights.
    ctx.strokeStyle = 'rgba(114, 121, 122, .13)';
    for (let i = -12; i <= 12; i++) {
      const x = cx + i * 82;
      ctx.beginPath(); ctx.moveTo(cx, horizon); ctx.lineTo(x, h); ctx.stroke();
    }
    for (let i = 1; i <= 12; i++) {
      const t = i / 12;
      const y = horizon + (h - horizon) * t * t;
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
    }
    for (let i = 0; i < 145; i++) {
      const yT = ((i * 29.71) % 100) / 100;
      const y = horizon + (h - horizon) * Math.pow(yT, .72);
      const x = (i * 97.13 + state.yaw * (1 + yT * 3)) % (w + 20) - 10;
      ctx.fillStyle = i % 3 ? 'rgba(210,215,211,.045)' : 'rgba(0,0,0,.13)';
      ctx.fillRect(x, y, 1 + i % 3, 1);
    }

    // Ceiling strip-lights reflected softly on the back wall.
    const lightX = w * .5 - state.yaw * 3.5;
    const glow = ctx.createRadialGradient(lightX, horizon * .18, 5, lightX, horizon * .18, w * .48);
    glow.addColorStop(0, 'rgba(224,235,226,.14)'); glow.addColorStop(1, 'transparent');
    ctx.fillStyle = glow; ctx.fillRect(0, 0, w, horizon);
    ctx.fillStyle = 'rgba(226,238,230,.34)';
    ctx.fillRect(lightX - 95, 14 + state.pitch * .7, 190, 3);

    // Workbench in front of the player, with a thick top and steel legs.
    const tableY = Math.min(h - 82, horizon + (h - horizon) * .5);
    const tableOffset = -state.yaw * 2.1;
    ctx.fillStyle = '#24282a';
    ctx.beginPath();
    ctx.moveTo(w * .28 + tableOffset, tableY);
    ctx.lineTo(w * .72 + tableOffset, tableY);
    ctx.lineTo(w * .79 + tableOffset, tableY + 42);
    ctx.lineTo(w * .21 + tableOffset, tableY + 42);
    ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#111416'; ctx.fillRect(w * .21 + tableOffset, tableY + 42, w * .58, 16);
    ctx.fillStyle = 'rgba(255,255,255,.08)';
    ctx.beginPath(); ctx.moveTo(w * .28 + tableOffset, tableY); ctx.lineTo(w * .72 + tableOffset, tableY); ctx.lineTo(w * .735 + tableOffset, tableY + 5); ctx.lineTo(w * .27 + tableOffset, tableY + 5); ctx.fill();
    ctx.fillStyle = '#171a1c';
    ctx.fillRect(w * .25 + tableOffset, tableY + 56, 17, h - tableY);
    ctx.fillRect(w * .72 + tableOffset, tableY + 56, 17, h - tableY);
    ctx.fillStyle = 'rgba(66,232,224,.22)'; ctx.fillRect(w * .21 + tableOffset, tableY + 57, w * .58, 1);
  }

  function drawWeapon(w, h, dt) {
    state.recoil = Math.max(0, state.recoil - dt * 7.5);
    state.muzzleFlash = Math.max(0, state.muzzleFlash - dt * 15);
    const kick = Math.sin(state.recoil * Math.PI) * 18;
    const sway = state.running && !state.paused ? Math.sin(performance.now() / 480) * 1.4 : 0;
    ctx.save();
    // Placement follows a classic FPS view model: raised on the right, muzzle
    // reaching toward the lower-right side of the crosshair.
    ctx.translate(w - 42, h - 76 - kick + sway);
    ctx.rotate(-.075 - state.recoil * .055);
    ctx.scale(1.12, 1.12);

    if (state.muzzleFlash > 0) {
      const alpha = state.muzzleFlash;
      const flare = ctx.createRadialGradient(-282, -78, 1, -282, -78, 46);
      flare.addColorStop(0, `rgba(255,255,235,${alpha})`);
      flare.addColorStop(.22, `rgba(255,174,42,${alpha * .9})`);
      flare.addColorStop(1, 'rgba(255,92,15,0)');
      ctx.fillStyle = flare; ctx.beginPath(); ctx.arc(-282, -78, 46, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = `rgba(255,225,125,${alpha})`;
      ctx.beginPath(); ctx.moveTo(-280,-78); ctx.lineTo(-326,-91); ctx.lineTo(-298,-77); ctx.lineTo(-322,-59); ctx.closePath(); ctx.fill();
    }

    // Suppressor, slide, frame and grip.
    let metal = ctx.createLinearGradient(0, -105, 0, -42);
    metal.addColorStop(0, '#f4f3ea'); metal.addColorStop(.34, '#d8d9d3'); metal.addColorStop(.72, '#9da3a3'); metal.addColorStop(1, '#343a3c');
    ctx.fillStyle = metal;
    ctx.beginPath(); ctx.roundRect(-284, -89, 162, 22, 7); ctx.fill();
    ctx.fillStyle = '#24292b'; ctx.fillRect(-277, -84, 142, 4);
    ctx.fillStyle = '#8dd744';
    ctx.beginPath(); ctx.moveTo(-238,-89); ctx.lineTo(-215,-67); ctx.lineTo(-226,-67); ctx.lineTo(-245,-86); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#ef4a39'; ctx.fillRect(-190, -87, 17, 4);
    for (let x = -145; x < -126; x += 5) ctx.fillRect(x, -89, 2, 22);
    ctx.fillStyle = metal;
    ctx.beginPath(); ctx.roundRect(-128, -98, 120, 38, 5); ctx.fill();
    ctx.fillStyle = '#080a0b'; ctx.fillRect(-115, -64, 104, 9);
    ctx.fillStyle = 'rgba(255,255,255,.12)'; ctx.fillRect(-117, -94, 91, 2);
    // Bright geometric skin accents, intentionally generic rather than a copied skin.
    ctx.fillStyle = '#ff513d';
    ctx.beginPath(); ctx.moveTo(-101,-95); ctx.lineTo(-79,-61); ctx.lineTo(-92,-61); ctx.lineTo(-112,-91); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#f4c63e';
    ctx.beginPath(); ctx.moveTo(-91,-93); ctx.lineTo(-72,-65); ctx.lineTo(-82,-63); ctx.lineTo(-101,-91); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#5fd34e';
    ctx.beginPath(); ctx.moveTo(-69,-96); ctx.lineTo(-49,-62); ctx.lineTo(-58,-61); ctx.lineTo(-80,-92); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#15191a'; ctx.fillRect(-19, -89, 9, 20);
    for (let x = -49; x < -21; x += 6) ctx.fillRect(x, -98, 2, 20);

    ctx.fillStyle = '#171b1d';
    ctx.beginPath(); ctx.moveTo(-99,-58); ctx.lineTo(-24,-58); ctx.lineTo(-9,-21); ctx.lineTo(-38,-9); ctx.lineTo(-67,-36); ctx.lineTo(-103,-39); ctx.closePath(); ctx.fill();
    ctx.strokeStyle = '#555d61'; ctx.lineWidth = 2; ctx.stroke();
    ctx.fillStyle = '#0d1011';
    ctx.beginPath(); ctx.moveTo(-43,-24); ctx.lineTo(-5,38); ctx.lineTo(-41,57); ctx.lineTo(-73,-13); ctx.closePath(); ctx.fill();
    ctx.strokeStyle = '#3d4447'; ctx.stroke();
    ctx.strokeStyle = 'rgba(255,255,255,.12)';
    for (let y = -10; y < 38; y += 7) { ctx.beginPath(); ctx.moveTo(-57,y); ctx.lineTo(-22,y+17); ctx.stroke(); }
    ctx.fillStyle = '#080a0b'; ctx.beginPath(); ctx.ellipse(-73,-42,15,19,0,0,Math.PI*2); ctx.fill();

    // Gloved firing hand.
    ctx.fillStyle = '#303a3d';
    ctx.beginPath(); ctx.ellipse(-16, 49, 48, 38, -.35, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#1b2325'; ctx.beginPath(); ctx.ellipse(-57, 5, 17, 38, -.3, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  }

  function drawTarget(t) {
    const p = project(t.yaw, t.pitch, t.depth);
    if (!p.visible || p.x < -p.radius || p.x > canvas.clientWidth + p.radius || p.y < -p.radius || p.y > canvas.clientHeight + p.radius) return;
    const pulse = 1 + Math.sin(performance.now() / 350 + t.pulse) * .035;
    const r = p.radius * pulse;
    ctx.save();
    ctx.shadowColor = settings.color;
    ctx.shadowBlur = 24;
    const g = ctx.createRadialGradient(p.x - r * .28, p.y - r * .32, r * .06, p.x, p.y, r);
    g.addColorStop(0, '#ffffff');
    g.addColorStop(.12, settings.color);
    g.addColorStop(.67, settings.color);
    g.addColorStop(1, shade(settings.color, -55));
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(p.x, p.y, r, 0, Math.PI * 2); ctx.fill();
    ctx.shadowBlur = 0;
    ctx.strokeStyle = 'rgba(255,255,255,.35)'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.arc(p.x, p.y, r + 5, 0, Math.PI * 2); ctx.stroke();
    ctx.restore();
  }

  function shade(hex, amount) {
    const n = parseInt(hex.slice(1), 16);
    const r = Math.max(0, Math.min(255, (n >> 16) + amount));
    const g = Math.max(0, Math.min(255, ((n >> 8) & 255) + amount));
    const b = Math.max(0, Math.min(255, (n & 255) + amount));
    return `rgb(${r},${g},${b})`;
  }

  function drawParticles(dt) {
    state.particles = state.particles.filter(p => p.life > 0);
    ctx.fillStyle = settings.color;
    state.particles.forEach(p => {
      p.life -= dt * 2.2; p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= .97; p.vy *= .97;
      ctx.globalAlpha = Math.max(0, p.life); ctx.fillRect(p.x, p.y, p.size, p.size);
    });
    ctx.globalAlpha = 1;
  }

  function loop(now) {
    const dt = Math.min((now - (state.lastTime || now)) / 1000, .05);
    state.lastTime = now;
    const w = canvas.clientWidth, h = canvas.clientHeight;
    const viewSmoothing = 1 - Math.exp(-dt * 55);
    state.yaw += (state.aimYaw - state.yaw) * viewSmoothing;
    state.pitch += (state.aimPitch - state.pitch) * viewSmoothing;
    drawRoom(w, h);
    if (state.target && !state.ended) drawTarget(state.target);
    drawParticles(dt);
    drawWeapon(w, h, dt);
    if (state.flash > 0) {
      state.flash -= dt * 8;
      ctx.fillStyle = `rgba(255,255,255,${Math.max(0,state.flash) * .07})`;
      ctx.fillRect(0, 0, w, h);
    }
    if (state.running && !state.paused) {
      state.timeLeft -= dt;
      state.timerAccumulator += dt;
      if (state.timerAccumulator >= .1) { state.timerAccumulator = 0; updateHud(); }
      if (state.timeLeft <= 0) { state.timeLeft = 0; updateHud(); endGame(); }
    }
    requestAnimationFrame(loop);
  }

  loadSettings();
  bindRange('sensitivity', v => v.toFixed(2), v => $('#edpi').textContent = `${Math.round(v * 800)} eDPI`);
  bindRange('fov', v => `${v}°`);
  bindRange('targetSize', sizeLabel);
  $('#bestScore').textContent = (+localStorage.getItem('voidAimBest') || 0).toLocaleString();

  startButton.addEventListener('click', startGame);
  wrap.addEventListener('click', e => {
    if (state.paused && !overlay.contains(e.target)) startGame();
    else if (document.pointerLockElement === canvas) shoot();
  });
  document.addEventListener('mousemove', e => {
    if (document.pointerLockElement !== canvas || !state.running || state.paused) return;
    if (state.pointerWarmup > 0) { state.pointerWarmup--; return; }
    const scale = settings.sensitivity * .045;
    // Some browsers emit one huge delta when pointer lock starts; cap that spike.
    const dx = Math.max(-100, Math.min(100, e.movementX));
    const dy = Math.max(-100, Math.min(100, e.movementY));
    state.aimYaw += dx * scale;
    state.aimPitch = Math.max(-42, Math.min(42, state.aimPitch - dy * scale));
  });
  document.addEventListener('pointerlockchange', () => {
    if (document.pointerLockElement === canvas) {
      state.pointerWarmup = 2;
      state.aimYaw = state.yaw;
      state.aimPitch = state.pitch;
    } else if (state.running && !state.ended) pauseGame();
  });
  document.addEventListener('keydown', e => {
    if (e.code === 'Space' && !state.running) { e.preventDefault(); startGame(); }
  });
  window.addEventListener('resize', resize);

  $$('#duration button').forEach(button => button.addEventListener('click', () => {
    settings.duration = +button.dataset.value;
    state.timeLeft = settings.duration;
    $$('#duration button').forEach(b => b.classList.toggle('active', b === button));
    $('#durationValue').textContent = `${settings.duration} 秒`;
    updateHud(); saveSettings();
  }));
  $$('.color').forEach(button => button.addEventListener('click', () => {
    settings.color = button.dataset.color;
    $$('.color').forEach(b => b.classList.toggle('active', b === button));
    saveSettings();
  }));
  $('#soundToggle').addEventListener('click', e => {
    settings.sound = !settings.sound;
    e.currentTarget.classList.toggle('muted', !settings.sound);
    e.currentTarget.setAttribute('aria-label', settings.sound ? '关闭音效' : '开启音效');
    saveSettings();
  });
  $('#resetSettings').addEventListener('click', () => {
    $('#sensitivity').value = 1; $('#fov').value = 90; $('#targetSize').value = 34;
    ['sensitivity','fov','targetSize'].forEach(id => $(`#${id}`).dispatchEvent(new Event('input')));
    const thirty = $('#duration button[data-value="30"]'); thirty.click();
    $$('.color')[0].click(); showToast('训练参数已重置');
  });
  $$('.nav-item').forEach(button => button.addEventListener('click', () => {
    if (button.dataset.view !== 'train') showToast(button.dataset.view === 'stats' ? '数据会在完成训练后自动记录' : '训练设置已在右侧展开');
    $$('.nav-item').forEach(b => b.classList.toggle('active', b === button));
    setTimeout(() => { if (button.dataset.view !== 'train') { $$('.nav-item').forEach(b => b.classList.toggle('active', b.dataset.view === 'train')); } }, 700);
  }));

  resize();
  updateHud();
  requestAnimationFrame(loop);
})();
