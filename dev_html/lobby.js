// ─── Lobby constants ──────────────────────────────────────────────────────────
const LOBBY_W = 1600;
const LOBBY_H = 1200;
const BASE_X  = LOBBY_W / 2;
const BASE_Y  = LOBBY_H / 2;
const BASE_R  = 220;

// ─── Lobby player ─────────────────────────────────────────────────────────────
const lobbyPlayer = {
  x: LOBBY_W / 2,
  y: LOBBY_H / 2 + BASE_R + 120,
  r: 18, speed: 5, color: '#ffffff',
};

// ─── Letter state ─────────────────────────────────────────────────────────────
const A_REST_GAP  = 75;
const A_MAX_DRIFT = BASE_R - A_REST_GAP - 20;
const A_FAR_DIST  = 520;
const A_NEAR_GAP  = 22;
const A_LERP      = 0.04;

const letterPos = {
  aL: { x: -A_REST_GAP, y: 0 },
  aR: { x:  A_REST_GAP, y: 0 },
};

// ─── Entry button ─────────────────────────────────────────────────────────────
function _entryBtn() {
  return { x: VIEW_W / 2 - 90, y: VIEW_H - 90, w: 180, h: 44 };
}

function handleLobbyClick(cx, cy) {
  const b = _entryBtn();
  if (cx >= b.x && cx <= b.x + b.w && cy >= b.y && cy <= b.y + b.h) switchToRaid();
}

// ─── Update ───────────────────────────────────────────────────────────────────
function updateLobby(dt) {
  let dx = 0, dy = 0;
  if (keys['ArrowUp']    || keys['w'] || keys['W']) dy -= 1;
  if (keys['ArrowDown']  || keys['s'] || keys['S']) dy += 1;
  if (keys['ArrowLeft']  || keys['a'] || keys['A']) dx -= 1;
  if (keys['ArrowRight'] || keys['d'] || keys['D']) dx += 1;
  if (dx !== 0 && dy !== 0) { dx *= 0.7071; dy *= 0.7071; }

  const spd = lobbyPlayer.speed * (keys['Shift'] ? 2.2 : 1);
  lobbyPlayer.x = Math.max(lobbyPlayer.r, Math.min(LOBBY_W - lobbyPlayer.r, lobbyPlayer.x + dx * spd));
  lobbyPlayer.y = Math.max(lobbyPlayer.r, Math.min(LOBBY_H - lobbyPlayer.r, lobbyPlayer.y + dy * spd));
  _updateLetters();
}

function _updateLetters() {
  const dx   = lobbyPlayer.x - BASE_X;
  const dy   = lobbyPlayer.y - BASE_Y;
  const dist = Math.sqrt(dx * dx + dy * dy) || 0.001;
  const nx = dx / dist, ny = dy / dist;

  const ratio    = Math.min(dist / A_FAR_DIST, 1);
  const driftAmt = ratio * A_MAX_DRIFT;

  const farL  = { x: -A_REST_GAP + nx * driftAmt, y: ny * driftAmt };
  const farR  = { x:  A_REST_GAP + nx * driftAmt, y: ny * driftAmt };
  const nearL = { x: dx - A_NEAR_GAP, y: dy };
  const nearR = { x: dx + A_NEAR_GAP, y: dy };

  const ib = Math.max(0, 1 - dist / BASE_R);
  const b  = ib * ib;

  const targets = {
    aL: { x: farL.x + (nearL.x - farL.x) * b, y: farL.y + (nearL.y - farL.y) * b },
    aR: { x: farR.x + (nearR.x - farR.x) * b, y: farR.y + (nearR.y - farR.y) * b },
  };
  for (const k of ['aL', 'aR']) {
    letterPos[k].x += (targets[k].x - letterPos[k].x) * A_LERP;
    letterPos[k].y += (targets[k].y - letterPos[k].y) * A_LERP;
  }
}

// ─── Render ───────────────────────────────────────────────────────────────────
function renderLobby() {
  const camX = VIEW_W / 2 - lobbyPlayer.x;
  const camY = VIEW_H / 2 - lobbyPlayer.y;

  ctx.save();
  ctx.translate(camX, camY);
  _drawLobbyGrid();
  _drawBase();
  _drawLobbyPlayer();
  ctx.restore();

  _drawEntryButton();
}

function _drawLobbyGrid() {
  ctx.save();
  ctx.strokeStyle = '#111122';
  ctx.lineWidth = 1;
  const step = 60;
  for (let x = 0; x <= LOBBY_W; x += step) {
    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, LOBBY_H); ctx.stroke();
  }
  for (let y = 0; y <= LOBBY_H; y += step) {
    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(LOBBY_W, y); ctx.stroke();
  }
  ctx.restore();
}

