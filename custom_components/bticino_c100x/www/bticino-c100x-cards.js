// config: name, icon, color, tap_action, entity
class IntercomButton extends HTMLElement {
  setConfig(c) {
    this._c = c || {};
    this._phase = 'idle';
    const ms = c.busy_time || 1500;
    if (!this.shadowRoot) this.attachShadow({ mode: 'open' });
    this.shadowRoot.innerHTML = `
      <style>
        :host { display: block; }
        .b {
          position: relative; overflow: hidden;
          box-sizing: border-box; height: 100%; min-height: 78px;
          display: flex; align-items: center; justify-content: center; padding: 12px 6px;
          cursor: pointer;
          background: var(--ha-card-background, var(--card-background-color, #1c1c1c));
          border-radius: var(--ha-card-border-radius, 12px);
          border: var(--ha-card-border-width, 1px) solid
                  var(--ha-card-border-color, var(--divider-color, rgba(127,127,127,.25)));
          box-shadow: var(--ha-card-box-shadow, none);
          -webkit-tap-highlight-color: transparent; user-select: none;
          transition: transform .08s ease;
          --busy-color: ${c.busy_color || '#f2b705'};
        }
        .b::before {
          content: ''; position: absolute; inset: 0; border-radius: inherit;
          background: var(--primary-text-color, #fff); opacity: 0;
          transition: opacity .15s ease; pointer-events: none; z-index: 0;
        }
        @media (hover: hover) {
          .b:hover:not(.busy):not(.noint):not(.done)::before { opacity: .06; }
        }
        .content {
          position: relative; z-index: 1;
          display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
          color: var(--secondary-text-color, #9aa0a6);
          transition: color .15s ease, opacity .15s ease;
        }
        ha-icon { --mdc-icon-size: 27px; color: inherit; }
        .lbl { font-size: 12.5px; font-weight: 500; line-height: 1; text-align: center; color: inherit; }

        .b.on.green .content { color: #35c25e; }
        .b.on.red   .content { color: #ff5b60; }
        .b.on.amber .content { color: #f2b705; }
        .b.on.blue  .content { color: #5b9bff; }
        .b.on.white .content { color: var(--primary-text-color, #ffffff); }

        .b:active:not(.busy):not(.noint):not(.done) { transform: scale(.92); }
        .b.blink .content { animation: blink 1s ease-in-out infinite; }
        .b.noint { pointer-events: none; }
        .b.noint .content { opacity: .45; }
        .b.disabled .content { color: var(--disabled-text-color, #5b5b5b); }
        .b.busy { pointer-events: none; }
        .b.busy .content { opacity: .7; }
        .b.done { pointer-events: none; }
        .b.done .content { animation: donepop .5s ease; }

        .bar { position: absolute; left: 0; bottom: 0; height: 3px; width: 0;
               background: var(--busy-color); opacity: 0; z-index: 1; }
        .b.busy .bar { opacity: 1; }
        .b.busy.det   .bar { animation: fill ${ms}ms linear forwards; }   .b.busy.indet .bar { width: 35%; animation: slide 1.1s ease-in-out infinite; } .b.done .bar { opacity: 1; width: 100%; animation: none; }

        @keyframes blink   { 0%,100% { opacity: 1; } 50% { opacity: .16; } }
        @keyframes fill    { from { width: 0; } to { width: 100%; } }
        @keyframes slide   { 0% { left: -35%; } 100% { left: 100%; } }
        @keyframes donepop { 0% { transform: scale(1); } 45% { transform: scale(1.2); } 100% { transform: scale(1); } }
      </style>
      <div class="b ${c.color || ''}">
        <div class="content"><ha-icon icon="${c.icon || ''}"></ha-icon><div class="lbl">${c.name || ''}</div></div>
        <div class="bar"></div>
      </div>`;
    this._el = this.shadowRoot.querySelector('.b');
    this._el.onclick = () => this._tap();
    if (this._hass) this._render();
  }
  _st(e) { return e && this._hass.states[e] ? this._hass.states[e].state : null; }
  _on(e) { return this._st(e) === 'on'; }
  _enabled() { return this._c.enabled_entity ? this._on(this._c.enabled_entity) : true; }

