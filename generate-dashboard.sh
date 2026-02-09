#!/bin/bash
# Generates the usage tracking HTML dashboard from JSONL data.
# Reads: ~/.claude/usage-tracking.jsonl, /tmp/claude-usage-cache.json, /tmp/claude-statusline-stdin.json
# Writes: ~/.claude/usage-dashboard.html

TRACKING_FILE="$HOME/.claude/usage-tracking.jsonl"
DASHBOARD_FILE="$HOME/.claude/usage-dashboard.html"
CACHE_FILE="/tmp/claude-usage-cache.json"
STDIN_FILE="/tmp/claude-statusline-stdin.json"

# Build JSONL array
JSONL_DATA="[]"
if [ -f "$TRACKING_FILE" ]; then
    JSONL_DATA="[$(paste -sd',' "$TRACKING_FILE")]"
fi

# Current usage from cache (guard against empty reads from race conditions)
CURRENT_JSON="{}"
if [ -f "$CACHE_FILE" ]; then
    TMP=$(cat "$CACHE_FILE" 2>/dev/null)
    [ -n "$TMP" ] && CURRENT_JSON="$TMP"
fi

# Session info from stdin log
SESSION_JSON="{}"
if [ -f "$STDIN_FILE" ]; then
    TMP=$(cat "$STDIN_FILE" 2>/dev/null)
    [ -n "$TMP" ] && SESSION_JSON="$TMP"
fi