function _drawBase() {
  ctx.save();

  const glowGrad = ctx.createRadialGradient(BASE_X, BASE_Y, BASE_R - 10, BASE_X, BASE_Y, BASE_R + 30);
  glowGrad.addColorStop(0,   'rgba(255,255,255,0.18)');
  glowGrad.addColorStop(0.5, 'rgba(180,180,180,0.06)');
  glowGrad.addColorStop(1,   'rgba(0,0,0,0)');
  ctx.beginPath();
  ctx.arc(BASE_X, BASE_Y, BASE_R + 30, 0, Math.PI * 2);
  ctx.fillStyle = glowGrad;
  ctx.fill();

  const baseGrad = ctx.createRadialGradient(BASE_X, BASE_Y, 0, BASE_X, BASE_Y, BASE_R);
  baseGrad.addColorStop(0,   '#0d1b2a');
  baseGrad.addColorStop(0.7, '#0a1220');
  baseGrad.addColorStop(1,   '#060d18');
  ctx.beginPath();
  ctx.arc(BASE_X, BASE_Y, BASE_R, 0, Math.PI * 2);
  ctx.fillStyle = baseGrad;
  ctx.fill();

  ctx.beginPath();
  ctx.arc(BASE_X, BASE_Y, BASE_R, 0, Math.PI * 2);
  ctx.strokeStyle = '#aaaaaa';
  ctx.lineWidth = 2.5;
  ctx.stroke();

  _drawATA(BASE_X, BASE_Y, 100);
  ctx.restore();
}

function _drawATA(cx, cy, size) {
  const h = size;
  const w = size * 0.62;

  const aCenterL = { x: cx + letterPos.aL.x, y: cy + letterPos.aL.y };
  const aCenterR = { x: cx + letterPos.aR.x, y: cy + letterPos.aR.y };
  const tCenter  = {
    x: (aCenterL.x + aCenterR.x) / 2,
    y: (aCenterL.y + aCenterR.y) / 2 - h * 0.35,
  };

  function layerSeg(x0, y0, x1, y1) {
    [[18,'rgba(255,255,255,0.08)',50],[10,'rgba(255,255,255,0.25)',25],
     [4, 'rgba(255,255,255,0.85)',10],[2, '#ffffff', 4]]
    .forEach(([lw, color, blur]) => {
      ctx.strokeStyle = color;
      ctx.lineWidth   = lw;
      ctx.shadowColor = '#ffffff';
      ctx.shadowBlur  = blur;
      ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
    });
  }

  const PUP_X = w * 0.10;
  const PUP_Y = h * 0.14;

  function drawLetterA(ac) {
    const ddx = lobbyPlayer.x - ac.x;
    const ddy = lobbyPlayer.y - ac.y;
    const dd  = Math.sqrt(ddx * ddx + ddy * ddy) || 1;
    const px  = (ddx / dd) * PUP_X;
    const py  = (ddy / dd) * PUP_Y;
    ctx.save();
    ctx.translate(ac.x, ac.y);
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    layerSeg(-w / 2, h / 2, 0, -h / 2);
    layerSeg(0, -h / 2, w / 2, h / 2);
    layerSeg(-w * 0.32 + px, h * 0.06 + py, w * 0.32 + px, h * 0.06 + py);
    ctx.restore();
  }

  function drawLetterT(tc) {
    ctx.save();
    ctx.translate(tc.x, tc.y);
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    layerSeg(-w * 0.9, -h / 2, w * 0.9, -h / 2);
    layerSeg(0, -h / 2, 0, h * 1.0);
    ctx.restore();
  }

  drawLetterA(aCenterL);
  drawLetterT(tCenter);
  drawLetterA(aCenterR);
}

function _drawLobbyPlayer() {
  const p = lobbyPlayer;
  ctx.save();

  const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r * 2.5);
  g.addColorStop(0, 'rgba(255,255,255,0.28)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.beginPath(); ctx.arc(p.x, p.y, p.r * 2.5, 0, Math.PI * 2);
  ctx.fillStyle = g; ctx.fill();

  ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
  ctx.fillStyle = '#1a1a1a'; ctx.fill();
  ctx.strokeStyle = p.color; ctx.lineWidth = 2.5;
  ctx.shadowColor = p.color; ctx.shadowBlur = 12; ctx.stroke();

  ctx.beginPath(); ctx.arc(p.x, p.y, 4, 0, Math.PI * 2);
  ctx.fillStyle = p.color; ctx.shadowBlur = 0; ctx.fill();
  ctx.restore();
}

function _drawEntryButton() {
  const b = _entryBtn();
  ctx.save();
  ctx.fillStyle   = 'rgba(255,255,255,0.06)';
  ctx.strokeStyle = 'rgba(255,255,255,0.55)';
  ctx.lineWidth   = 1;
  ctx.beginPath();
  ctx.roundRect(b.x, b.y, b.w, b.h, 5);
  ctx.fill(); ctx.stroke();

  ctx.fillStyle    = '#ffffff';
  ctx.font         = '15px monospace';
  ctx.textAlign    = 'center';
  ctx.textBaseline = 'middle';
  ctx.shadowColor  = '#ffffff';
  ctx.shadowBlur   = 10;
  ctx.fillText('进入战局', b.x + b.w / 2, b.y + b.h / 2);
  ctx.restore();
}