  _tap() {
    if (this._phase !== 'idle' || !this._enabled() || !this._hass) return;
    const t = this._c.tap_action;
    if (t && t.service) { const [d, s] = t.service.split('.'); if (d && s) this._hass.callService(d, s, t.data || {}); }
    this._phase = 'busy';
    this._apply();
    clearTimeout(this._tm);
    const wait = (this._c.done_on || this._c.done_off) ? 20000 : (this._c.busy_time || 1500);
    this._tm = setTimeout(() => this._toDone(), wait);
  }
  _toDone() {
    if (this._phase !== 'busy') return;
    clearTimeout(this._tm);
    this._phase = 'done';
    this._apply();
    clearTimeout(this._tm2);
    this._tm2 = setTimeout(() => { this._phase = 'idle'; this._apply(); }, 550);
  }
  set hass(h) { this._hass = h; this._render(); }
  _render() {
    if (!this._el || !this._hass) return;
    const c = this._c;
    if (this._phase === 'busy') {
      if ((c.done_on && this._on(c.done_on)) || (c.done_off && this._st(c.done_off) === 'off')) {
        this._toDone();
        return;
      }
    }
    this._apply();
  }
  _apply() {
    const c = this._c, el = this._el;
    const on = c.entity ? this._on(c.entity) : true;
    const enabled = this._enabled();
    const idle = this._phase === 'idle';
    const busy = this._phase === 'busy';
    const notPressable = idle && !enabled;
    el.classList.toggle('on', on);
    el.classList.toggle('blink', idle && enabled && !!c.blink_entity && this._on(c.blink_entity));
    el.classList.toggle('busy', busy);
    el.classList.toggle('det',   busy && !(c.done_on || c.done_off));
    el.classList.toggle('indet', busy && !!(c.done_on || c.done_off));
    el.classList.toggle('done', this._phase === 'done');
    el.classList.toggle('noint', notPressable);
    el.classList.toggle('disabled', notPressable && !on);
  }
  getCardSize() { return 1; }
}
customElements.define('intercom-button', IntercomButton);
window.customCards = window.customCards || [];
window.customCards.push({ type: 'intercom-button', name: 'Intercom Button', description: 'An intercom button with four states and a progress bar' });

// config: url, connect_entity, talk_entity, controls
class IntercomVideo extends HTMLElement {
  setConfig(c) {
    this._c = c || {};
    if (!this.shadowRoot) this.attachShadow({ mode: 'open' });
    this.shadowRoot.innerHTML = `
      <style>
        :host { display: block; }
        .wrap { position: relative; width: 100%; aspect-ratio: 4 / 3; overflow: hidden;
                background: #000; border-radius: var(--ha-card-border-radius, 12px); }
        video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover;
                background: #000; }
        video[hidden] { display: none; }
        .badge { position: absolute; top: 10px; left: 10px; z-index: 3;
                 display: none; align-items: center; gap: 6px;
                 padding: 5px 10px; border-radius: 999px;
                 background: rgba(0,0,0,.55); backdrop-filter: blur(4px);
                 color: #fff; font-size: 12px; font-weight: 500; letter-spacing: .2px;
                 pointer-events: none; }
        .badge.visible { display: inline-flex; }
        .badge ha-icon { --mdc-icon-size: 15px; }
        .dot { width: 8px; height: 8px; border-radius: 50%; background: #ff3b30;
               animation: pulse 1.4s ease-in-out infinite; }
        .badge.video-only .dot { display: none; }
        .badge.talking { background: rgba(180,0,0,.6); }
        @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: .25; } }
      </style>
      <div class="wrap">
        <video autoplay playsinline muted${this._c.controls === true ? ' controls' : ''}></video>
        <div class="badge video-only">
          <span class="dot"></span>
          <ha-icon icon="mdi:microphone-off"></ha-icon>
          <span class="txt">Live</span>
        </div>
      </div>`;
    this._video = this.shadowRoot.querySelector('video');
    this._video.hidden = true;
    this._badge = this.shadowRoot.querySelector('.badge');
    this._video.addEventListener('click', () => {
      if (this._video.muted) {
        this._video.muted = false;
        const r = this._video.play(); if (r && r.catch) r.catch(() => {});
      }
    });
    this._unlockAudio();
    this._observe();
  }

