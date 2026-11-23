// The toolbar icon, drawn like Cool Head's menu bar icon (Sources/CoolHeadApp/CoolHeadApp.swift, MenuIcon.badged):
// the melting snowflake in the toolbar's icon color, with ice-blue drops and a puddle, and a status badge at its top
// right whose shape and color both carry the level, for people who can't tell the colors apart: green circle, memory
// is fine; yellow triangle, memory is tight or slowing the Mac; red octagon, memory is very tight. No badge when
// there's no reading from Cool Head, since Chrome's own memory figure on a Mac doesn't say whether memory is short.
// Drawn in the menu bar icon's 20 by 18 point box, y up, and scaled, so it's sharp at 16 and 32 pixels.

const ICE = '#59B8FF';
const BADGE = { good: '#34C759', warning: '#FFBD00', issue: '#FF3B30' };

// The level for the badge from Cool Head's memory reading (logic/auto.js currentMemory), or null for none.
export function toolbarLevel(memory) {
  if (memory === 'fine') return 'good';
  if (memory === 'tight' || memory === 'slowed') return 'warning';
  if (memory === 'veryTight') return 'issue';
  return null;
}

// The flake's arms, sagging, the lower ones shorter; returns the lower arms' tips, where the drops fall.
function droopingFlake(ctx, cx, cy, r, width) {
  const tips = [];
  for (let i = 0; i < 6; i++) {
    const a = (i * Math.PI) / 3 + Math.PI / 2;
    const lower = Math.sin(a) < -0.1;
    const len = r * (lower ? 0.78 : 0.95);
    const sag = lower ? 1.9 : 0.9;
    const end = [cx + Math.cos(a) * len, cy + Math.sin(a) * len - sag];
    const ctrl = [cx + Math.cos(a) * len * 0.55, cy + Math.sin(a) * len * 0.55];
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.bezierCurveTo(ctrl[0], ctrl[1], ctrl[0], ctrl[1], end[0], end[1]);
    const mid = [cx + Math.cos(a) * len * 0.58, cy + Math.sin(a) * len * 0.58 - sag * 0.45];
    for (const side of [-1, 1]) {
      const b = a + (side * Math.PI) / 4;
      ctx.moveTo(mid[0], mid[1]);
      ctx.lineTo(mid[0] + Math.cos(b) * len * 0.34, mid[1] + Math.sin(b) * len * 0.34 - sag * 0.5);
    }
    ctx.lineWidth = width;
    ctx.lineCap = 'round';
    ctx.stroke();
    if (lower) tips.push(end);
  }
  return tips;
}

function drop(ctx, x, y, d) {
  ctx.beginPath();
  ctx.moveTo(x, y + d * 1.4);
  ctx.bezierCurveTo(x - d * 0.9, y, x - d * 0.6, y - d * 0.5, x, y - d * 0.5);
  ctx.bezierCurveTo(x + d * 0.6, y - d * 0.5, x + d * 0.9, y, x, y + d * 1.4);
  ctx.fill();
}

function badgePath(ctx, level, x, y, w) {
  const cx = x + w / 2, cy = y + w / 2;
  ctx.beginPath();
  if (level === 'good') {
    ctx.arc(cx, cy, w / 2 - 0.5, 0, Math.PI * 2);
  } else if (level === 'warning') {
    const side = w * 1.22, h = (side * Math.sqrt(3)) / 2, my = cy + w * 0.04;
    const top = [cx, my + h / 2], right = [cx + side / 2, my - h / 2], left = [cx - side / 2, my - h / 2];
    const rad = side * 0.16;
    ctx.moveTo(cx, left[1]);
    ctx.arcTo(right[0], right[1], top[0], top[1], rad);
    ctx.arcTo(top[0], top[1], left[0], left[1], rad);
    ctx.arcTo(left[0], left[1], right[0], right[1], rad);
    ctx.closePath();
  } else {
    for (let i = 0; i < 8; i++) {
      const a = (i * Math.PI) / 4 + Math.PI / 8;
      const px = cx + (Math.cos(a) * w) / 2, py = cy + (Math.sin(a) * w) / 2;
      if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.closePath();
  }
}

// Draws the icon into a 2D context of `size` pixels. `dark` is whether Chrome's toolbar is dark, for the flake's color.
export function drawToolbarIcon(ctx, size, level, dark) {
  const s = size / 20;
  ctx.save();
  ctx.clearRect(0, 0, size, size);
  // the menu bar box is 20 by 18, y up: flip it, and center it in the square
  ctx.translate(0, size - (size - 18 * s) / 2);
  ctx.scale(s, -s);
  ctx.strokeStyle = dark ? '#E8EAED' : '#3C4043';
  const tips = droopingFlake(ctx, 8.5, 10.2, 6.4, size <= 16 ? 1.6 : 1.4);
  ctx.fillStyle = ICE;
  tips.forEach((t, k) => drop(ctx, t[0], t[1] - 2.2 - (k % 2) * 0.7, 1.0));
  ctx.beginPath();
  ctx.ellipse(8.5, 1.3, 5, 0.9, 0, 0, Math.PI * 2);
  ctx.fill();
  if (level) {
    // a clear ring around the badge so it stands apart from the flake
    const x = 12, y = 10.5, w = 7.5;
    ctx.save();
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(x + w / 2, y + w / 2, w / 2 + (level === 'warning' ? 1.6 : 1), 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
    badgePath(ctx, level, x, y, w);
    ctx.fillStyle = BADGE[level];
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.45)';
    ctx.lineWidth = 0.6;
    ctx.stroke();
  }
  ctx.restore();
}
