// ─── Raid constants ───────────────────────────────────────────────────────────
const TILE          = 48;
const R_MAP_W       = 60;
const R_MAP_H       = 60;
const RAID_DURATION    = 90;
const CONE_HALF        = 30 * Math.PI / 180;
const ITEM_COUNT       = 20;
const EXTRACT_REVEAL   = 600;
const EXTRACT_TIME     = 1.5;
const RAY_STEPS        = 300;
const PERCEPTION_RANGE = 90;
const ZOOM             = 1.5;

// ─── Combat constants ─────────────────────────────────────────────────────────
const BULLET_SPEED      = 700;
const BULLET_RANGE      = 950;
const PLAYER_DMG        = 40;
const PLAYER_FIRE_RATE  = 220;   // ms between shots
const PLAYER_HP         = 100;
const PLAYER_START_AMMO = 30;
const MAG_SIZE          = 10;
const RELOAD_TIME       = 2.0;  // seconds
const ENEMY_COUNT       = 12;
const ENEMY_HP          = 60;
const ENEMY_SPEED       = 55;
const ENEMY_DETECT_R    = 400;
const ENEMY_FIRE_RATE   = 2200;  // ms between enemy shots
const ENEMY_DMG         = 18;

// VIEW_RANGE computed dynamically so cone always exceeds screen corners
function _viewRange() {
  return Math.ceil(Math.hypot(VIEW_W, VIEW_H) / (2 * ZOOM)) + TILE * 3;
}

// ─── Item types ───────────────────────────────────────────────────────────────
const ITEM_TYPES = [
  { id: 'ammo',    name: '子弹',   w: 1, h: 1, value: 50,   color: '#e0cc88' },
  { id: 'medkit',  name: '医疗包', w: 1, h: 2, value: 220,  color: '#88c8a0' },
  { id: 'parts',   name: '零件',   w: 2, h: 1, value: 160,  color: '#a0a8cc' },
  { id: 'battery', name: '电池',   w: 1, h: 2, value: 340,  color: '#e8a855' },
  { id: 'chip',    name: '芯片',   w: 2, h: 2, value: 850,  color: '#cc88cc' },
  { id: 'weapon',  name: '武器',   w: 3, h: 1, value: 1200, color: '#e87777' },
];

// ─── Inventory ────────────────────────────────────────────────────────────────
const INV_COLS = 4;
const INV_ROWS = 5;
const INV_CELL = 30;
const INV_PAD  = 10;

function _invOrigin() {
  return { x: VIEW_W - INV_COLS * INV_CELL - INV_PAD, y: INV_PAD + 22 };
}

// ─── Raid state ───────────────────────────────────────────────────────────────
let RS = null;

function initRaid() {
  const { tiles, items, extraction } = _generateMap();

  const spawnTX = Math.floor(R_MAP_W / 2);
  const spawnTY = Math.floor(R_MAP_H / 2);

  const fogCanvas = document.createElement('canvas');
  fogCanvas.width  = VIEW_W;
  fogCanvas.height = VIEW_H;

  RS = {
    tiles, items, extraction,
    extractionRevealed: false,
    player: { x: (spawnTX + 0.5) * TILE, y: (spawnTY + 0.5) * TILE,
      r: 12, speed: 200, facing: 0,
      hp: PLAYER_HP, ammo: PLAYER_START_AMMO,
      mag: MAG_SIZE, reloading: false, reloadTimer: 0,
      lastShot: -Infinity },
    timer: RAID_DURATION, itemsCollected: 0, extractProgress: 0,
    fog: { polygon: [], fogCanvas, fogCtx: fogCanvas.getContext('2d') },
    inventory: {
      grid: Array.from({ length: INV_ROWS }, () => new Array(INV_COLS).fill(null)),
      placed: [],
    },
    bullets: [],
    enemies: [],
  };
  _spawnEnemies();
}

// ─── Map generation ───────────────────────────────────────────────────────────
const MAP_FILL_DENSITY = 0.45;   // initial wall noise density
const MAP_CA_ITERS     = 5;      // cellular automata smoothing passes
const MAP_SPAWN_CLEAR  = 6;      // tile radius kept open at spawn