  set hass(h) {
    this._hass = h;
    const st = (e) => (e && h.states[e] ? h.states[e].state : null);
    this._wanted = this._c.connect_entity ? st(this._c.connect_entity) === 'on' : true;
    this._withMic = this._c.talk_entity ? st(this._c.talk_entity) === 'on' : false;
    this._converge();
  }

  _unlockAudio() {
    const prime = () => {
      try {
        if (!this._video.srcObject) this._video.srcObject = new MediaStream();
        const r = this._video.play();
        if (r && r.catch) r.catch(() => {});
        this._unlocked = true;
      } catch (e) {}
    };
    document.addEventListener('pointerdown', prime, { capture: true, once: true });
    document.addEventListener('touchstart', prime, { capture: true, once: true });
  }

  _paintBadge() {
    if (!this._badge) return;
    const hasVideo = !!(this._video && !this._video.hidden);
    const mic = !!this._micAttached;
    this._badge.classList.toggle('visible', hasVideo);
    this._badge.classList.toggle('talking', mic);
    this._badge.classList.toggle('video-only', !mic);
    const icon = this._badge.querySelector('ha-icon');
    const text = this._badge.querySelector('.txt');
    if (icon) icon.setAttribute('icon', mic ? 'mdi:microphone' : 'mdi:microphone-off');
    if (text) text.textContent = mic ? 'Mic open' : 'Live';
  }

  _converge() {
    const should = !!(this._visible && this._wanted && this._hass && this._c);
    if (!should) { this._cancelRetry(); if (this._pc || this._ws) this._stop(); return; }
    if (this._retryPending) return;
    if (!this._pc && !this._started) { this._start(); return; }
    if (this._started && this._micAttached !== this._withMic) this._attachMic(this._withMic);
  }

  _observe() {
    if (this._io) return;
    this._io = new IntersectionObserver((entries) => {
      const vis = entries.some(e => e.isIntersecting);
      if (vis === this._visible) return;
      this._visible = vis;
      this._converge();
    }, { threshold: 0.01 });
    this._io.observe(this);
  }

  async _start() {
    const src = (this._c && this._c.url) || 'camera.door';
    if (!this._hass || this._started || !this._visible || !this._wanted) return;
    this._started = true;
    let wsUrl;
    try {
      const path = '/api/bticino_c100x/ws?src=' + encodeURIComponent(src);
      const signed = await this._hass.callWS({ type: 'auth/sign_path', path });
      wsUrl = 'ws' + this._hass.hassUrl(signed.path).substring(4);
    } catch (e) { this._started = false; return; }

    const pc = new RTCPeerConnection({ iceServers: [], bundlePolicy: 'max-bundle' });
    this._pc = pc;
    const stream = new MediaStream();
    pc.ontrack = (ev) => {
      stream.addTrack(ev.track);
      if (this._video.srcObject !== stream) this._video.srcObject = stream;
      if (ev.track.kind !== 'video') return;
      this._hasPicture = true;
      this._attempts = 0;
      clearTimeout(this._watchdog); this._watchdog = null;
      this._video.hidden = false;
      this._paintBadge();
      this._reportPicture(true);
      const v = this._video;
      const p = v.play();
      const withSound = () => {
        v.addEventListener('pause', () => { v.muted = true; const r = v.play(); if (r && r.catch) r.catch(() => {}); }, { once: true });
        v.muted = false;
      };
      if (p && p.then) p.then(withSound).catch(() => {}); else withSound();
    };

    const micTr = pc.addTransceiver('audio', { direction: 'sendonly' });
    this._micSender = micTr.sender;
    this._micAttached = false;
    try {
      const caps = RTCRtpSender.getCapabilities('audio');
      if (caps && caps.codecs && micTr.setCodecPreferences) {
        const pcma = caps.codecs.filter(c => /PCMA|PCMU/i.test(c.mimeType));
        const rest = caps.codecs.filter(c => !/PCMA|PCMU/i.test(c.mimeType));
        if (pcma.length) micTr.setCodecPreferences(pcma.concat(rest));
      }
    } catch (e) {}
    pc.addTransceiver('video', { direction: 'recvonly' });
    pc.addTransceiver('audio', { direction: 'recvonly' });

    const ws = new WebSocket(wsUrl);
    this._ws = ws;

    pc.onicecandidate = (ev) => {
      if (ev.candidate && ws.readyState === 1) {
        ws.send(JSON.stringify({ type: 'webrtc/candidate', value: ev.candidate.candidate }));
      }
    };
    ws.onopen = async () => {
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      ws.send(JSON.stringify({ type: 'webrtc/offer', value: pc.localDescription.sdp }));
      if (this._withMic) this._attachMic(true);
    };
    ws.onmessage = async (ev) => {
      let msg; try { msg = JSON.parse(ev.data); } catch (e) { return; }
      if (msg.type === 'webrtc/answer') {
        const sdp = msg.value || '';
        const secVideo = sdp.split(/^m=/m).find(x => x.startsWith('video'));
        const videoOk = !!(secVideo && /a=rtpmap:\s*\d+\s+H26[45]/i.test(secVideo));
        if (!videoOk) {
          console.warn('intercom-video: the answer carried no video codec, retrying', this._attempts);
          this._scheduleRetry();
          return;
        }
        await pc.setRemoteDescription({ type: 'answer', sdp: msg.value });
      } else if (msg.type === 'webrtc/candidate' && msg.value) {
        try { await pc.addIceCandidate({ candidate: msg.value, sdpMid: '0' }); } catch (e) {}
      }
    };
    ws.onclose = () => { this._ws = null; };

    clearTimeout(this._watchdog);
    this._watchdog = setTimeout(() => {
      this._watchdog = null;
      if (!this._hasPicture) {
        console.warn('intercom-video: twelve seconds with no picture, retrying', this._attempts);
        this._scheduleRetry();
      }
    }, 12000);

    clearInterval(this._chk);
    this._chk = setInterval(() => {
      const vis = this.isConnected && this.offsetParent !== null;
      if (vis !== this._visible) { this._visible = vis; this._converge(); }
    }, 1000);
  }

