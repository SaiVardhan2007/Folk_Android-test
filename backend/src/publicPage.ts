// The public registration / volunteer / feedback page. One self-contained HTML document (no external fonts, scripts or images),
// served by the Worker at /f/:slug and opened from a WhatsApp link. All user text is inserted with textContent, never innerHTML.

export type PageConfig = {
  slug: string;
  title: string;
  type: "Registration" | "Volunteer" | "Feedback";
  eventName: string;
  open: boolean;
  intro: string;
  asks: { dinner: boolean; transport: boolean; donation: boolean };
  slots: string[];
  services: string[];
  genders: { value: string; label: string }[];
  occupations: string[];
  /** College / Company values people can pick (the form adds "Others" at the bottom; it cannot add new values). */
  colleges: { value: string; label: string }[];
  areas: { value: string; label: string }[];
};

/** JSON that is safe inside a <script type="application/json"> block. */
const safeJson = (v: unknown) => JSON.stringify(v).replace(/</g, "\\u003c").replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

// ---- design tokens (same palette as the app's lib/core/theme.dart). Change colours and sizes here only.
const CSS = `
:root{
  --brand:#C75B12; --brand-dark:#6E1F2F; --on-brand:#FFFFFF;
  --page:#FFF8EE; --card:#FFFFFF; --soft:#F7EAD6; --line:#EBD9C2;
  --ink:#2B1B14; --muted:#5E4A3F; --success:#2F7D4A; --danger:#B3261E;
  --radius:16px; --gap:16px; --text:18px; --text-small:16px; --field-height:56px;
  --font:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--page);color:var(--ink);font:var(--text)/1.5 var(--font)}
header{background:linear-gradient(135deg,var(--brand-dark),#9A3B22 60%,var(--brand));color:var(--on-brand);padding:28px var(--gap) 24px}
header .brand{font-weight:800;letter-spacing:.12em;font-size:var(--text-small);opacity:.9}
header h1{margin:6px 0 4px;font-size:26px;line-height:1.25}
header p{margin:0;font-size:var(--text-small);opacity:.92}
main{width:100%;max-width:640px;margin:0 auto;padding:var(--gap)}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);padding:var(--gap);margin-bottom:var(--gap)}
label{display:block;font-weight:600;margin:14px 0 6px}
input,select,textarea{width:100%;height:var(--field-height);padding:0 14px;font:inherit;color:var(--ink);background:#fff;border:1.5px solid var(--line);border-radius:12px}
input:focus,select:focus,textarea:focus{outline:3px solid #FFE2C8;border-color:var(--brand)}
.stars{display:flex;gap:8px;margin:6px 0}
.stars button{flex:1;margin:0;height:var(--field-height);background:#fff;color:var(--muted);border:1.5px solid var(--line);font-size:26px;font-weight:700}
.stars button.on{background:var(--brand);color:var(--on-brand);border-color:var(--brand)}
textarea{height:auto;min-height:96px;padding:12px 14px;resize:vertical}
.check{display:flex;align-items:center;gap:12px;margin:14px 0;font-weight:500}
.check input{width:26px;height:26px;flex:none;accent-color:var(--brand)}
button{width:100%;height:var(--field-height);margin-top:18px;border:0;border-radius:14px;background:var(--brand);color:var(--on-brand);font:inherit;font-weight:700;cursor:pointer}
button:disabled{opacity:.6;cursor:default}
button.link{background:none;color:var(--brand);height:48px;margin-top:6px}
.row{display:flex;justify-content:space-between;gap:12px;padding:10px 0;border-bottom:1px solid var(--line)}
.row:last-child{border-bottom:0}
.row span:first-child{color:var(--muted)}
.row span:last-child{font-weight:600;text-align:right}
.note{background:var(--soft);border-radius:12px;padding:12px 14px;font-size:var(--text-small)}
.error{color:var(--danger);font-weight:600;margin-top:12px}
.done{text-align:center;padding:28px var(--gap)}
.done .tick{width:72px;height:72px;border-radius:50%;background:var(--success);color:#fff;font-size:42px;line-height:72px;margin:0 auto 14px}
.thanks{position:relative;overflow:hidden;border:2px solid #D9A441;background:linear-gradient(180deg,#FFF3DA 0%,#FFFFFF 55%,#FFF3DA 100%);padding:32px var(--gap) 26px}
.thanks h2{font-size:28px;color:var(--brand-dark);margin:8px 0 6px}
.thanks p{margin:0 0 10px}
.thanks svg{display:block;margin:0 auto}
.thanks .om{font-size:30px;color:var(--brand);line-height:1;margin-bottom:2px}
.thanks .mantra{margin:18px 0 6px;padding:14px 12px;border-radius:14px;background:var(--brand-dark);color:#FFE9B8;font-family:Georgia,"Times New Roman",serif;font-style:italic;font-size:17px;line-height:1.6}
.thanks .sign{color:var(--muted);font-size:var(--text-small);margin-top:12px}
.hp{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
h2{margin:0 0 4px;font-size:21px}
.sub{color:var(--muted);font-size:var(--text-small);margin:0 0 6px}
.mb{margin-bottom:var(--gap)}
.top{margin-top:40px}
`;