// Flood-fill: mark all floor tiles reachable from (sx,sy), wall off unreachable ones
function _floodFillKeepLargest(tiles, sx, sy) {
  const visited = Array.from({ length: R_MAP_H }, () => new Uint8Array(R_MAP_W));
  const stack = [[sx, sy]];
  visited[sy][sx] = 1;
  while (stack.length) {
    const [x, y] = stack.pop();
    for (const [dx, dy] of [[-1,0],[1,0],[0,-1],[0,1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || nx >= R_MAP_W || ny < 0 || ny >= R_MAP_H) continue;
      if (visited[ny][nx] || tiles[ny][nx] === 1) continue;
      visited[ny][nx] = 1;
      stack.push([nx, ny]);
    }
  }
  // Seal any floor tile not reachable from spawn
  for (let y = 0; y < R_MAP_H; y++)
    for (let x = 0; x < R_MAP_W; x++)
      if (tiles[y][x] === 0 && !visited[y][x]) tiles[y][x] = 1;
}

// Carve a 1-tile corridor from (ex,ey) toward spawn until hitting connected floor
function _carveCorridorToSpawn(tiles, ex, ey, cx, cy) {
  let x = ex, y = ey;
  while (x > 0 && x < R_MAP_W - 1 && y > 0 && y < R_MAP_H - 1) {
    tiles[y][x] = 0;
    // Stop once an orthogonal neighbor is already connected to spawn
    for (const [dx, dy] of [[-1,0],[1,0],[0,-1],[0,1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || nx >= R_MAP_W || ny < 0 || ny >= R_MAP_H) continue;
      if (tiles[ny][nx] === 0 && _isFloorConnected(tiles, cx, cy, nx, ny)) return;
    }
    const dx = cx - x, dy = cy - y;
    if (Math.abs(dx) >= Math.abs(dy)) x += dx > 0 ? 1 : -1;
    else                              y += dy > 0 ? 1 : -1;
  }
}

// Quick BFS check: is (tx,ty) reachable from (sx,sy) through floor tiles
function _isFloorConnected(tiles, sx, sy, tx, ty) {
  if (tiles[ty][tx] !== 0) return false;
  const visited = new Uint8Array(R_MAP_W * R_MAP_H);
  const stack = [[sx, sy]];
  visited[sy * R_MAP_W + sx] = 1;
  while (stack.length) {
    const [x, y] = stack.pop();
    if (x === tx && y === ty) return true;
    for (const [dx, dy] of [[-1,0],[1,0],[0,-1],[0,1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || nx >= R_MAP_W || ny < 0 || ny >= R_MAP_H) continue;
      const idx = ny * R_MAP_W + nx;
      if (visited[idx] || tiles[ny][nx] === 1) continue;
      visited[idx] = 1;
      stack.push([nx, ny]);
    }
  }
  return false;
}

function _generateMap() {
  const tiles = Array.from({ length: R_MAP_H }, () => new Uint8Array(R_MAP_W));

  for (let x = 0; x < R_MAP_W; x++) { tiles[0][x] = 1; tiles[R_MAP_H - 1][x] = 1; }
  for (let y = 0; y < R_MAP_H; y++) { tiles[y][0] = 1; tiles[y][R_MAP_W - 1] = 1; }

  const cx = Math.floor(R_MAP_W / 2);
  const cy = Math.floor(R_MAP_H / 2);

  // 1) Random noise fill
  for (let y = 1; y < R_MAP_H - 1; y++)
    for (let x = 1; x < R_MAP_W - 1; x++) {
      if (Math.random() < MAP_FILL_DENSITY) tiles[y][x] = 1;
    }

  // 2) Cellular automata smoothing — clumps walls together
  for (let iter = 0; iter < MAP_CA_ITERS; iter++) {
    const next = Array.from({ length: R_MAP_H }, () => new Uint8Array(R_MAP_W));
    for (let x = 0; x < R_MAP_W; x++) { next[0][x] = 1; next[R_MAP_H - 1][x] = 1; }
    for (let y = 0; y < R_MAP_H; y++) { next[y][0] = 1; next[y][R_MAP_W - 1] = 1; }
    for (let y = 1; y < R_MAP_H - 1; y++)
      for (let x = 1; x < R_MAP_W - 1; x++) {
        let n = 0;
        for (let dy = -1; dy <= 1; dy++)
          for (let dx = -1; dx <= 1; dx++) {
            if (dx === 0 && dy === 0) continue;
            if (tiles[y + dy][x + dx] === 1) n++;
          }
        // Birth if >=5 wall neighbors, survive if >=4, else floor
        if (tiles[y][x] === 1) next[y][x] = n >= 4 ? 1 : 0;
        else                   next[y][x] = n >= 5 ? 1 : 0;
      }
    for (let y = 0; y < R_MAP_H; y++) tiles[y].set(next[y]);
  }

  // 3) Clear spawn zone
  for (let y = 1; y < R_MAP_H - 1; y++)
    for (let x = 1; x < R_MAP_W - 1; x++) {
      if (Math.hypot(x - cx, y - cy) < MAP_SPAWN_CLEAR) tiles[y][x] = 0;
    }

  // 3) Pick & clear extraction zone BEFORE flood-fill so it's included in connectivity
  let ex, ey;
  const edge = Math.floor(Math.random() * 4);
  if      (edge === 0) { ex = 2 + Math.floor(Math.random() * (R_MAP_W - 4)); ey = 1; }
  else if (edge === 1) { ex = R_MAP_W - 2; ey = 2 + Math.floor(Math.random() * (R_MAP_H - 4)); }
  else if (edge === 2) { ex = 2 + Math.floor(Math.random() * (R_MAP_W - 4)); ey = R_MAP_H - 2; }
  else                 { ex = 1; ey = 2 + Math.floor(Math.random() * (R_MAP_H - 4)); }
  for (let dy = -1; dy <= 1; dy++)
    for (let dx = -1; dx <= 1; dx++) {
      const nx = ex + dx, ny = ey + dy;
      if (nx > 0 && nx < R_MAP_W - 1 && ny > 0 && ny < R_MAP_H - 1) tiles[ny][nx] = 0;
    }

  // 4) Flood-fill connectivity: only keep the largest open region, fill the rest
  _floodFillKeepLargest(tiles, cx, cy);

  // 5) If extraction was sealed by flood-fill, carve a corridor to spawn
  if (tiles[ey][ex] === 1) _carveCorridorToSpawn(tiles, ex, ey, cx, cy);

  const items = [];
  for (let att = 0; items.length < ITEM_COUNT && att < 3000; att++) {
    const tx = 2 + Math.floor(Math.random() * (R_MAP_W - 4));
    const ty = 2 + Math.floor(Math.random() * (R_MAP_H - 4));
    if (tiles[ty][tx] !== 0 || Math.hypot(tx - cx, ty - cy) < 6) continue;
    items.push({ tx, ty, x: (tx + 0.5) * TILE, y: (ty + 0.5) * TILE, collected: false,
      type: ITEM_TYPES[Math.floor(Math.random() * ITEM_TYPES.length)] });
  }

  return { tiles, items, extraction: { tx: ex, ty: ey, x: (ex + 0.5) * TILE, y: (ey + 0.5) * TILE } };
}

// ─── Update ───────────────────────────────────────────────────────────────────
function updateRaid(dt) {
  if (!RS) return;
  const now = performance.now();

  RS.timer -= dt;
  if (RS.timer <= 0) { switchToResult(false, RS.inventory.placed); return; }

  // Player movement
  let mx = 0, my = 0;
  if (keys['ArrowUp']    || keys['w'] || keys['W']) my -= 1;
  if (keys['ArrowDown']  || keys['s'] || keys['S']) my += 1;
  if (keys['ArrowLeft']  || keys['a'] || keys['A']) mx -= 1;
  if (keys['ArrowRight'] || keys['d'] || keys['D']) mx += 1;
  if (mx !== 0 && my !== 0) { mx *= 0.7071; my *= 0.7071; }

  const spd = RS.player.speed * (keys['Shift'] ? 2.2 : 1);
  const pos = _resolveCollision(
    RS.player.x + mx * spd * dt,
    RS.player.y + my * spd * dt,
    RS.player.r, RS.tiles
  );
  RS.player.x = Math.max(RS.player.r, Math.min(R_MAP_W * TILE - RS.player.r, pos.x));
  RS.player.y = Math.max(RS.player.r, Math.min(R_MAP_H * TILE - RS.player.r, pos.y));
  RS.player.facing = Math.atan2(mouse.y - VIEW_H / 2, mouse.x - VIEW_W / 2);

  // Reload
  const p = RS.player;
  if ((keys['r'] || keys['R']) && !p.reloading && p.mag < MAG_SIZE && p.ammo > 0) {
    p.reloading = true;
    p.reloadTimer = RELOAD_TIME;
  }
  if (p.reloading) {
    p.reloadTimer -= dt;
    if (p.reloadTimer <= 0) {
      const take = Math.min(MAG_SIZE - p.mag, p.ammo);
      p.mag += take; p.ammo -= take;
      p.reloading = false;
    }
  }

  // Shooting
  if (mouse.down) _playerShoot(now);

  // Fog + combat updates
  _updateFogBasic();
  _updateBullets(dt, now);
  _updateEnemies(dt, now);

  // Player death
  if (RS.player.hp <= 0) { switchToResult(false, RS.inventory.placed); return; }

  // Item pickup
  for (const item of RS.items) {
    if (item.collected) continue;
    if (!_isPointVisible(item.x, item.y)) continue;
    if (Math.hypot(RS.player.x - item.x, RS.player.y - item.y) < TILE * 0.65) {
      if (item.type.id === 'ammo') {
        item.collected = true;
        RS.player.ammo += 30;
      } else if (_inventoryPlace(item)) {
        item.collected = true;
        RS.itemsCollected++;
      }
    }
  }

  const eDist = Math.hypot(RS.player.x - RS.extraction.x, RS.player.y - RS.extraction.y);
  if (eDist < EXTRACT_REVEAL) RS.extractionRevealed = true;

  if (eDist < TILE * 0.75) {
    RS.extractProgress += dt;
    if (RS.extractProgress >= EXTRACT_TIME) { switchToResult(true, RS.inventory.placed); return; }
  } else {
    RS.extractProgress = Math.max(0, RS.extractProgress - dt * 2);
  }
}

// ─── Collision ────────────────────────────────────────────────────────────────
function _resolveCollision(px, py, pr, tiles) {
  let x = px, y = py;
  const minTX = Math.max(0, Math.floor((x - pr) / TILE));
  const maxTX = Math.min(R_MAP_W - 1, Math.floor((x + pr) / TILE));
  const minTY = Math.max(0, Math.floor((y - pr) / TILE));
  const maxTY = Math.min(R_MAP_H - 1, Math.floor((y + pr) / TILE));
  for (let ty = minTY; ty <= maxTY; ty++)
    for (let tx = minTX; tx <= maxTX; tx++) {
      if (tiles[ty][tx] !== 1) continue;
      const cx = Math.max(tx * TILE, Math.min(x, (tx + 1) * TILE));
      const cy = Math.max(ty * TILE, Math.min(y, (ty + 1) * TILE));
      const ddx = x - cx, ddy = y - cy;
      const dist = Math.sqrt(ddx * ddx + ddy * ddy);
      if (dist < pr && dist > 0) { x += ddx / dist * (pr - dist); y += ddy / dist * (pr - dist); }
    }
  return { x, y };
}

// ─── Render ───────────────────────────────────────────────────────────────────
function renderRaid() {
  if (!RS) return;
  const px = RS.player.x, py = RS.player.y;

  // Zoomed camera: player stays at screen center, world scaled by ZOOM
  ctx.save();
  ctx.translate(VIEW_W / 2, VIEW_H / 2);
  ctx.scale(ZOOM, ZOOM);
  ctx.translate(-px, -py);
  _drawMap();
  _drawItems();
  _drawEnemies();
  _drawBullets();
  _drawRaidPlayer();
  ctx.restore();

  _renderFogOverlay();

  // Draw extraction above fog (zoomed screen coords)
  if (RS.extractionRevealed) {
    ctx.save();
    ctx.translate(VIEW_W / 2, VIEW_H / 2);
    ctx.scale(ZOOM, ZOOM);
    ctx.translate(-px, -py);
    _drawExtraction();
    ctx.restore();
  }

  _drawHUD();
  _drawInventory();
}

function _drawMap() {
  const { tiles } = RS;
  const px = RS.player.x, py = RS.player.y;
  const halfW = VIEW_W / (2 * ZOOM), halfH = VIEW_H / (2 * ZOOM);
  const minTX = Math.max(0, Math.floor((px - halfW) / TILE) - 1);
  const maxTX = Math.min(R_MAP_W - 1, Math.floor((px + halfW) / TILE) + 1);
  const minTY = Math.max(0, Math.floor((py - halfH) / TILE) - 1);
  const maxTY = Math.min(R_MAP_H - 1, Math.floor((py + halfH) / TILE) + 1);
  for (let ty = minTY; ty <= maxTY; ty++)
    for (let tx = minTX; tx <= maxTX; tx++) {
      ctx.fillStyle = tiles[ty][tx] === 1 ? '#111111' : '#e8e8e8';
      ctx.fillRect(tx * TILE, ty * TILE, TILE, TILE);
    }
}

function _drawExtraction() {
  if (!RS.extractionRevealed) return;
  const { x, y } = RS.extraction;
  const pulse = 0.5 + 0.5 * Math.sin(performance.now() / 500);
  ctx.save();
  ctx.strokeStyle = `rgba(255,255,255,${0.5 + 0.4 * pulse})`;
  ctx.fillStyle   = `rgba(255,255,255,${0.10 + 0.07 * pulse})`;
  ctx.lineWidth = 2;
  ctx.shadowColor = '#ffffff'; ctx.shadowBlur = 12 + 10 * pulse;
  ctx.beginPath(); ctx.arc(x, y, TILE * 0.42, 0, Math.PI * 2);
  ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#ffffff'; ctx.font = '10px monospace';
  ctx.textAlign = 'center'; ctx.textBaseline = 'bottom'; ctx.shadowBlur = 0;
  ctx.fillText('EXTRACT', x, y - TILE * 0.46 - 3);
  ctx.restore();
}

function _isPointVisible(wx, wy) {
  const px = RS.player.x, py = RS.player.y;
  const dx = wx - px, dy = wy - py;
  const dist = Math.hypot(dx, dy);
  if (dist <= PERCEPTION_RANGE) return true;
  if (dist > _viewRange()) return false;
  let diff = Math.atan2(dy, dx) - RS.player.facing;
  while (diff >  Math.PI) diff -= 2 * Math.PI;
  while (diff < -Math.PI) diff += 2 * Math.PI;
  if (Math.abs(diff) > CONE_HALF) return false;
  return _castRayDDA(px, py, Math.atan2(dy, dx)) >= dist - TILE * 0.5;
}

function _drawItems() {
  for (const item of RS.items) {
    if (item.collected) continue;
    if (!_isPointVisible(item.x, item.y)) continue;
    ctx.save();
    ctx.fillStyle   = item.type.color;
    ctx.shadowColor = item.type.color;
    ctx.shadowBlur  = item.isEnemyDrop ? 14 : 0;
    ctx.beginPath(); ctx.arc(item.x, item.y, 6, 0, Math.PI * 2); ctx.fill();
    if (item.isEnemyDrop) {
      // Diamond outline to signal enemy loot
      const s = 11;
      ctx.strokeStyle = 'rgba(255,255,255,0.75)';
      ctx.lineWidth = 1.2;
      ctx.shadowColor = '#ffffff';
      ctx.shadowBlur = 6;
      ctx.beginPath();
      ctx.moveTo(item.x,     item.y - s);
      ctx.lineTo(item.x + s, item.y    );
      ctx.lineTo(item.x,     item.y + s);
      ctx.lineTo(item.x - s, item.y    );
      ctx.closePath();
      ctx.stroke();
    }
    ctx.restore();
  }
}

function _drawRaidPlayer() {
  const p = RS.player;
  ctx.save();
  ctx.strokeStyle = 'rgba(255,255,255,0.22)'; ctx.lineWidth = 1;
  ctx.setLineDash([3, 4]);
  ctx.beginPath(); ctx.moveTo(p.x, p.y);
  ctx.lineTo(p.x + Math.cos(p.facing) * 36, p.y + Math.sin(p.facing) * 36);
  ctx.stroke(); ctx.setLineDash([]);

  const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r * 2.5);
  g.addColorStop(0, 'rgba(255,255,255,0.22)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.beginPath(); ctx.arc(p.x, p.y, p.r * 2.5, 0, Math.PI * 2);
  ctx.fillStyle = g; ctx.fill();

  ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
  ctx.fillStyle = '#1a1a1a'; ctx.fill();
  ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 2;
  ctx.shadowColor = '#ffffff'; ctx.shadowBlur = 8; ctx.stroke();
  ctx.beginPath(); ctx.arc(p.x, p.y, 3.5, 0, Math.PI * 2);
  ctx.fillStyle = '#ffffff'; ctx.shadowBlur = 0; ctx.fill();
  ctx.restore();
}

// ─── Ray casting ──────────────────────────────────────────────────────────────
function _castRayDDA(ox, oy, angle) {
  const dx = Math.cos(angle), dy = Math.sin(angle);
  const tiles = RS.tiles;
  let tileX = Math.floor(ox / TILE), tileY = Math.floor(oy / TILE);
  const tDX = dx !== 0 ? Math.abs(TILE / dx) : Infinity;
  const tDY = dy !== 0 ? Math.abs(TILE / dy) : Infinity;
  const stepX = dx > 0 ? 1 : -1, stepY = dy > 0 ? 1 : -1;
  let tMaxX = dx > 0 ? ((tileX+1)*TILE - ox)/dx : dx < 0 ? (tileX*TILE - ox)/dx : Infinity;
  let tMaxY = dy > 0 ? ((tileY+1)*TILE - oy)/dy : dy < 0 ? (tileY*TILE - oy)/dy : Infinity;
  for (let i = 0; i < 90; i++) {
    let t;
    if (tMaxX < tMaxY) { t = tMaxX; tileX += stepX; tMaxX += tDX; }
    else               { t = tMaxY; tileY += stepY; tMaxY += tDY; }
    if (t >= _viewRange()) return _viewRange();
    if (tileX < 0 || tileX >= R_MAP_W || tileY < 0 || tileY >= R_MAP_H) return _viewRange();
    if (tiles[tileY][tileX] === 1) return t;
  }
  return _viewRange();
}

// ─── Fog ──────────────────────────────────────────────────────────────────────
function _updateFogBasic() {
  const { x: px, y: py, facing } = RS.player;
  const poly = [{ x: px, y: py }];
  for (let i = 0; i <= RAY_STEPS; i++) {
    const angle = (facing - CONE_HALF) + (i / RAY_STEPS) * 2 * CONE_HALF;
    const dist  = _castRayDDA(px, py, angle);
    poly.push({ x: px + Math.cos(angle) * dist, y: py + Math.sin(angle) * dist });
  }
  RS.fog.polygon = poly;
}

function _renderFogOverlay() {
  const { fogCanvas, fogCtx: fc } = RS.fog;
  const px = RS.player.x, py = RS.player.y;

  if (fogCanvas.width !== VIEW_W || fogCanvas.height !== VIEW_H) {
    fogCanvas.width  = VIEW_W;
    fogCanvas.height = VIEW_H;
  }

  fc.clearRect(0, 0, VIEW_W, VIEW_H);
  fc.fillStyle = 'rgba(0,0,0,0.58)';
  fc.fillRect(0, 0, VIEW_W, VIEW_H);

  // Apply same zoomed transform as main canvas so shapes align perfectly
  fc.setTransform(ZOOM, 0, 0, ZOOM, VIEW_W / 2 - px * ZOOM, VIEW_H / 2 - py * ZOOM);
  fc.globalCompositeOperation = 'destination-out';
  fc.fillStyle = '#ffffff';

  // View cone (world coords)
  const poly = RS.fog.polygon;
  if (poly && poly.length > 2) {
    fc.beginPath();
    poly.forEach((p, i) => i === 0 ? fc.moveTo(p.x, p.y) : fc.lineTo(p.x, p.y));
    fc.closePath();
    fc.fill();
  }

  // Perception circle (world coords)
  fc.beginPath();
  fc.arc(px, py, PERCEPTION_RANGE, 0, Math.PI * 2);
  fc.fill();

  fc.setTransform(1, 0, 0, 1, 0, 0);
  fc.globalCompositeOperation = 'source-over';
  ctx.drawImage(fogCanvas, 0, 0);
}

function _drawHUD() {
  ctx.save(); ctx.shadowBlur = 0;

  const t    = Math.max(0, RS.timer);
  const mins = Math.floor(t / 60);
  const secs = Math.floor(t % 60).toString().padStart(2, '0');
  ctx.font = 'bold 20px monospace'; ctx.textAlign = 'center'; ctx.textBaseline = 'top';
  ctx.fillStyle   = t < 30 ? '#ff5555' : '#ffffff';
  ctx.shadowColor = t < 30 ? '#ff0000' : 'transparent';
  ctx.shadowBlur  = t < 30 ? 10 : 0;
  ctx.fillText(`${mins}:${secs}`, VIEW_W / 2, 18);

  ctx.shadowBlur = 0; ctx.font = '15px monospace';
  ctx.textAlign = 'right'; ctx.fillStyle = '#cccccc';
  ctx.fillText(`物品  ${RS.itemsCollected} / ${RS.items.length}`, VIEW_W - 18, 22);

  // HP bar (bottom-left)
  const bw = 160, bh = 10, bx = 16, by = VIEW_H - 30;
  ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillRect(bx - 2, by - 2, bw + 4, bh + 4);
  const hpRatio = Math.max(0, RS.player.hp / PLAYER_HP);
  ctx.fillStyle = hpRatio > 0.5 ? '#88ff88' : hpRatio > 0.25 ? '#ffcc44' : '#ff4444';
  ctx.fillRect(bx, by, bw * hpRatio, bh);
  ctx.strokeStyle = 'rgba(255,255,255,0.3)'; ctx.lineWidth = 1; ctx.strokeRect(bx, by, bw, bh);
  ctx.font = '11px monospace'; ctx.textAlign = 'left'; ctx.textBaseline = 'bottom';
  ctx.fillStyle = '#aaaaaa'; ctx.fillText(`HP ${RS.player.hp}`, bx, by - 3);

  // Ammo — bottom-right
  const p = RS.player;
  ctx.textAlign = 'right'; ctx.textBaseline = 'bottom';
  ctx.font = 'bold 20px monospace';
  ctx.fillStyle = p.mag === 0 ? '#ff5555' : '#ffffff';
  ctx.fillText(`${p.mag} / ${p.ammo}`, VIEW_W - 16, VIEW_H - 16);
  ctx.font = '11px monospace'; ctx.fillStyle = '#888888';
  ctx.fillText('弹夹 / 备弹', VIEW_W - 16, VIEW_H - 40);

  // Reload bar
  if (p.reloading) {
    const rbw = 120, rbh = 6, rbx = VIEW_W - 16 - rbw, rby = VIEW_H - 56;
    const prog = 1 - p.reloadTimer / RELOAD_TIME;
    ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillRect(rbx - 2, rby - 2, rbw + 4, rbh + 4);
    ctx.fillStyle = '#ffdd66'; ctx.fillRect(rbx, rby, rbw * prog, rbh);
    ctx.strokeStyle = 'rgba(255,255,255,0.3)'; ctx.lineWidth = 1; ctx.strokeRect(rbx, rby, rbw, rbh);
    ctx.font = '11px monospace'; ctx.textAlign = 'right'; ctx.fillStyle = '#ffdd66';
    ctx.fillText('换弹中…', VIEW_W - 16, rby - 4);
  } else if (p.mag === 0) {
    ctx.font = '12px monospace'; ctx.textAlign = 'right'; ctx.fillStyle = '#ff5555';
    ctx.fillText('[R] 换弹', VIEW_W - 16, VIEW_H - 56);
  }

  if (RS.extractProgress > 0) {
    const prog = RS.extractProgress / EXTRACT_TIME;
    const bw = 200, bh = 10, bx = VIEW_W / 2 - bw / 2, by = VIEW_H - 58;
    ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(bx - 2, by - 2, bw + 4, bh + 4);
    ctx.fillStyle = '#ffffff'; ctx.fillRect(bx, by, bw * prog, bh);
    ctx.strokeStyle = 'rgba(255,255,255,0.4)'; ctx.lineWidth = 1;
    ctx.strokeRect(bx, by, bw, bh);
    ctx.font = '12px monospace'; ctx.textAlign = 'center';
    ctx.fillStyle = '#ffffff'; ctx.fillText('撤离中…', VIEW_W / 2, by - 16);
  }

  if (!RS.extractionRevealed) {
    // Direction arrow toward extraction
    const ex = RS.extraction.x, ey = RS.extraction.y;
    const angle = Math.atan2(ey - RS.player.y, ex - RS.player.x);
    const ax = VIEW_W / 2 + Math.cos(angle) * 60;
    const ay = VIEW_H / 2 + Math.sin(angle) * 60;
    ctx.save();
    ctx.translate(ax, ay);
    ctx.rotate(angle);
    ctx.fillStyle = 'rgba(255,255,255,0.55)';
    ctx.beginPath();
    ctx.moveTo(12, 0); ctx.lineTo(-8, -7); ctx.lineTo(-8, 7);
    ctx.closePath(); ctx.fill();
    ctx.restore();
    ctx.font = '12px monospace'; ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
    ctx.fillStyle = 'rgba(255,255,255,0.3)';
    ctx.fillText('探索地图以找到撤离点', VIEW_W / 2, VIEW_H - 16);
  }

  ctx.restore();
}

// ─── Inventory logic ─────────────────────────────────────────────────────────
function _inventoryPlace(item) {
  const { w, h } = item.type;
  const grid = RS.inventory.grid;
  for (let r = 0; r <= INV_ROWS - h; r++) {
    for (let c = 0; c <= INV_COLS - w; c++) {
      let fits = true;
      for (let dr = 0; dr < h && fits; dr++)
        for (let dc = 0; dc < w && fits; dc++)
          if (grid[r + dr][c + dc] !== null) fits = false;
      if (fits) {
        for (let dr = 0; dr < h; dr++)
          for (let dc = 0; dc < w; dc++)
            grid[r + dr][c + dc] = item;
        item.invRow = r; item.invCol = c;
        RS.inventory.placed.push(item);
        return true;
      }
    }
  }
  return false;
}

function _inventoryDrop(row, col) {
  const grid = RS.inventory.grid;
  const item  = grid[row][col];
  if (!item) return;
  for (let r = 0; r < INV_ROWS; r++)
    for (let c = 0; c < INV_COLS; c++)
      if (grid[r][c] === item) grid[r][c] = null;
  RS.inventory.placed = RS.inventory.placed.filter(i => i !== item);
  RS.itemsCollected--;
}

function handleRaidClick(cx, cy) {
  if (!RS) return;
  const { x: ox, y: oy } = _invOrigin();
  if (cx < ox || cx > ox + INV_COLS * INV_CELL) return;
  if (cy < oy || cy > oy + INV_ROWS * INV_CELL) return;
  const col = Math.floor((cx - ox) / INV_CELL);
  const row = Math.floor((cy - oy) / INV_CELL);
  _inventoryDrop(row, col);
}

// ─── Inventory UI ─────────────────────────────────────────────────────────────
function _drawInventory() {
  const { x: ox, y: oy } = _invOrigin();
  const grid = RS.inventory.grid;
  ctx.save();

  // Background
  ctx.fillStyle = 'rgba(0,0,0,0.72)';
  ctx.fillRect(ox - 4, oy - 20, INV_COLS * INV_CELL + 8, INV_ROWS * INV_CELL + 24);

  // Label
  ctx.font = '11px monospace'; ctx.textAlign = 'left'; ctx.textBaseline = 'top';
  ctx.fillStyle = '#888888';
  ctx.fillText('背包  (点击丢弃)', ox, oy - 17);

  // Empty grid cells
  ctx.strokeStyle = 'rgba(255,255,255,0.12)'; ctx.lineWidth = 0.5;
  for (let r = 0; r < INV_ROWS; r++)
    for (let c = 0; c < INV_COLS; c++)
      ctx.strokeRect(ox + c * INV_CELL, oy + r * INV_CELL, INV_CELL, INV_CELL);

  // Placed items
  const drawn = new Set();
  for (let r = 0; r < INV_ROWS; r++)
    for (let c = 0; c < INV_COLS; c++) {
      const item = grid[r][c];
      if (!item || drawn.has(item)) continue;
      drawn.add(item);
      const ix = ox + item.invCol * INV_CELL + 2;
      const iy = oy + item.invRow * INV_CELL + 2;
      const iw = item.type.w * INV_CELL - 4;
      const ih = item.type.h * INV_CELL - 4;
      ctx.fillStyle = item.type.color;
      ctx.fillRect(ix, iy, iw, ih);
      ctx.fillStyle = 'rgba(0,0,0,0.75)';
      ctx.font = '9px monospace';
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(item.type.name,        ix + iw / 2, iy + ih / 2 - 4);
      ctx.fillText('¥' + item.type.value, ix + iw / 2, iy + ih / 2 + 5);
    }

  ctx.restore();
}

// ─── Combat: spawn ────────────────────────────────────────────────────────────
function _spawnEnemies() {
  const cx = Math.floor(R_MAP_W / 2), cy = Math.floor(R_MAP_H / 2);
  let count = 0, attempts = 0;
  while (count < ENEMY_COUNT && attempts < 3000) {
    attempts++;
    const tx = 1 + Math.floor(Math.random() * (R_MAP_W - 2));
    const ty = 1 + Math.floor(Math.random() * (R_MAP_H - 2));
    if (RS.tiles[ty][tx] !== 0) continue;
    if (Math.hypot(tx - cx, ty - cy) < 12) continue;
    RS.enemies.push({
      x: (tx + 0.5) * TILE, y: (ty + 0.5) * TILE,
      hp: ENEMY_HP, r: 14,
      facing: Math.random() * Math.PI * 2,
      state: 'wander',
      wanderTimer: Math.random() * 2,
      lastShot: -Infinity,
      lastSeen: -Infinity,
    });
    count++;
  }
}

// ─── Combat: shooting ─────────────────────────────────────────────────────────
function _playerShoot(now) {
  const p = RS.player;
  if (p.reloading || p.mag <= 0 || now - p.lastShot < PLAYER_FIRE_RATE) return;
  p.lastShot = now; p.mag--;
  RS.bullets.push({ x: p.x, y: p.y, dx: Math.cos(p.facing), dy: Math.sin(p.facing),
    speed: BULLET_SPEED, traveled: 0, owner: 'player', r: 4 });
}

function _enemyShoot(enemy, now) {
  if (now - enemy.lastShot < ENEMY_FIRE_RATE) return;
  enemy.lastShot = now;
  const dx = RS.player.x - enemy.x, dy = RS.player.y - enemy.y;
  const len = Math.hypot(dx, dy) || 1;
  RS.bullets.push({ x: enemy.x, y: enemy.y, dx: dx/len, dy: dy/len,
    speed: BULLET_SPEED, traveled: 0, owner: 'enemy', r: 4 });
}

// ─── Combat: bullets ─────────────────────────────────────────────────────────
function _inWall(x, y) {
  const tx = Math.floor(x / TILE), ty = Math.floor(y / TILE);
  if (tx < 0 || tx >= R_MAP_W || ty < 0 || ty >= R_MAP_H) return true;
  return RS.tiles[ty][tx] === 1;
}

function _updateBullets(dt) {
  const step = BULLET_SPEED * dt;
  RS.bullets = RS.bullets.filter(b => {
    b.x += b.dx * step; b.y += b.dy * step; b.traveled += step;
    if (b.traveled > BULLET_RANGE || _inWall(b.x, b.y)) return false;
    if (b.owner === 'player') {
      for (const e of RS.enemies) {
        if (Math.hypot(b.x - e.x, b.y - e.y) < b.r + e.r) {
          e.hp -= PLAYER_DMG; return false;
        }
      }
    } else {
      if (Math.hypot(b.x - RS.player.x, b.y - RS.player.y) < b.r + RS.player.r) {
        RS.player.hp -= ENEMY_DMG; return false;
      }
    }
    return true;
  });
  const dead = RS.enemies.filter(e => e.hp <= 0);
  dead.forEach(e => _spawnEnemyDrop(e.x, e.y));
  RS.enemies = RS.enemies.filter(e => e.hp > 0);
}

// ─── Combat: enemy drops ─────────────────────────────────────────────────────
const DROP_CHANCE = 0.75;   // 75% chance enemy drops something

function _spawnEnemyDrop(wx, wy) {
  if (Math.random() > DROP_CHANCE) return;
  const type = ITEM_TYPES[Math.floor(Math.random() * ITEM_TYPES.length)];
  const tx = Math.floor(wx / TILE);
  const ty = Math.floor(wy / TILE);
  RS.items.push({
    tx, ty, x: wx, y: wy,
    collected: false,
    type,
    isEnemyDrop: true,
  });
}

// ─── Combat: enemy AI ────────────────────────────────────────────────────────
function _enemyCanSeePlayer(enemy) {
  const dx = RS.player.x - enemy.x, dy = RS.player.y - enemy.y;
  const dist = Math.hypot(dx, dy);
  if (dist > ENEMY_DETECT_R) return false;
  return _castRayDDA(enemy.x, enemy.y, Math.atan2(dy, dx)) >= dist - TILE * 0.5;
}

function _updateEnemies(dt, now) {
  for (const enemy of RS.enemies) {
    if (enemy.state === 'wander') {
      // Move
      enemy.wanderTimer -= dt;
      if (enemy.wanderTimer <= 0) {
        enemy.facing = Math.random() * Math.PI * 2;
        enemy.wanderTimer = 1.5 + Math.random() * 2;
      }
      const np = _resolveCollision(
        enemy.x + Math.cos(enemy.facing) * ENEMY_SPEED * dt,
        enemy.y + Math.sin(enemy.facing) * ENEMY_SPEED * dt,
        enemy.r, RS.tiles
      );
      if (Math.abs(np.x - enemy.x) < 0.1 && Math.abs(np.y - enemy.y) < 0.1) {
        enemy.facing = Math.random() * Math.PI * 2; // bounced wall
      }
      enemy.x = Math.max(enemy.r, Math.min(R_MAP_W*TILE - enemy.r, np.x));
      enemy.y = Math.max(enemy.r, Math.min(R_MAP_H*TILE - enemy.r, np.y));

      if (_enemyCanSeePlayer(enemy)) { enemy.state = 'alert'; enemy.lastSeen = now; }

    } else { // alert
      const dx = RS.player.x - enemy.x, dy = RS.player.y - enemy.y;
      enemy.facing = Math.atan2(dy, dx);
      if (_enemyCanSeePlayer(enemy)) {
        enemy.lastSeen = now;
        _enemyShoot(enemy, now);
      } else if (now - enemy.lastSeen > 4000) {
        enemy.state = 'wander';
        enemy.wanderTimer = 0;
      }
    }
  }
}

// ─── Combat: drawing ─────────────────────────────────────────────────────────
function _drawEnemies() {
  for (const enemy of RS.enemies) {
    if (!_isPointVisible(enemy.x, enemy.y)) continue;
    ctx.save();
    // Glow
    const g = ctx.createRadialGradient(enemy.x, enemy.y, 0, enemy.x, enemy.y, enemy.r * 2);
    g.addColorStop(0, 'rgba(255,80,60,0.25)'); g.addColorStop(1, 'rgba(255,80,60,0)');
    ctx.beginPath(); ctx.arc(enemy.x, enemy.y, enemy.r * 2, 0, Math.PI * 2);
    ctx.fillStyle = g; ctx.fill();
    // Body
    ctx.beginPath(); ctx.arc(enemy.x, enemy.y, enemy.r, 0, Math.PI * 2);
    ctx.fillStyle = enemy.state === 'alert' ? '#cc3322' : '#883322';
    ctx.fill();
    ctx.strokeStyle = '#ff6644'; ctx.lineWidth = 2;
    ctx.shadowColor = '#ff4422'; ctx.shadowBlur = 8; ctx.stroke();
    // Direction
    ctx.strokeStyle = 'rgba(255,100,80,0.5)'; ctx.lineWidth = 1; ctx.shadowBlur = 0;
    ctx.setLineDash([3,3]);
    ctx.beginPath();
    ctx.moveTo(enemy.x, enemy.y);
    ctx.lineTo(enemy.x + Math.cos(enemy.facing)*28, enemy.y + Math.sin(enemy.facing)*28);
    ctx.stroke(); ctx.setLineDash([]);
    // HP bar
    const bw = enemy.r * 2, bh = 3;
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.fillRect(enemy.x - bw/2 - 1, enemy.y - enemy.r - 8, bw + 2, bh + 2);
    ctx.fillStyle = '#ff6644';
    ctx.fillRect(enemy.x - bw/2, enemy.y - enemy.r - 7, bw * (enemy.hp / ENEMY_HP), bh);
    ctx.restore();
  }
}

function _drawBullets() {
  ctx.save();
  for (const b of RS.bullets) {
    ctx.beginPath(); ctx.arc(b.x, b.y, b.r, 0, Math.PI * 2);
    ctx.fillStyle   = b.owner === 'player' ? '#ffffaa' : '#ff8866';
    ctx.shadowColor = b.owner === 'player' ? '#ffffff'  : '#ff4422';
    ctx.shadowBlur  = 8; ctx.fill();
  }
  ctx.restore();
}