  _scheduleRetry() {
    if (this._retryPending) return;
    this._retryPending = true;
    this._stop();
    const DELAYS = [0, 2000, 5000, 10000, 15000];
    const ms = DELAYS[Math.min(this._attempts || 0, DELAYS.length - 1)];
    this._attempts = (this._attempts || 0) + 1;
    clearTimeout(this._retryTimer);
    this._retryTimer = setTimeout(() => {
      this._retryTimer = null;
      this._retryPending = false;
      this._converge();
    }, ms);
  }

  _cancelRetry() {
    clearTimeout(this._retryTimer); this._retryTimer = null;
    this._retryPending = false;
    this._attempts = 0;
  }

  async _attachMic(on) {
    if (!this._micSender || this._micAttached === on) return;
    if (this._requestingMic) return;
    this._requestingMic = true;
    try {
    if (on) {
      try {
        const st = await navigator.mediaDevices.getUserMedia({ audio: true });
        if (!this._withMic || !this._micSender) {
          st.getTracks().forEach(t => t.stop());
          this._setMicState('off');
          return;
        }
        this._micStream = st;
        const track = st.getAudioTracks()[0];
        await this._micSender.replaceTrack(track);
        this._micAttached = true;
        this._paintBadge();
        if (this._video) {
          this._video.muted = false;
          const r = this._video.play(); if (r && r.catch) r.catch(() => {});
        }
        this._setMicState('on:' + ((track && track.label) || 'unnamed').slice(0, 40));
      } catch (e) {
        console.error('intercom-video: microphone unavailable ->', e && e.name, e && e.message);
        this._setMicState('ERROR ' + (e && e.name) + ' | secure=' + window.isSecureContext);
      }
    } else {
      try { await this._micSender.replaceTrack(null); } catch (e) {}
      if (this._micStream) { this._micStream.getTracks().forEach(t => t.stop()); this._micStream = null; }
      this._micAttached = false;
      this._paintBadge();
      this._setMicState('off');
    }
    } finally { this._requestingMic = false; }
  }

  _reportPicture(showing) {
    if (this._pictureReported === showing || !this._hass) return;
    this._pictureReported = showing;
    try {
      this._hass.callService('bticino_c100x', 'video_on_screen', { value: showing });
    } catch (e) {}
  }

  _setMicState(v) {
    this._mic = v;
    this.setAttribute('mic', v);
    try {
      if (this._hass) this._hass.callService('bticino_c100x', 'microphone_state',
        { value: String(v).slice(0, 120) });
    } catch (e) {}
  }