const SCRIPT = `
(function(){
  var C = JSON.parse(document.getElementById('cfg').textContent);
  var app = document.getElementById('app');
  var state = { mob: '', found: false, person: null, registered: false, rating: 0, started: Date.now() };

  function el(tag, props, kids){
    var n = document.createElement(tag);
    for (var k in (props||{})) { if (k === 'text') n.textContent = props[k]; else if (k === 'class') n.className = props[k]; else n.setAttribute(k, props[k]); }
    (kids||[]).forEach(function(c){ if (c) n.appendChild(c); });
    return n;
  }
  function field(label, input){ return el('div', {}, [el('label', {text: label}), input]); }
  function clear(){ while (app.firstChild) app.removeChild(app.firstChild); }
  // Mobile data can be slow: show a hint after 5 s, give up after 25 s and try once more. Safe to repeat: registering twice only updates the same record.
  var hint = el('div', {class:'note mb', hidden:'hidden', text:'Slow connection. Still trying, please wait...'});
  app.parentNode.insertBefore(hint, app);
  function post(path, body){
    function attempt(n){
      var ctrl = new AbortController();
      var giveUp = setTimeout(function(){ ctrl.abort(); }, 25000);
      var slow = setTimeout(function(){ hint.hidden = false; }, 5000);
      return fetch('/pub/' + C.slug + '/' + path, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body), signal: ctrl.signal })
        .then(function(r){ return r.json().then(function(j){ if (!r.ok) { var e = new Error(j.error || 'Something went wrong. Please try again.'); e.server = true; throw e; } return j; }); })
        .catch(function(e){
          if (e.server) throw e;
          if (n < 2) return attempt(n + 1);
          throw new Error('Could not reach the server. Please check your internet connection and try again.');
        })
        .then(function(v){ clearTimeout(giveUp); clearTimeout(slow); hint.hidden = true; return v; },
              function(e){ clearTimeout(giveUp); clearTimeout(slow); hint.hidden = true; throw e; });
    }
    return attempt(1);
  }
  function select(id, options, placeholder){
    var s = el('select', {id: id});
    s.appendChild(el('option', {value:'', text: placeholder || 'Choose'}));
    options.forEach(function(o){ var v = typeof o === 'string' ? o : o.value, t = typeof o === 'string' ? o : o.label; s.appendChild(el('option', {value: v, text: t})); });
    return s;
  }
  function area(id, max){ return el('textarea', {id: id, maxlength: String(max || 500), rows: '3'}); }
  function val(id){ var x = document.getElementById(id); return x ? x.value.trim() : ''; }
  function chk(id){ var x = document.getElementById(id); return !!(x && x.checked); }
  function check(id, text){ return el('label', {class:'check'}, [el('input', {type:'checkbox', id:id}), el('span', {text:text})]); }

  function stepPhone(){
    clear();
    var phone = el('input', {id:'mob', type:'tel', inputmode:'numeric', autocomplete:'tel-national', maxlength:'15', placeholder:'10-digit mobile number'});
    var err = el('div', {class:'error', role:'alert'});
    var btn = el('button', {type:'submit', text:'Continue'});
    var form = el('form', {class:'card', novalidate:''}, [
      el('h2', {text:'Enter your mobile number'}),
      el('p', {class:'sub', text:'We will check if you are already in our list.'}),
      phone, err, btn
    ]);
    phone.addEventListener('input', function(){ phone.value = phone.value.replace(/[^0-9+ -]/g, ''); });
    form.addEventListener('submit', function(e){
      e.preventDefault(); err.textContent = '';
      var digits = phone.value.replace(/\\D/g, '');
      if (digits.length === 12 && digits.indexOf('91') === 0) digits = digits.slice(2);
      if (digits.length === 11 && digits.charAt(0) === '0') digits = digits.slice(1);
      if (!/^[6-9]\\d{9}$/.test(digits)) { err.textContent = 'Please enter a valid 10-digit mobile number.'; return; }
      btn.disabled = true; btn.textContent = 'Checking...';
      post('lookup', { mob: digits }).then(function(r){
        state.mob = digits; state.found = r.found; state.person = r.person || null; state.registered = !!r.registered;
        stepDetails();
      }).catch(function(e2){ err.textContent = e2.message; btn.disabled = false; btn.textContent = 'Continue'; });
    });
    app.appendChild(form);
    phone.focus();
  }

  function genderLabel(v){ for (var i=0;i<C.genders.length;i++) if (C.genders[i].value === v) return C.genders[i].label; return ''; }
  function row(k, v){ return v ? el('div', {class:'row'}, [el('span', {text:k}), el('span', {text:v})]) : null; }

  function stepDetails(){
    clear();
    var kids = [];
    if (state.found) {
      var p = state.person;
      kids.push(el('div', {class:'card'}, [
        el('h2', {text:'Hare Krishna, ' + p.name.split(' ')[0] + '!'}),
        el('p', {class:'sub', text:'These are your details from our list.'}),
        row('Name', p.name), row('Mobile', state.mob), row('Gender', genderLabel(p.gender)), row('Occupation', p.occupation),
        row('College / Company', p.profession), row('Area', p.venue)
      ]));
      if (state.registered && C.type === 'Feedback') kids.push(el('div', {class:'note', text:'You have already sent feedback for this event. Submit again to replace it.'}));
      else if (state.registered) kids.push(el('div', {class:'note', text: C.type === 'Volunteer' ? 'You are already registered for this event. Submit again to update your volunteer choices.' : 'You are already registered for this event. Submit again to update your answers.'}));
    } else {
      kids.push(el('div', {class:'card'}, [
        el('h2', {text:'Welcome! Tell us about you'}),
        el('p', {class:'sub', text:'Mobile: ' + state.mob}),
        field('Full name *', el('input', {id:'name', type:'text', autocomplete:'name', maxlength:'100'})),
        C.type === 'Feedback' ? null : field('Gender *', select('gender', C.genders)),
        C.type === 'Feedback' ? null : field('Occupation', select('occupation', C.occupations)),
        C.type === 'Feedback' ? null : field('College / Company', select('college_id', (C.colleges || []).concat([{value:'other', label:'Others'}]))),
        C.type === 'Feedback' ? null : field('Area you stay in', select('area_id', (C.areas || []).concat([{value:'other', label:'Others'}])))
      ]));
    }
    var q = [];
    if (C.type === 'Feedback') {
      var stars = el('div', {class:'stars', id:'stars', role:'radiogroup', 'aria-label':'Rating'});
      for (var i = 1; i <= 5; i++) (function(n){
        var b = el('button', {type:'button', text: String(n), 'aria-label': n + ' out of 5'});
        b.addEventListener('click', function(){ state.rating = n; Array.prototype.forEach.call(stars.children, function(x, k){ x.className = k < n ? 'on' : ''; }); });
        stars.appendChild(b);
      })(i);
      q.push(el('div', {}, [el('label', {text:'How was it? (1 = poor, 5 = excellent) *'}), stars]));
      q.push(field('What did you like the most?', area('liked')));
      q.push(field('What can we do better?', area('improve')));
      q.push(field('Anything else you would like to tell us?', area('comments')));
    } else if (C.type === 'Volunteer') {
      if (C.slots.length) q.push(field('Which time can you serve? *', select('slot', C.slots)));
      if (C.services.length) q.push(field('Which service would you like to do?', select('service', C.services, 'Any / not sure')));
    } else {
      if (C.asks.dinner) q.push(check('dinner', 'I would like dinner'));
      if (C.asks.transport) q.push(check('transport', 'I need transport'));
      if (C.asks.donation) q.push(check('donation', 'I am interested in donating'));
    }
    if (q.length) kids.push(el('div', {class:'card'}, q));
    var err = el('div', {class:'error', role:'alert'});
    var btnText = C.type === 'Feedback' ? 'Send feedback' : (C.type === 'Volunteer' ? 'Register as volunteer' : 'Register');
    var btn = el('button', {type:'submit', text: btnText});
    var back = el('button', {type:'button', class:'link', text:'Use a different number'});
    back.addEventListener('click', stepPhone);
    var hp = el('div', {class:'hp', 'aria-hidden':'true'}, [el('input', {id:'website', type:'text', tabindex:'-1', autocomplete:'off'})]);
    var form = el('form', {novalidate:''}, kids.concat([hp, err, btn, back]));
    form.addEventListener('submit', function(e){
      e.preventDefault(); err.textContent = '';
      var body = { mob: state.mob, website: val('website'), waited: Date.now() - state.started };
      if (!state.found) {
        body.name = val('name'); body.gender = val('gender'); body.occupation = val('occupation'); body.college_id = val('college_id'); body.area_id = val('area_id');
        if (!body.name) { err.textContent = 'Please enter your name.'; return; }
        if (C.type !== 'Feedback' && !body.gender) { err.textContent = 'Please choose your gender.'; return; }
      }
      if (C.type === 'Feedback') {
        if (!state.rating) { err.textContent = 'Please choose a rating from 1 to 5.'; return; }
        body.rating = state.rating; body.liked = val('liked'); body.improve = val('improve'); body.comments = val('comments');
      } else if (C.type === 'Volunteer') {
        body.slot = val('slot'); body.service = val('service');
        if (C.slots.length && !body.slot) { err.textContent = 'Please choose a time slot.'; return; }
      } else { body.dinner = chk('dinner'); body.transport = chk('transport'); body.donation = chk('donation'); }
      btn.disabled = true; btn.textContent = 'Saving...';
      post('submit', body).then(function(r){ stepDone(r.name); })
        .catch(function(e2){ err.textContent = e2.message; btn.disabled = false; btn.textContent = btnText; });
    });
    app.appendChild(form);
    window.scrollTo(0, 0);
  }

  // A peacock feather (Krishna's crest), drawn in the page so it needs no image file.
  function feather(){
    var NS = 'http://www.w3.org/2000/svg';
    function n(tag, attrs){ var e = document.createElementNS(NS, tag); for (var k in attrs) e.setAttribute(k, attrs[k]); return e; }
    var svg = n('svg', {viewBox:'0 0 120 170', width:'96', height:'136', 'aria-hidden':'true'});
    var defs = n('defs', {}), g = n('radialGradient', {id:'eye', cx:'50%', cy:'50%', r:'50%'});
    [['0','#0B2A5B'],['0.35','#1D4FA3'],['0.6','#12A0A8'],['0.8','#1E8A5E'],['1','#D9A441']].forEach(function(s){ g.appendChild(n('stop', {offset:s[0], 'stop-color':s[1]})); });
    defs.appendChild(g); svg.appendChild(defs);
    for (var a = -70; a <= 70; a += 7) {
      var r = a * Math.PI / 180, x = 60 + Math.sin(r) * 54, y = 62 - Math.cos(r) * 58;
      svg.appendChild(n('line', {x1:'60', y1:'70', x2:String(x), y2:String(y), stroke:(a % 14 === 0 ? '#1E8A5E' : '#D9A441'), 'stroke-width':'1.4', 'stroke-linecap':'round', opacity:'0.85'}));
    }
    svg.appendChild(n('path', {d:'M60 165 C57 130 63 100 60 66', stroke:'#8A5A1F', 'stroke-width':'3', fill:'none', 'stroke-linecap':'round'}));
    svg.appendChild(n('ellipse', {cx:'60', cy:'62', rx:'26', ry:'34', fill:'url(#eye)', stroke:'#D9A441', 'stroke-width':'2'}));
    svg.appendChild(n('ellipse', {cx:'60', cy:'62', rx:'9', ry:'13', fill:'#0B2A5B'}));
    return svg;
  }

  function stepDone(name){
    clear();
    var first = (name || '').split(' ')[0];
    var msg = C.type === 'Feedback' ? 'Thank you for your feedback on ' + C.eventName + '. It helps us serve better.'
      : C.type === 'Volunteer' ? 'Thank you for offering to serve at ' + C.eventName + '. Your service pleases Krishna. We will contact you soon.'
      : 'Thank you for registering for ' + C.eventName + '. You are most welcome. We look forward to seeing you.';
    app.appendChild(el('div', {class:'card done thanks'}, [
      feather(),
      el('div', {class:'om', text:'\u0950'}),
      el('h2', {text:'Hare Krishna' + (first ? ', ' + first : '') + '!'}),
      el('p', {text: msg}),
      el('div', {class:'mantra', text:'Hare Krishna Hare Krishna Krishna Krishna Hare Hare \u00b7 Hare Rama Hare Rama Rama Rama Hare Hare'}),
      el('p', {class:'sign', text:'Your well-wishers at FOLK'})
    ]));
    window.scrollTo(0, 0);
  }

  if (!C.open) {
    app.appendChild(el('div', {class:'card done'}, [el('h2', {text: C.type === 'Feedback' ? 'Feedback is closed' : 'Registration is closed'}), el('p', {text:'This form is not taking responses right now. Please contact the FOLK team.'})]));
  } else { stepPhone(); }
})();
`;

export function renderPage(cfg: PageConfig, nonce: string): string {
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<meta name="theme-color" content="#6E1F2F">
<title>${esc(cfg.title)}</title>
<style nonce="${nonce}">${CSS}</style>
</head><body>
<header><div class="brand">FOLK</div><h1>${esc(cfg.title)}</h1><p>${esc(cfg.eventName)}</p></header>
<main>
${cfg.intro ? `<div class="note mb">${esc(cfg.intro)}</div>` : ""}
<div id="app"></div>
</main>
<script id="cfg" type="application/json">${safeJson(cfg)}</script>
<script nonce="${nonce}">${SCRIPT}</script>
</body></html>`;
}

export function notFoundPage(nonce: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Link not found</title><style nonce="${nonce}">${CSS}</style></head><body><main><div class="card done top"><h2>This link is not available</h2><p>Please check the link you were sent, or contact the FOLK team.</p></div></main></body></html>`;
}

export const pageHeaders = (nonce: string) => ({
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Content-Security-Policy": `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
});