# Write the HTML in parts, injecting data directly to avoid sed/perl escaping issues
{
cat << 'PART1'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Claude Code Usage Tracking</title>
<style>
  :root {
    --bg: #1a1b26;
    --surface: #24283b;
    --surface2: #2f3349;
    --text: #c0caf5;
    --text-dim: #565f89;
    --cyan: #7dcfff;
    --green: #9ece6a;
    --yellow: #e0af68;
    --red: #f7768e;
    --magenta: #bb9af7;
    --blue: #7aa2f7;
    --orange: #ff9e64;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: 'SF Mono', 'Fira Code', 'JetBrains Mono', monospace;
    background: var(--bg);
    color: var(--text);
    padding: 24px;
    min-height: 100vh;
  }
  h1 { font-size: 1.4em; color: var(--cyan); margin-bottom: 4px; }
  .subtitle { color: var(--text-dim); font-size: 0.85em; margin-bottom: 24px; }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
  }
  .card { background: var(--surface); border-radius: 8px; padding: 20px; }
  .card h2 {
    font-size: 0.9em; color: var(--text-dim);
    text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 12px;
  }
  .metric { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
  .metric-label { color: var(--text-dim); font-size: 0.85em; }
  .metric-value { font-size: 1.3em; font-weight: bold; }
  .bar-wrap { width: 100%; height: 8px; background: var(--surface2); border-radius: 4px; margin: 4px 0 12px; overflow: hidden; }
  .bar { height: 100%; border-radius: 4px; transition: width 0.3s; }
  .color-green { color: var(--green); } .color-yellow { color: var(--yellow); } .color-red { color: var(--red); }
  .bar-green { background: var(--green); } .bar-yellow { background: var(--yellow); } .bar-red { background: var(--red); }
  .wide { grid-column: 1 / -1; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
  th { text-align: left; color: var(--text-dim); padding: 6px 8px; border-bottom: 1px solid var(--surface2); }
  td { padding: 6px 8px; border-bottom: 1px solid var(--surface2); }
  .chart-box { width: 100%; height: 220px; position: relative; margin-top: 8px; }
  canvas { width: 100% !important; height: 100% !important; }
  .info-row { display: flex; gap: 24px; flex-wrap: wrap; margin-bottom: 8px; }
  .info-row span { font-size: 0.85em; }
  .info-row .lbl { color: var(--text-dim); }
  .empty { color: var(--text-dim); text-align: center; padding: 40px; font-style: italic; }
  .range-sel { display: flex; gap: 2px; }
  .range-sel button {
    background: none; border: none; color: var(--text-dim);
    padding: 2px 6px; font-family: inherit; font-size: 0.8em; cursor: pointer; border-radius: 3px;
  }
  .range-sel button:hover { color: var(--text); }
  .range-sel button.on { background: var(--surface2); color: var(--cyan); font-weight: bold; }
  .chart-tooltip {
    position: absolute;
    background: var(--surface2);
    border: 1px solid #3b4261;
    border-radius: 6px;
    padding: 8px 12px;
    font-size: 0.8em;
    pointer-events: none;
    white-space: nowrap;
    z-index: 10;
    display: none;
  }
  .chart-tooltip .tt-time { color: var(--text-dim); margin-bottom: 4px; }
  .chart-tooltip .tt-row { display: flex; align-items: center; gap: 6px; line-height: 1.6; }
  .chart-tooltip .tt-dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
</style>
</head>
<body>
<h1>Claude Code Usage Tracking</h1>
<div class="subtitle">Dashboard generated <span id="gen-time"></span></div>

<div class="grid">
  <div class="card">
    <h2>Current Session</h2>
    <div class="metric"><span class="metric-label">Session usage</span><span class="metric-value" id="s-pct">-</span></div>
    <div class="bar-wrap"><div class="bar" id="s-bar"></div></div>
    <div class="metric"><span class="metric-label">Resets at</span><span id="s-reset" style="color:var(--text-dim)">-</span></div>
  </div>
  <div class="card">
    <h2>Weekly (All Models)</h2>
    <div class="metric"><span class="metric-label">Weekly usage</span><span class="metric-value" id="w-pct">-</span></div>
    <div class="bar-wrap"><div class="bar" id="w-bar"></div></div>
  </div>
  <div class="card">
    <h2>Weekly (Sonnet Only)</h2>
    <div class="metric"><span class="metric-label">Sonnet usage</span><span class="metric-value" id="sn-pct">-</span></div>
    <div class="bar-wrap"><div class="bar" id="sn-bar"></div></div>
  </div>
  <div class="card">
    <h2>Last Active Session <span style="text-transform:none;letter-spacing:0;font-weight:normal;font-size:0.85em">(most recent terminal)</span></h2>
    <div class="info-row">
      <span><span class="lbl">Model:</span> <span id="i-model">-</span></span>
      <span><span class="lbl">Context:</span> <span id="i-ctx">-</span></span>
      <span><span class="lbl">Cost:</span> <span id="i-cost">-</span></span>
    </div>
    <div class="info-row">
      <span><span class="lbl">Input tokens:</span> <span id="i-in">-</span></span>
      <span><span class="lbl">Output tokens:</span> <span id="i-out">-</span></span>
    </div>
    <div class="info-row">
      <span><span class="lbl">Cache read:</span> <span id="i-cr">-</span></span>
      <span><span class="lbl">Cache write:</span> <span id="i-cw">-</span></span>
    </div>
    <div class="info-row">
      <span><span class="lbl">Lines +/-:</span> <span id="i-lines">-</span></span>
      <span><span class="lbl">Duration:</span> <span id="i-dur">-</span></span>
    </div>
  </div>

  <div class="card wide">
    <h2 style="display:flex;justify-content:space-between;align-items:center">
      <span>Usage Over Time</span>
      <div class="range-sel" id="range-sel">
        <button data-h="24">1d</button>
        <button data-h="48">2d</button>
        <button data-h="120">5d</button>
        <button data-h="168">1w</button>
        <button data-h="336">2w</button>
        <button data-h="720">1m</button>
        <button data-h="1440">2m</button>
        <button data-h="2160">3m</button>
        <button data-h="4320">6m</button>
        <button data-h="8760">1y</button>
        <button data-h="0" class="on">all</button>
      </div>
    </h2>
    <div class="chart-box"><canvas id="chart"></canvas></div>
  </div>

  <div class="card wide">
    <h2>Fetch History</h2>
    <div id="hist"></div>
  </div>
</div>

<script>
PART1

# Inject data as JS variables (raw JSON, no escaping needed)
echo "const trackingData = $JSONL_DATA;"
echo "const currentUsage = $CURRENT_JSON;"
echo "const sessionInfo = $SESSION_JSON;"

cat << 'PART2'

document.getElementById('gen-time').textContent = new Date().toLocaleString();

function pctColor(p) { return p < 50 ? 'green' : p < 75 ? 'yellow' : 'red'; }
function fmt(n) { return n == null || isNaN(n) ? '-' : n.toLocaleString(); }
function fmtDur(ms) {
  if (!ms) return '-';
  var m = Math.floor(ms/60000);
  return m < 60 ? m+'m' : Math.floor(m/60)+'h '+m%60+'m';
}
function setBar(id, pct) {
  var e = document.getElementById(id); if (!e) return;
  var c = pctColor(pct);
  e.style.width = Math.min(pct,100)+'%';
  e.className = 'bar bar-'+c;
}
function setVal(id, v, suf) {
  var e = document.getElementById(id); if (!e) return;
  suf = suf||'';
  var p = parseInt(v);
  if (!isNaN(p)) e.className = 'metric-value color-'+pctColor(p);
  e.textContent = v+suf;
}

// Current usage
if (currentUsage && currentUsage.session_pct != null) {
  setVal('s-pct', currentUsage.session_pct, '%');
  setBar('s-bar', currentUsage.session_pct);
  document.getElementById('s-reset').textContent = currentUsage.session_reset || '-';
  setVal('w-pct', currentUsage.weekly_pct, '%');
  setBar('w-bar', currentUsage.weekly_pct);
  setVal('sn-pct', currentUsage.sonnet_pct, '%');
  setBar('sn-bar', currentUsage.sonnet_pct);
}

// Session info
if (sessionInfo && sessionInfo.model) {
  var mod = sessionInfo.model||{}, cost = sessionInfo.cost||{};
  var ctx = sessionInfo.context_window||{}, cur = ctx.current_usage||{};
  document.getElementById('i-model').textContent = mod.display_name||'-';
  document.getElementById('i-ctx').textContent = (ctx.used_percentage||0)+'%';
  document.getElementById('i-cost').textContent = cost.total_cost_usd!=null ? '$'+cost.total_cost_usd.toFixed(2) : '-';
  document.getElementById('i-in').textContent = fmt(ctx.total_input_tokens);
  document.getElementById('i-out').textContent = fmt(ctx.total_output_tokens);
  document.getElementById('i-cr').textContent = fmt(cur.cache_read_input_tokens);
  document.getElementById('i-cw').textContent = fmt(cur.cache_creation_input_tokens);
  document.getElementById('i-lines').textContent =
    cost.total_lines_added!=null ? '+'+fmt(cost.total_lines_added)+' / -'+fmt(cost.total_lines_removed) : '-';
  document.getElementById('i-dur').textContent = fmtDur(cost.total_duration_ms);
}

// Chart
var chartState = null;
function drawChart(hoverTime) {
  var canvas = document.getElementById('chart');
  if (!canvas || !trackingData.length) {
    var c = canvas?canvas.parentElement:null;
    if (c) c.innerHTML = '<div class="empty">No tracking data yet. Usage is recorded every ~5 minutes.</div>';
    return;
  }
  var cx = canvas.getContext('2d');
  var rect = canvas.parentElement.getBoundingClientRect();
  var dpr = window.devicePixelRatio||1;
  canvas.width = rect.width*dpr; canvas.height = rect.height*dpr;
  cx.scale(dpr,dpr);
  var W = rect.width, H = rect.height;
  var pad = {t:40,r:20,b:40,l:45};
  var pW = W-pad.l-pad.r, pH = H-pad.t-pad.b;

  var allPts = trackingData.map(function(d){
    return {t:new Date(d.timestamp).getTime(), s:d.session_pct||0, w:d.weekly_pct||0, sn:d.sonnet_pct||0, sr:d.session_reset||''};
  }).sort(function(a,b){return a.t-b.t;});
  if (!allPts.length) return;

  // Apply time range filter from selected pill
  var activeBtn = document.querySelector('#range-sel .on');
  var hoursBack = parseInt(activeBtn ? activeBtn.dataset.h : 0);
  var pts;
  if (hoursBack === 0) {
    pts = allPts;
  } else {
    var cutoff = Date.now() - hoursBack * 3600000;
    pts = allPts.filter(function(p){ return p.t >= cutoff; });
    if (!pts.length) pts = allPts;
  }

  var t0=pts[0].t, t1=pts[pts.length-1].t, tr=t1-t0||1;
  function xp(t){return pad.l+((t-t0)/tr)*pW;}
  function yp(v){return pad.t+pH-(v/100)*pH;}

  // Grid
  cx.strokeStyle='#2f3349'; cx.lineWidth=1;
  for(var v=0;v<=100;v+=25){
    cx.beginPath();cx.moveTo(pad.l,yp(v));cx.lineTo(W-pad.r,yp(v));cx.stroke();
    cx.fillStyle='#565f89';cx.font='11px monospace';cx.textAlign='right';
    cx.fillText(v+'%',pad.l-6,yp(v)+4);
  }

  // Reset lines — detect drops in usage % which indicate a reset occurred
  cx.setLineDash([6,4]);
  cx.lineWidth=1;
  for(var i=1;i<pts.length;i++){
    // Session reset: only when session_pct actually drops (not string comparison —
    // the reset time string varies in format e.g. "1:59pm" vs "2pm" for the same window)
    if(pts[i].s < pts[i-1].s - 2){
      var rx = xp(pts[i].t + 5 * 60000);
      cx.strokeStyle='#7dcfff';
      cx.beginPath();cx.moveTo(rx, pad.t);cx.lineTo(rx, pad.t+pH);cx.stroke();
    }
    // Weekly reset: weekly_pct drops
    if(pts[i].w < pts[i-1].w - 2){
      var rx = xp(pts[i].t + 5 * 60000);
      cx.strokeStyle='#e0af68';
      cx.beginPath();cx.moveTo(rx, pad.t);cx.lineTo(rx, pad.t+pH);cx.stroke();
    }
  }
  cx.setLineDash([]);

  // Time labels
  cx.textAlign='center';
  var lc=Math.min(8,pts.length), st=Math.max(1,Math.floor(pts.length/lc));
  for(var i=0;i<pts.length;i+=st){
    var d=new Date(pts[i].t);
    var lb=(d.getMonth()+1)+'/'+d.getDate()+' '+
      ('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2);
    cx.fillStyle='#565f89';cx.fillText(lb,xp(pts[i].t),H-pad.b+20);
  }

  // Lines
  function drawLine(key,color){
    cx.strokeStyle=color;cx.lineWidth=2;cx.beginPath();
    pts.forEach(function(p,i){
      var px=xp(p.t),py=yp(p[key]);
      if(i===0){cx.moveTo(px,py);}
      else if(p[key] < pts[i-1][key] - 2){
        cx.lineTo(px,yp(pts[i-1][key]));
        cx.lineTo(px,py);
      } else {cx.lineTo(px,py);}
    });
    cx.stroke();
    cx.fillStyle=color;
    pts.forEach(function(p){
      cx.beginPath();cx.arc(xp(p.t),yp(p[key]),3,0,Math.PI*2);cx.fill();
    });
  }
  drawLine('s','#7dcfff');
  drawLine('w','#e0af68');
  drawLine('sn','#bb9af7');

  // Legend
  cx.font='11px monospace'; cx.textBaseline='middle';
  var ly=pad.t-20, lx=pad.l;
  [['session','#7dcfff'],['weekly','#e0af68'],['sonnet','#bb9af7']].forEach(function(a){
    cx.strokeStyle=a[1];cx.lineWidth=2;cx.setLineDash([]);
    cx.beginPath();cx.moveTo(lx,ly);cx.lineTo(lx+16,ly);cx.stroke();
    cx.fillStyle=a[1];cx.beginPath();cx.arc(lx+8,ly,3,0,Math.PI*2);cx.fill();
    cx.fillStyle=a[1];cx.textAlign='left';cx.fillText(a[0],lx+22,ly);
    lx+=cx.measureText(a[0]).width+42;
  });
  cx.setLineDash([4,3]);cx.lineWidth=1;cx.strokeStyle='#565f89';
  cx.beginPath();cx.moveTo(lx,ly);cx.lineTo(lx+16,ly);cx.stroke();
  cx.setLineDash([]);
  cx.fillStyle='#565f89';cx.textAlign='left';cx.fillText('reset',lx+22,ly);
  cx.textBaseline='alphabetic';

  // Hover crosshair + highlighted dots
  if (hoverTime != null) {
    var nearest = null, minDist = Infinity;
    pts.forEach(function(p) {
      var dist = Math.abs(p.t - hoverTime);
      if (dist < minDist) { minDist = dist; nearest = p; }
    });
    if (nearest) {
      var hx = xp(nearest.t);
      cx.strokeStyle = '#565f89'; cx.lineWidth = 1; cx.setLineDash([3,3]);
      cx.beginPath(); cx.moveTo(hx, pad.t); cx.lineTo(hx, pad.t+pH); cx.stroke();
      cx.setLineDash([]);
      [['s','#7dcfff'],['w','#e0af68'],['sn','#bb9af7']].forEach(function(a) {
        cx.fillStyle = a[1];
        cx.beginPath(); cx.arc(xp(nearest.t), yp(nearest[a[0]]), 5, 0, Math.PI*2); cx.fill();
      });
    }
  }
  chartState = { pts: pts, xp: xp, yp: yp, pad: pad, W: W, H: H, pW: pW, pH: pH };
}
drawChart();
window.addEventListener('resize',function(){ drawChart(); });

// Tooltip for chart hover
var chartTooltip = document.createElement('div');
chartTooltip.className = 'chart-tooltip';
document.getElementById('chart').parentElement.appendChild(chartTooltip);

document.getElementById('chart').addEventListener('mousemove', function(e) {
  if (!chartState) return;
  var rect = e.target.getBoundingClientRect();
  var mx = e.clientX - rect.left;
  var nearest = null, minDist = Infinity;
  chartState.pts.forEach(function(p) {
    var dist = Math.abs(chartState.xp(p.t) - mx);
    if (dist < minDist) { minDist = dist; nearest = p; }
  });
  if (!nearest || minDist > 30) {
    chartTooltip.style.display = 'none';
    drawChart();
    return;
  }
  drawChart(nearest.t);
  var d = new Date(nearest.t);
  var timeStr = (d.getMonth()+1)+'/'+d.getDate()+' '+
    ('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2);
  chartTooltip.innerHTML = '<div class="tt-time">'+timeStr+'</div>' +
    '<div class="tt-row"><span class="tt-dot" style="background:#7dcfff"></span>Session: '+nearest.s+'%</div>' +
    '<div class="tt-row"><span class="tt-dot" style="background:#e0af68"></span>Weekly: '+nearest.w+'%</div>' +
    '<div class="tt-row"><span class="tt-dot" style="background:#bb9af7"></span>Sonnet: '+nearest.sn+'%</div>';
  chartTooltip.style.display = 'block';
  var tx = chartState.xp(nearest.t) + 12;
  var ty = e.clientY - rect.top - 40;
  if (tx + chartTooltip.offsetWidth > chartState.W) tx = chartState.xp(nearest.t) - chartTooltip.offsetWidth - 12;
  if (ty < 0) ty = 0;
  chartTooltip.style.left = tx + 'px';
  chartTooltip.style.top = ty + 'px';
});
document.getElementById('chart').addEventListener('mouseleave', function() {
  chartTooltip.style.display = 'none';
  drawChart();
});

document.querySelectorAll('#range-sel button').forEach(function(btn){
  btn.addEventListener('click', function(){
    document.querySelector('#range-sel .on').classList.remove('on');
    btn.classList.add('on');
    drawChart();
  });
});

// History table
(function(){
  var el=document.getElementById('hist');
  if(!trackingData.length){el.innerHTML='<div class="empty">No tracking data yet.</div>';return;}
  var rows=trackingData.slice().reverse().slice(0,100);
  var h='<table><thead><tr><th>Time</th><th>Session</th><th>Weekly</th><th>Sonnet</th><th>Reset</th></tr></thead><tbody>';
  rows.forEach(function(d){
    var t=new Date(d.timestamp);
    var ts=t.toLocaleDateString()+' '+t.toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'});
    h+='<tr><td>'+ts+'</td>';
    h+='<td class="color-'+pctColor(d.session_pct||0)+'">'+(d.session_pct||0)+'%</td>';
    h+='<td class="color-'+pctColor(d.weekly_pct||0)+'">'+(d.weekly_pct||0)+'%</td>';
    h+='<td class="color-'+pctColor(d.sonnet_pct||0)+'">'+(d.sonnet_pct||0)+'%</td>';
    h+='<td style="color:var(--text-dim)">'+(d.session_reset||'-')+'</td></tr>';
  });
  h+='</tbody></table>';
  el.innerHTML=h;
})();
</script>
</body>
</html>
PART2
} > "$DASHBOARD_FILE"

echo "Dashboard generated at $DASHBOARD_FILE"