  _stop() {
    clearInterval(this._chk); this._chk = null;
    clearTimeout(this._watchdog); this._watchdog = null;
    this._hasPicture = false;
    if (this._micStream) { this._micStream.getTracks().forEach(t => t.stop()); this._micStream = null; }
    if (this._pc) {
      try { this._pc.getSenders().forEach(s => { if (s.track) s.track.stop(); }); } catch (e) {}
    }
    if (this._micSender) { try { this._micSender.replaceTrack(null); } catch (e) {} }
    this._micSender = null; this._micAttached = false;
    if (this._ws) { try { this._ws.close(); } catch (e) {} this._ws = null; }
    if (this._pc) { try { this._pc.close(); } catch (e) {} this._pc = null; }
    if (this._video) { this._video.srcObject = null; this._video.hidden = true; }
    this._paintBadge();
    this._reportPicture(false);
    this._started = false;
  }

  connectedCallback() { this._observe(); }
  disconnectedCallback() { if (this._io) { this._io.disconnect(); this._io = null; } this._visible = false; this._cancelRetry(); this._stop(); }
  getCardSize() { return 4; }
}
customElements.define('intercom-video', IntercomVideo);
window.customCards.push({ type: 'intercom-video', name: 'Intercom Video', description: 'The intercom video, with the loading centred' });

// The card ships its keys in English only; translating is the dashboard's
// job, by providing values for these keys under the card's `labels` option.
// Dates and times already follow the instance's language on their own.
const CALL_LOG_TEXT = {
  answered: 'Answered', missed: 'Missed',
  opened: 'Door opened', not_opened: 'Door not opened',
  today: 'Today', yesterday: 'Yesterday', empty: 'No calls yet',
};

// config: limit, labels (any CALL_LOG_TEXT key, e.g. labels: {missed: Manquée})
class IntercomCallLog extends HTMLElement {
  setConfig(c) {
    this._c = c || {};
    this._t = Object.assign({}, CALL_LOG_TEXT, this._c.labels || {});
    if (!this.shadowRoot) this.attachShadow({ mode: 'open' });
    this.shadowRoot.innerHTML = `
      <style>
        :host { display: block; }
        [hidden] { display: none !important; }
        .card {
          box-sizing: border-box; overflow: hidden;
          background: var(--ha-card-background, var(--card-background-color, #1c1c1c));
          border-radius: var(--ha-card-border-radius, 12px);
          border: var(--ha-card-border-width, 1px) solid
                  var(--ha-card-border-color, var(--divider-color, rgba(127,127,127,.25)));
          box-shadow: var(--ha-card-box-shadow, none);
        }
        .row {
          display: flex; align-items: center; gap: 12px; padding: 9px 16px;
          cursor: pointer; -webkit-tap-highlight-color: transparent; user-select: none;
          transition: background .12s ease;
        }
        .row + .row { border-top: 1px solid var(--divider-color, rgba(127,127,127,.2)); }
        @media (hover: hover) { .row:hover { background: rgba(127,127,127,.08); } }
        .thumb, .noface {
          width: 44px; height: 44px; border-radius: 50%; flex: none;
          object-fit: cover; background: rgba(127,127,127,.15);
        }
        .noface { display: flex; align-items: center; justify-content: center;
                  color: var(--secondary-text-color, #9aa0a6); }
        .noface ha-icon { --mdc-icon-size: 24px; }
        .mid { flex: 1; min-width: 0; }
        .status { display: flex; align-items: center; gap: 6px;
                  font-size: 13.5px; font-weight: 500;
                  color: var(--primary-text-color, #fff); }
        .status ha-icon { --mdc-icon-size: 16px; color: #35c25e; }
        .row.missed .status, .row.missed .status ha-icon { color: #ff5b60; }
        .when { font-size: 12px; margin-top: 2px; color: var(--secondary-text-color, #9aa0a6); }
        .side { display: flex; align-items: center; gap: 6px; flex: none;
                color: var(--secondary-text-color, #9aa0a6); }
        .side .door { color: #35c25e; --mdc-icon-size: 18px; }
        .side .door-off { --mdc-icon-size: 18px; opacity: .35; }
        .side .chev { --mdc-icon-size: 20px; opacity: .6; }
        .empty { padding: 22px 16px; text-align: center; font-size: 13px;
                 color: var(--secondary-text-color, #9aa0a6); }

        .overlay { position: fixed; inset: 0; z-index: 999;
                   background: rgba(0,0,0,.6); display: flex;
                   align-items: center; justify-content: center; padding: 16px; }
        .panel { position: relative; width: min(92vw, 480px); max-height: 90vh;
                 overflow: auto; border-radius: var(--ha-card-border-radius, 12px);
                 background: var(--ha-card-background, var(--card-background-color, #1c1c1c)); }
        .panel img { display: block; width: 100%; max-height: 70vh;
                     object-fit: contain; background: #000; }
        .panel .noimg { display: flex; align-items: center; justify-content: center;
                        height: 200px; background: rgba(127,127,127,.12);
                        color: var(--secondary-text-color, #9aa0a6); }
        .panel .noimg ha-icon { --mdc-icon-size: 72px; }
        .close { position: absolute; top: 10px; right: 10px; z-index: 1;
                 width: 36px; height: 36px; border: 0; border-radius: 50%;
                 background: rgba(0,0,0,.55); color: #fff; cursor: pointer;
                 display: flex; align-items: center; justify-content: center; }
        .close ha-icon { --mdc-icon-size: 22px; }
        .facts { padding: 14px 18px 18px; }
        .fact { display: flex; align-items: center; gap: 10px; padding: 6px 0;
                font-size: 14px; color: var(--primary-text-color, #fff); }
        .fact ha-icon { --mdc-icon-size: 19px; color: var(--secondary-text-color, #9aa0a6); }
        .fact.good ha-icon { color: #35c25e; }
        .fact.bad, .fact.bad ha-icon { color: #ff5b60; }
      </style>
      <div class="card"><div class="rows"></div></div>
      <div class="overlay" hidden>
        <div class="panel">
          <button class="close" aria-label="close"><ha-icon icon="mdi:close"></ha-icon></button>
          <img hidden><div class="noimg" hidden><ha-icon icon="mdi:account"></ha-icon></div>
          <div class="facts"></div>
        </div>
      </div>`;
    this._rows = this.shadowRoot.querySelector('.rows');
    this._overlay = this.shadowRoot.querySelector('.overlay');
    this._overlay.onclick = (e) => { if (e.target === this._overlay) this._closeDetail(); };
    this.shadowRoot.querySelector('.close').onclick = () => this._closeDetail();
    this._onKey = (e) => { if (e.key === 'Escape') this._closeDetail(); };
    if (this._calls) this._render();
  }

