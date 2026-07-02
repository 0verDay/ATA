// ─── Canvas ───────────────────────────────────────────────────────────────────
const canvas = document.getElementById('gameCanvas');
const ctx    = canvas.getContext('2d');

let VIEW_W = window.innerWidth;
let VIEW_H = window.innerHeight;

function resize() {
  VIEW_W = window.innerWidth;
  VIEW_H = window.innerHeight;
  canvas.width  = VIEW_W;
  canvas.height = VIEW_H;
}
resize();
window.addEventListener('resize', resize);

// ─── State machine ────────────────────────────────────────────────────────────
const GS = { LOBBY: 'LOBBY', RAID: 'RAID', RESULT: 'RESULT' };
let gameState = GS.LOBBY;
let resultData = null;

function switchToRaid()  { gameState = GS.RAID;   initRaid(); }
function switchToLobby() { gameState = GS.LOBBY; }
function switchToResult(success, placedItems) {
  gameState  = GS.RESULT;
  const items      = placedItems.map(i => ({ name: i.type.name, value: i.type.value, color: i.type.color }));
  const totalValue = items.reduce((s, i) => s + i.value, 0);
  resultData = { success, items, totalValue };
}

// ─── Input ────────────────────────────────────────────────────────────────────
const keys  = {};
const mouse = { x: 0, y: 0, down: false };

window.addEventListener('keydown', e => { keys[e.key] = true; });
window.addEventListener('keyup',   e => {
  keys[e.key] = false;
  keys[e.key.toLowerCase()] = false;
  keys[e.key.toUpperCase()] = false;
});
window.addEventListener('mousemove',  e => { mouse.x = e.clientX; mouse.y = e.clientY; });
window.addEventListener('mousedown',  e => { if (e.button === 0) mouse.down = true;  });
window.addEventListener('mouseup',    e => { if (e.button === 0) mouse.down = false; });

canvas.addEventListener('click', e => {
  if      (gameState === GS.LOBBY)  handleLobbyClick(e.clientX, e.clientY);
  else if (gameState === GS.RAID)   handleRaidClick(e.clientX, e.clientY);
  else if (gameState === GS.RESULT) switchToLobby();
});

// ─── Result screen ────────────────────────────────────────────────────────────
function renderResult() {
  const { success, items, totalValue } = resultData;
  ctx.save();

  ctx.fillStyle = 'rgba(0,0,0,0.90)';
  ctx.fillRect(0, 0, VIEW_W, VIEW_H);

  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.font      = 'bold 48px monospace';
  ctx.fillStyle = success ? '#ffffff' : '#444444';
  ctx.shadowColor = success ? '#ffffff' : 'transparent';
  ctx.shadowBlur  = success ? 22 : 0;
  ctx.fillText(success ? '撤离成功' : '任务失败', VIEW_W / 2, VIEW_H / 2 - 120);

  ctx.shadowBlur = 0;

  // Item list
  const startY = VIEW_H / 2 - 70;
  const lineH  = 22;
  ctx.font = '14px monospace'; ctx.textAlign = 'left';
  items.forEach((item, i) => {
    const y = startY + i * lineH;
    ctx.fillStyle = item.color;
    ctx.fillRect(VIEW_W / 2 - 140, y - 7, 12, 12);
    ctx.fillStyle = '#cccccc';
    ctx.fillText(item.name, VIEW_W / 2 - 122, y);
    ctx.textAlign = 'right';
    ctx.fillStyle = '#aaaaaa';
    ctx.fillText('¥' + item.value, VIEW_W / 2 + 140, y);
    ctx.textAlign = 'left';
  });

  if (items.length === 0) {
    ctx.textAlign = 'center'; ctx.fillStyle = '#555555';
    ctx.fillText('背包为空', VIEW_W / 2, startY + lineH);
  }

  // Total
  const totalY = startY + Math.max(items.length, 1) * lineH + 18;
  ctx.textAlign = 'center';
  ctx.fillStyle = success ? '#ffffff' : '#666666';
  ctx.font      = 'bold 18px monospace';
  ctx.fillText(`总价值  ¥${totalValue}`, VIEW_W / 2, totalY);

  ctx.font = '13px monospace'; ctx.fillStyle = '#444444';
  ctx.fillText('点击任意处返回大厅', VIEW_W / 2, totalY + 44);

  ctx.restore();
}

// ─── Main loop ────────────────────────────────────────────────────────────────
let lastTime = 0;
function loop(ts) {
  const dt = Math.min((ts - lastTime) / 1000, 0.05);
  lastTime = ts;

  ctx.clearRect(0, 0, VIEW_W, VIEW_H);
  ctx.fillStyle = '#07070f';
  ctx.fillRect(0, 0, VIEW_W, VIEW_H);

  if      (gameState === GS.LOBBY)  { updateLobby(dt); renderLobby(); }
  else if (gameState === GS.RAID)   { updateRaid(dt);  renderRaid();  }
  else if (gameState === GS.RESULT) { renderResult(); }

  requestAnimationFrame(loop);
}

// Start loop only after all scripts are loaded and parsed
window.addEventListener('load', () => requestAnimationFrame(loop));