  set hass(h) {
    const first = !this._hass;
    this._hass = h;
    if (first) {
      this._lang = h.selectedLanguage || h.language || 'en';
      this._start();
    }
    // no render here: the card reads no entity state, so the hass churn is noise
  }

  async _start() {
    if (this._startedOnce) return;
    this._startedOnce = true;
    await this._fetch();
    this._deepLink();
    this._onHash = () => this._deepLink();
    window.addEventListener('hashchange', this._onHash);
    this._subscribe();
  }

  async _fetch() {
    if (!this._hass) return;
    try {
      const resp = await this._hass.callWS({ type: 'bticino_c100x/calls' });
      this._calls = resp.calls;
      this._render();
    } catch (e) { /* not loaded yet; the event subscription retries us */ }
  }

  async _subscribe() {
    if (this._unsub || !this._hass) return;
    this._unsub = await this._hass.connection.subscribeEvents(
      () => this._fetch(), 'bticino_c100x_call_log_updated');
    if (!this.isConnected) { this._unsub(); this._unsub = null; }
  }

  _render() {
    if (!this._rows) return;
    this._rows.textContent = '';
    const list = (this._calls || []).slice(0, this._c.limit || 10);
    if (!list.length) {
      const empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = this._t.empty;
      this._rows.appendChild(empty);
      return;
    }
    for (const call of list) this._rows.appendChild(this._row(call));
  }

  _row(call) {
    const row = document.createElement('div');
    row.className = call.answered ? 'row' : 'row missed';
    if (call.photo_url) {
      const img = document.createElement('img');
      img.className = 'thumb'; img.loading = 'lazy'; img.src = call.photo_url;
      row.appendChild(img);
    } else {
      const face = document.createElement('div');
      face.className = 'noface';
      face.innerHTML = '<ha-icon icon="mdi:account"></ha-icon>';
      row.appendChild(face);
    }
    const mid = document.createElement('div'); mid.className = 'mid';
    const status = document.createElement('div'); status.className = 'status';
    const icon = document.createElement('ha-icon');
    icon.setAttribute('icon', call.answered ? 'mdi:phone-incoming' : 'mdi:phone-missed');
    status.appendChild(icon);
    status.appendChild(document.createTextNode(call.answered ? this._t.answered : this._t.missed));
    const when = document.createElement('div'); when.className = 'when';
    when.textContent = this._when(call.ts);
    mid.appendChild(status); mid.appendChild(when);
    row.appendChild(mid);
    const side = document.createElement('div'); side.className = 'side';
    const door = document.createElement('ha-icon');
    door.className = call.door_opened ? 'door' : 'door-off';
    door.setAttribute('icon', call.door_opened ? 'mdi:door-open' : 'mdi:door-closed');
    door.setAttribute('title', call.door_opened ? this._t.opened : this._t.not_opened);
    side.appendChild(door);
    const chev = document.createElement('ha-icon');
    chev.className = 'chev'; chev.setAttribute('icon', 'mdi:chevron-right');
    side.appendChild(chev);
    row.appendChild(side);
    row.onclick = () => this._openDetail(call);
    return row;
  }

  _when(ts) {
    const d = new Date(ts);
    const time = d.toLocaleTimeString(this._lang, { hour: '2-digit', minute: '2-digit' });
    const today = new Date();
    const yesterday = new Date(today); yesterday.setDate(today.getDate() - 1);
    if (d.toDateString() === today.toDateString()) return `${this._t.today} ${time}`;
    if (d.toDateString() === yesterday.toDateString()) return `${this._t.yesterday} ${time}`;
    return `${d.toLocaleDateString(this._lang, { day: 'numeric', month: 'short' })} ${time}`;
  }

  _openDetail(call) {
    const img = this.shadowRoot.querySelector('.panel img');
    const noimg = this.shadowRoot.querySelector('.panel .noimg');
    img.hidden = !call.photo_url;
    noimg.hidden = !!call.photo_url;
    if (call.photo_url) img.src = call.photo_url;
    const facts = this.shadowRoot.querySelector('.facts');
    facts.textContent = '';
    const fact = (iconName, text, cls) => {
      const el = document.createElement('div');
      el.className = cls ? `fact ${cls}` : 'fact';
      const ic = document.createElement('ha-icon'); ic.setAttribute('icon', iconName);
      el.appendChild(ic); el.appendChild(document.createTextNode(text));
      facts.appendChild(el);
    };
    const d = new Date(call.ts);
    fact('mdi:calendar-clock', d.toLocaleString(this._lang,
      { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' }));
    fact(call.answered ? 'mdi:phone-incoming' : 'mdi:phone-missed',
      call.answered ? this._t.answered : this._t.missed, call.answered ? 'good' : 'bad');
    fact(call.door_opened ? 'mdi:door-open' : 'mdi:door-closed',
      call.door_opened ? this._t.opened : this._t.not_opened, call.door_opened ? 'good' : '');
    this._overlay.hidden = false;
    window.addEventListener('keydown', this._onKey);
  }

  _closeDetail() {
    if (this._overlay) this._overlay.hidden = true;
    window.removeEventListener('keydown', this._onKey);
  }

  _deepLink() {
    if (window.location.hash !== '#call' || !this._calls || !this._calls.length) return;
    history.replaceState(null, '', window.location.pathname + window.location.search);
    this._openDetail(this._calls[0]);
  }

  connectedCallback() {
    if (this._hass && this._startedOnce && !this._unsub) { this._fetch(); this._subscribe(); }
  }
  disconnectedCallback() {
    if (this._unsub) { this._unsub(); this._unsub = null; }
    if (this._onHash) window.removeEventListener('hashchange', this._onHash);
    this._closeDetail();
  }
  getCardSize() { return Math.min((this._c && this._c.limit) || 10, 10); }
}
customElements.define('intercom-call-log', IntercomCallLog);
window.customCards.push({ type: 'intercom-call-log', name: 'Intercom Call Log', description: 'The rings at the door, like a phone\'s call history' });
