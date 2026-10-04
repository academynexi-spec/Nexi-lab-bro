'use strict';
if(typeof supabase==='undefined'){document.getElementById('stage').innerHTML='<p style="padding:24px;color:#ff6b7d;text-align:center">Impossible de charger Supabase (connexion internet requise au premier lancement). Recharge la page avec Ctrl+F5.</p>';throw Error('supabase-js non chargé')}
addEventListener('error',e=>{const s=document.getElementById('stage');if(s&&!s.children.length)s.innerHTML='<p style="padding:24px;color:#ff6b7d;text-align:center">Erreur : '+String(e.message).replace(/</g,'&lt;')+'<br>Ouvre F12 > Console pour le détail.</p>'});
const sb=supabase.createClient(NEXI.URL,NEXI.KEY);
const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>[...r.querySelectorAll(s)];
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const A=o=>esc(JSON.stringify(o));
const mail=l=>l.trim().toLowerCase()+'@nexilab.app';
let ME=null,ADMIN_UI=false,CFG={},SECT=[];
const RK=[[1e5,'Ultra Nexian'],[5e4,'Légende'],[25e3,'Prodige'],[10500,'Élite'],[8e3,'S'],[5e3,'A'],[2e3,'B'],[1e3,'C'],[500,'D'],[-1,'E']];
const rank=n=>RK.find(r=>n>r[0])[1];
const MED=['🏆','🥈','🥉'],MC=['g','s','b'];
const sectOpts=()=>SECT.map(s=>`<option value=${s.id}>${esc(s.name)}</option>`).join('');
const HELP={donjon:'Question | A;B;C;D (2) [20;10;5]  → temps s ; NX ; bonus rapidité',nexify:'Question | A;B;C;D (2) [3;30]  → facteur ×3 ; temps s',carte:'Question | Réponse détaillée et exemple'},HELPIMG=' — schéma : ajoute @nom.png en fin de ligne (carte : @q.png sur la question, @r.png sur la réponse)';

/* Son + vibration */
let ac;const beep=(f,d=.12,t='sine')=>{try{ac=ac||new AudioContext();const o=ac.createOscillator(),g=ac.createGain();o.type=t;o.frequency.value=f;g.gain.setValueAtTime(.15,ac.currentTime);g.gain.exponentialRampToValueAtTime(.001,ac.currentTime+d);o.connect(g);g.connect(ac.destination);o.start();o.stop(ac.currentTime+d)}catch{}};
const sfx={tap:()=>beep(440,.05),ok:()=>{beep(660);setTimeout(()=>beep(990,.2),90)},ko:()=>{beep(140,.3,'sawtooth');navigator.vibrate&&navigator.vibrate([80,40,120])}};
const toast=(m,c='')=>{const t=$('#toast');t.textContent=m;t.className='on '+c;clearTimeout(toast.t);toast.t=setTimeout(()=>t.className='',2600)};

/* Images (schémas) : bucket privé « diagrams », URL signées, zoom pincer/molette */
const IMG=new Map(),FA='image/png,image/jpeg,image/webp';
async function imgUrl(p){const c=IMG.get(p);if(c&&c.t>Date.now())return c.u;const {data}=await sb.storage.from('diagrams').createSignedUrl(p,3600);const u=data?.signedUrl||'';if(u)IMG.set(p,{u,t:Date.now()+3e6});return u}
/* Cache persistant des schémas : chaque image n'est téléchargée qu'une fois par appareil (économise la bande passante gratuite) */
const IMC='nexi-img-v1',OBJ=new Map();
async function imgSrc(p){if(OBJ.has(p))return OBJ.get(p);
  try{const c=await caches.open(IMC),k=new Request(location.origin+'/__img/'+encodeURIComponent(p));let r=await c.match(k);
    if(!r){const u=await imgUrl(p);if(!u)return '';const f=await fetch(u);if(!f.ok)throw Error('img');await c.put(k,f.clone());r=f;
      c.keys().then(K=>K.slice(0,Math.max(0,K.length-150)).forEach(x=>c.delete(x)))}
    const o=URL.createObjectURL(await r.blob());OBJ.set(p,o);return o}catch(e){return imgUrl(p)}}
const figure=p=>p?`<figure class=fig><img data-p="${esc(p)}" alt="Schéma" decoding=async><figcaption>🔍</figcaption></figure>`:'';
const imgBad=i=>{const p=document.createElement('p');p.className='err';p.textContent='Schéma indisponible';(i.closest('figure')||i).replaceWith(p)};
async function hydrate(el){await Promise.all($$('img[data-p]',el).map(async i=>{const u=await imgSrc(i.dataset.p);if(!u)return imgBad(i);i.onerror=()=>{IMG.delete(i.dataset.p);OBJ.delete(i.dataset.p);imgBad(i)};i.src=u;try{await i.decode()}catch{}}))}
async function squareWebp(f,n=256){const b=await createImageBitmap(f),m=Math.min(b.width,b.height),c=document.createElement('canvas');c.width=c.height=n;c.getContext('2d').drawImage(b,(b.width-m)/2,(b.height-m)/2,m,m,0,0,n,n);return new Promise(r=>c.toBlob(r,'image/webp',.85))}
async function prep(f){if(!/^image\/(png|jpe?g|webp)$/.test(f.type))throw Error('Format accepté : PNG, JPEG ou WebP');if(f.size>15e6)throw Error('Image trop lourde (15 Mo maximum)');
  const b=await createImageBitmap(f),k=Math.min(1,1800/Math.max(b.width,b.height)),c=document.createElement('canvas');c.width=Math.round(b.width*k);c.height=Math.round(b.height*k);
  const g=c.getContext('2d');g.fillStyle='#fff';g.fillRect(0,0,c.width,c.height);g.drawImage(b,0,0,c.width,c.height);
  const bl=await new Promise(r=>c.toBlob(r,'image/webp',.88));if(!bl)throw Error('Conversion impossible');return bl}
async function upImg(f){const bl=await prep(f),p=crypto.randomUUID()+(bl.type==='image/webp'?'.webp':'.png');
  const {error}=await sb.storage.from('diagrams').upload(p,bl,{contentType:bl.type});if(error)throw error;return p}
const rmImg=async L=>{L=L.filter(Boolean);if(L.length)try{await sb.storage.from('diagrams').remove(L)}catch(e){console.warn(e)}};
const pick=cb=>{const f=document.createElement('input');f.type='file';f.accept=FA;f.onchange=()=>f.files[0]&&cb(f.files[0]);f.click()};
function zoom(src){const L=$('#zoom'),im=$('img',L),P=new Map();let s=1,x=0,y=0,d0=0,s0=1,lt=0;L.hidden=false;im.src=src;
  const ap=()=>{if(s<=1){s=1;x=y=0}im.style.transform=`translate(${x}px,${y}px) scale(${s})`},dd=()=>{const[a,b]=[...P.values()];return Math.hypot(a.clientX-b.clientX,a.clientY-b.clientY)};ap();
  L.onpointerdown=e=>{if(e.target.closest('button'))return;L.setPointerCapture(e.pointerId);P.set(e.pointerId,e);if(P.size===2){d0=dd();s0=s}
    else{const n=Date.now();if(n-lt<300){s=s>1?1:2.5;ap()}lt=n}};
  L.onpointermove=e=>{const p=P.get(e.pointerId);if(!p)return;if(P.size===2){P.set(e.pointerId,e);s=Math.min(6,Math.max(1,s0*dd()/d0))}else if(s>1){x+=e.clientX-p.clientX;y+=e.clientY-p.clientY;P.set(e.pointerId,e)}ap()};
  L.onpointerup=L.onpointercancel=e=>P.delete(e.pointerId);
  L.onwheel=e=>{e.preventDefault();s=Math.min(6,Math.max(1,s*(e.deltaY<0?1.15:.87)));ap()};
  $('button',L).onclick=()=>{L.hidden=true;im.removeAttribute('src')}}
document.addEventListener('click',e=>{const i=e.target.closest('img[data-p]');if(i&&i.src)zoom(i.src)});
addEventListener('keydown',e=>{if(e.key==='Escape')$('#zoom').hidden=true});

/* Navigation : pages empilées (le bouton retour du téléphone fonctionne) */
const BD={top1:'🥇 Or',top2:'🥈 Argent',top3:'🥉 Bronze',progression:'📈 Progression',assiduite:'🔥 Assiduité',precision:'🎯 Précision',revelation:'🌟 Révélation'},fd=d=>new Date(d+'T12:00:00').toLocaleDateString('fr');
/* Ligues (2 modèles), badges permanents, chapeaux */
const LGP=[['🟤','Bronze'],['⚪','Argent'],['🟡','Or'],['🔷','Platine'],['💎','Diamant']],LGR=[['🌱','Novice'],['⚔️','Confirmé'],['🔥','Expert'],['👑','Élite']],
  rl=n=>n<=1000?1:n<=5000?2:n<=10500?3:4,lgTag=(mode,l)=>{const t=(mode==='rang'?LGR:LGP)[l-1];return t?t[0]+' '+t[1]:''};
let BDC=null;const bdefs=async()=>BDC??=Object.fromEntries(((await sb.from('badge_defs').select('*').order('sort')).data||[]).map(b=>[b.code,b]));
const gotBadges=async L=>{if(!L?.length)return;const D=await bdefs();L.forEach((c,i)=>setTimeout(()=>{sfx.ok();toast('🎖️ Nouveau badge : '+(D[c]?.icon||'')+' '+(D[c]?.name||c),'ok')},1700+i*1600))};
const stack=[];
function push(v,a){if(stack.length)history.pushState(null,'');const s=document.createElement('section');s.className='pg';$('#stage').append(s);stack.at(-1)?.el.classList.add('under');const e={el:s,v,a};stack.push(e);draw(e);ui()}
let skip=0;function pop(){if(stack.length<2)return;doPop();skip++;history.back()}
const LIVE=new Set(['hub','cats','paliers','profile','hist','rank','badges','ahat','asante','abulk']);
function doPop(){const e=stack.pop(),t=stack.at(-1);e.el.classList.add('out');setTimeout(()=>e.el.remove(),280);t.el.classList.remove('under');ui();if(LIVE.has(t.v)&&e.v!=='cards')draw(t)}
function reset(v,a){$('#stage').innerHTML='';stack.length=0;push(v,a)}
async function draw(e){e.el.innerHTML='<p class=empty>Chargement…</p>';try{await views[e.v].r(e.el,e.a)}catch(x){e.el.innerHTML=`<p class=err>${esc(x.message)}</p>`}}
function ui(){const t=stack.at(-1);$('#back').hidden=stack.length<2;$('#ttl').textContent=views[t.v].t;document.body.classList.toggle('adm',ADMIN_UI);$('#botmsg').hidden=true}
async function refresh(){const {data}=await sb.from('profiles').select('*').eq('id',ME.id).single();ME=data;$('#nxb').textContent=ME.role==='admin'?'':ME.nx+' NX'}
document.addEventListener('click',e=>{const g=e.target.closest('[data-go]');if(g){sfx.tap();push(g.dataset.go,g.dataset.a?JSON.parse(g.dataset.a):undefined)}});
$('#back').onclick=()=>{sfx.tap();pop()};
addEventListener('popstate',()=>{if(skip){skip--;return}const z=$('#zoom');if(!z.hidden){z.hidden=true;history.pushState(null,'');return}if(stack.length>1)doPop()});
$('#bot').onclick=()=>{const m=$('#botmsg');m.textContent=views[stack.at(-1).v].tip||'';m.hidden=!m.hidden};

/* Session */
async function boot(){
  const {data:{user}}=await sb.auth.getUser();if(!user)return false;
  const {data:p}=await sb.from('profiles').select('*').eq('id',user.id).single();if(!p)return false;
  if(p.role==='admin'&&!ADMIN_UI)return false;
  if(p.role!=='admin')ADMIN_UI=false;
  ME=p;const [s,c]=await Promise.all([sb.from('sectors').select('*').order('name'),sb.from('plan_cfg').select('*')]);
  SECT=s.data;CFG=Object.fromEntries(c.data.map(x=>[x.plan,x]));
  await refresh();reset(p.role==='admin'?'ahub':'hub');return true}

const IM=/\s*@([^\s|@]+\.(?:png|jpe?g|webp))\s*$/i,tk=t=>{const m=t.match(IM);return [t.replace(IM,'').trim(),m?m[1]:null]};
function parse(k,l){
  const [q,...r]=l.split('|'),rest=r.join('|').trim();if(!q.trim()||!rest)throw Error('format « question | … »');
  const [q0,qi]=tk(q),[r0,ri]=tk(rest);if(!q0)throw Error('question vide');
  if(k==='carte')return {question:q0,back:r0,_i:qi,_b:ri};
  const m=r0.match(/^(.*)\((\d)\)\s*(?:\[(.*)\])?$/);if(!m)throw Error('index « (2) » manquant');
  const o=m[1].split(';').map(s=>s.trim()).filter(Boolean),ans=+m[2],p=(m[3]||'').split(';').map(Number);
  if(o.length<2||o.length>6||ans<1||ans>o.length)throw Error('options ou index invalides');
  return k==='donjon'?{question:q0,options:o,answer:ans,secs:p[0]||20,nx:p[1]||10,bonus:p[2]||5,_i:ri||qi}
    :{question:q0,options:o,answer:ans,factor:p[0]||2,secs:p[1]||30,_i:ri||qi}}

async function adminWatch(el){try{const {data:u}=await sb.rpc('usage_report');if(!u)return;const p=Math.max(u.db_pct,u.storage_pct);
  if(!u.last_maint||Date.now()-new Date(u.last_maint)>6048e5)sb.rpc('maintenance');
  if(p>=70&&el.isConnected)el.insertAdjacentHTML('afterbegin',`<button class="alert ${p>=90?'crit':''}" data-go=asante>${p>=90?'🚨':'⚠️'} Stockage à ${p} % : ouvre « Santé &amp; archives »</button>`)}catch(e){console.warn(e)}}
/* Archivage : l'historique ancien est écrit dans un fichier compressé (stockage séparé), vérifié, puis résumé et retiré de la base */
const mrange=m=>{const [y,o]=m.split('-').map(Number),f=(a,b)=>`${a}-${String(b).padStart(2,'0')}-01T00:00:00+02:00`;return [f(y,o),o===12?f(y+1,1):f(y,o+1)]};
const csvc=v=>{v=v==null?'':typeof v==='object'?JSON.stringify(v):String(v);return /[",\n;]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v};
const toCsv=(cols,rows)=>cols.join(',')+'\n'+rows.map(r=>cols.map(c=>csvc(r[c])).join(',')).join('\n');
async function gz(t){if(!('CompressionStream' in window))return {blob:new Blob([t],{type:'text/csv'}),ext:'csv',type:'text/csv'};return {blob:await new Response(new Blob([t]).stream().pipeThrough(new CompressionStream('gzip'))).blob(),ext:'csv.gz',type:'application/gzip'}}
async function archiveMonth(m,say){const [a,b]=mrange(m);let after=0;const rows=[];
  for(;;){const {data,error}=await sb.from('history').select('id,user_id,item_id,kind,ok,delta,at').gte('at',a).lt('at',b).gt('id',after).order('id').limit(5000);if(error)throw error;if(!data.length)break;rows.push(...data);after=data.at(-1).id;say(m+' : '+rows.length+' lignes lues…')}
  if(!rows.length)throw Error('Aucune ligne pour '+m);
  const f=await gz(toCsv(['id','user_id','item_id','kind','ok','delta','at'],rows)),path='history_'+m+'.'+f.ext;say(m+' : envoi du fichier…');
  const {error:e}=await sb.storage.from('archives').upload(path,f.blob,{upsert:true,contentType:f.type});if(e)throw e;
  const {error:e2}=await sb.rpc('archive_commit',{p_month:m+'-01',p_rows:rows.length,p_path:path});if(e2)throw e2;return rows.length}
async function dumpTables(T){const out={};for(const t of T){const R=[];for(let i=0;;i+=1000){const {data,error}=await sb.from(t).select('*').range(i,i+999);if(error)throw error;R.push(...data);if(data.length<1000)break}out[t]=R}return out}
const save=(blob,name)=>{const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=name;document.body.append(a);a.click();setTimeout(()=>{a.remove();URL.revokeObjectURL(a.href)},2000)};
/* Import massif : un fichier = plusieurs catégories, jusqu'à 30+ paliers, donjons + Nexify + cartes.
   # Catégorie  /  ## PALIER n  /  ### DONJON [secondes;NX;bonus]  /  lignes de questions */
const MTPL=`// MODÈLE NEXI LAB : tout ce qui commence par // est ignoré.
// @CATEGORY = catégorie (tu peux en mettre plusieurs dans le même fichier)
// @PALIER n | Titre = palier (jusqu'à 30 et plus), @DONJON / @NEXIFY / @CARTE = type de questions.
// Entre crochets après @DONJON ou @NEXIFY : valeurs par défaut du bloc. Une ligne peut avoir ses propres crochets.
// @fichier.png en fin de @PALIER, de @DONJON... ou de ligne = schéma (à choisir dans « Schémas du lot »).
// Alias accepté : # catégorie, ## PALIER n - Titre, ### DONJON [20;10;5].

@CATEGORY Hydrometallurgy

@PALIER 1 | Introduction & vocabulary
@DONJON [20;10;5]
Que signifie PLS ? | Pregnant Leach Solution;Plant Loading System;Primary Leach Stage (1)
Quel acide est le plus utilisé pour lixivier les oxydes de cuivre ? | Sulfurique;Chlorhydrique;Nitrique;Fluorhydrique (1) [30;10;5]
@NEXIFY [2;30]
Quel est le produit final d'un circuit SX-EW du cuivre ? | Cathodes de cuivre;Matte;Anodes;Boues (1)
@CARTE
Qu'est-ce que le leaching ? | Mise en solution d'un métal contenu dans un minerai à l'aide d'un réactif (lixiviation).

@PALIER 2 | Leaching fundamentals
@DONJON [30;10;5]
Quelle grandeur contrôle surtout la dissolution en lixiviation acide ? | Le pH;La couleur;Le poids du sac (1)
`;
function parseMass(txt,exp){const out={cats:[],errors:[],warn:[],imgs:new Set()};let cat=null,pal=null,pimg=null,blk=null;
  const err=(n,m)=>out.errors.push('Ligne '+n+' : '+m);
  txt.split(/\r?\n/).forEach((raw,i)=>{const n=i+1,l=raw.trim();if(!l||l.startsWith('//'))return;
    const at=l.match(/^@(CAT[EÉ]GORY|CAT[EÉ]GORIE|PALIER|DONJON|NEXIFY|CARTE)S?\b\s*(.*)$/i);
    if(at){const d=at[1].toUpperCase(),v=at[2].trim();
      if(d.startsWith('CAT')){if(!v)return err(n,'nom de catégorie vide');cat=out.cats.find(c=>c.name.toLowerCase()===v.toLowerCase());if(!cat){cat={name:v,rows:[],pal:new Map(),titles:new Map()};out.cats.push(cat)}pal=null;blk=null;return}
      if(d==='PALIER'){if(!cat)return err(n,'« @PALIER » avant toute « @CATEGORY »');const m=v.match(/^(\d+)\s*(?:\|\s*(.*))?$/);if(!m)return err(n,'écris « @PALIER 3 | Titre »');
        let t=(m[2]||'').trim();const im=t.match(IM);if(im){t=t.replace(IM,'').trim();pimg=im[1];out.imgs.add(pimg.toLowerCase())}else pimg=null;pal=+m[1];blk=null;if(t)cat.titles.set(pal,t);return}
      const mm=v.match(/^(?:\[([^\]]*)\])?\s*(?:@(\S+))?$/);if(!mm)return err(n,'après @'+d+', seulement [secondes;NX;bonus] et @schéma.png sont possibles');
      if(!cat||pal==null)return err(n,'« @'+d+' » avant la catégorie ou le palier');blk={k:d.toLowerCase(),def:mm[1]??null,img:mm[2]||null};if(blk.img)out.imgs.add(blk.img.toLowerCase());return}
    const h=l.match(/^(#{1,3})\s+(.*)$/);
    if(h){const d=h[1].length,body=h[2].trim();
      if(d===1){const nm=body.replace(/^cat[eé]gorie\s*:\s*/i,'').trim();if(!nm)return err(n,'nom de catégorie vide');cat=out.cats.find(c=>c.name.toLowerCase()===nm.toLowerCase());if(!cat){cat={name:nm,rows:[],pal:new Map(),titles:new Map()};out.cats.push(cat)}pal=null;blk=null;return}
      if(d===2){if(!cat)return err(n,'« ## PALIER » avant toute catégorie « # »');const m=body.match(/^(?:palier\s*)?(\d+)\b\s*(?:[-–—:]\s*)?(.*)$/i);if(!m)return err(n,'palier illisible. Exemple : ## PALIER 7');
        let t=m[2].trim();const im=t.match(IM);if(im)t=t.replace(IM,'').trim();pal=+m[1];pimg=im?im[1]:null;blk=null;if(pimg)out.imgs.add(pimg.toLowerCase());if(t)cat.titles.set(pal,t);return}
      const m=body.match(/^(donjon|nexify|carte)s?\b\s*(?:\[([^\]]*)\])?\s*(?:@(\S+))?\s*$/i);if(!m)return err(n,'type inconnu. Utilise ### DONJON, ### NEXIFY ou ### CARTE');
      if(!cat||pal==null)return err(n,'« ### » avant la catégorie ou le palier');blk={k:m[1].toLowerCase(),def:m[2]??null,img:m[3]||null};if(blk.img)out.imgs.add(blk.img.toLowerCase());return}
    if(!blk)return err(n,'ligne de question hors d’un bloc ### (catégorie, palier et type obligatoires avant)');
    try{let ln=l,im=null;const m=ln.match(IM);if(m){im=m[1];ln=ln.replace(IM,'')}
      if(blk.k!=='carte'&&blk.def&&!/\[[^\]]*\]\s*$/.test(ln))ln+=' ['+blk.def+']';
      const r=parse(blk.k,ln);r._i=r._i||im||blk.img||pimg||null;
      [r._i,r._b].forEach(x=>x&&out.imgs.add(x.toLowerCase()));
      cat.rows.push({...r,kind:blk.k,palier:pal});const key=pal+'|'+blk.k;cat.pal.set(key,(cat.pal.get(key)||0)+1)}catch(x){err(n,x.message)}});
  out.cats.forEach(c=>{const seen=new Set();c.rows.forEach(r=>{const k=r.palier+'|'+r.kind+'|'+r.question;if(seen.has(k))out.warn.push(c.name+' · palier '+r.palier+' : question en double ignorée « '+r.question.slice(0,40)+'… »');seen.add(k)});
    if(exp)[...new Set(c.rows.map(r=>r.palier))].sort((a,b)=>a-b).forEach(p=>['donjon','nexify','carte'].forEach(k=>{const v=c.pal.get(p+'|'+k)||0;if(v!==exp)out.warn.push(c.name+' · palier '+p+' · '+k+' : '+v+' ligne(s) au lieu de '+exp)}))});
  return out}
const tiles=T=>`<div class=grid>${T.map(t=>`<button class=tile data-go=${t[0]} ${t[3]?`data-a="${A(t[3])}"`:''}><i>${t[1]}</i>${t[2]}</button>`).join('')}</div>`;

const views={
home:{t:'NEXI LAB',tip:'Bienvenue dans NEXI LAB, le laboratoire des sciences exactes de Nexi Academy.',r(el){el.classList.add('home');
  el.innerHTML=`<img class=logo src=icons/icon-512.png alt=""><h2>NEXI LAB</h2><p class=sub>Le laboratoire des futurs ingénieurs</p><button class=btn data-go=about>À propos</button><button class="btn hot" data-go=login>Se connecter</button>`}},
about:{t:'À propos',tip:'Ici on raconte qui est NEXI LAB.',r(el){
  /* ✏️ MODIFIE CE TEXTE : c'est ici que tu racontes NEXI LAB dans Nexi Academy */
  el.innerHTML=`<h2>Qui est NEXI LAB ?</h2><p>NEXI LAB est le module des sciences exactes et de la technologie de Nexi Academy. Chaque Nexian évolue dans son secteur de génie, affronte des donjons, mise ses NX dans Nexify et révise avec des cartes, au plus près des situations réelles de terrain : normes ISO, audit interne, safety first, optimisation de procédés, esprit d'équipe.</p>`}},
login:{t:'Connexion',tip:'Entre ton identifiant et ton code, donnés par ton administrateur.',r(el){el.classList.add('center');
  el.innerHTML=`<img id=lg class=logo src=icons/icon-512.png alt="NEXI LAB"><form id=lf class=form><input id=u placeholder="Identifiant" autocomplete=username required><input id=p type=password placeholder="Code" autocomplete=current-password required><button class="btn hot">Entrer</button></form><p id=le class=err></p>`;
  let n=0,tm;$('#lg',el).onclick=()=>{clearTimeout(tm);if(++n>=5){n=0;ADMIN_UI=!ADMIN_UI;ui();navigator.vibrate&&navigator.vibrate(60);toast(ADMIN_UI?'Panel admin':'Panel Nexian')}tm=setTimeout(()=>n=0,1500)};
  $('#lf',el).onsubmit=async e=>{e.preventDefault();const le=$('#le',el);le.textContent='';
    const {error}=await sb.auth.signInWithPassword({email:mail($('#u',el).value),password:$('#p',el).value});
    if(error||!await boot()){if(!error)await sb.auth.signOut();le.textContent='Identifiant ou code incorrect.';sfx.ko()}}}},

hub:{t:'NEXI LAB',tip:'Ton QG : choisis une rubrique.',async r(el){await refresh();
  el.innerHTML=`<div class=hud><b>${esc(ME.pseudo)}</b><span>${ME.nx} NX · Rang ${rank(ME.nx)} · Semaine : ${ME.wnx||0}</span></div>${tiles([['profile','👤','Mon profil'],['cats','⚔️','Donjons',{k:'donjon'}],['cats','🎲','Nexify',{k:'nexify'}],['cats','🃏','Cartes de révision',{k:'carte'}],['rank','🏆','Classement'],['hall','🏅','Mur d’honneur'],['badges','🎖️','Badges'],['hist','📜','Historique']])}<button class="btn ghost" id=out>Déconnexion</button>`;
  $('#out',el).onclick=async()=>{await sb.auth.signOut();ME=null;ADMIN_UI=false;$('#nxb').textContent='';reset('home')}}},
cats:{t:'Catégories',tip:'Choisis une catégorie de ton secteur.',async r(el,a){
  if(a.k==='nexify'&&!CFG[ME.plan].nexify){el.innerHTML='<p class=empty>🔒 Nexify est réservé aux formules Premium.</p>';return}
  const [c,i]=await Promise.all([sb.from('categories').select('*').eq('sector_id',ME.sector_id).order('name'),sb.from('items_public').select('category_id').eq('kind',a.k)]);
  const has=new Set(i.data.map(x=>x.category_id)),L=c.data.filter(x=>has.has(x.id));
  el.innerHTML=`<div class=stack>${L.map(x=>`<button class=row data-go=paliers data-a="${A({k:a.k,c:x.id,n:x.name})}">${esc(x.name)}<span>›</span></button>`).join('')||'<p class=empty>Rien de publié pour l’instant.</p>'}</div>`}},
paliers:{t:'Paliers',tip:'Chaque palier est une étape. Un ticket est utilisé quand tu commences.',async r(el,a){
  const [it,at,pt]=await Promise.all([sb.from('items_public').select('id,palier,weekly').eq('kind',a.k).eq('category_id',a.c),sb.from('attempts').select('item_id,n').eq('user_id',ME.id),sb.from('palier_titles').select('palier,title').eq('category_id',a.c)]);
  const PT=Object.fromEntries((pt.data||[]).map(x=>[x.palier,x.title]));
  const m=Object.fromEntries(at.data.map(x=>[x.item_id,x.n])),mx=CFG[ME.plan].replays,P={};
  it.data.forEach(x=>(P[x.palier]??=[]).push(x));
  el.innerHTML=`<h3>${esc(a.n)}</h3><div class=grid>${Object.keys(P).sort((x,y)=>x-y).map(p=>{const dn=a.k!=='carte'&&P[p].every(x=>(m[x.id]||0)>=mx);
    return `<button class="tile ${dn?'done':''}" ${dn?'disabled':`data-go=${a.k==='carte'?'cards':'play'} data-a="${A({...a,p:+p})}"`}><i>${dn?'✅':p}</i>${dn?'Fait':'Palier '+p}${PT[p]?`<small class=pt>${esc(PT[p])}</small>`:''}${!dn&&P[p].some(x=>x.weekly)?'<small class=wk>⭐ Défi de la semaine</small>':''}</button>`}).join('')}</div>`}},
cards:{t:'Révision',tip:'Touche la carte pour voir la réponse détaillée. Touche un schéma pour l’agrandir.',async r(el,a){
  const {data}=await sb.from('items_public').select('*').eq('kind','carte').eq('category_id',a.c).eq('palier',a.p).order('ord');
  if(!data.length){el.innerHTML='<p class=empty>Aucune carte.</p>';return}
  let i=0;const show=()=>{const c=data[i];
    el.innerHTML=`<p class=cnt>${i+1} / ${data.length}</p><div class=flip id=fl><div class=face><div class=fc>${figure(c.image)}<p>${esc(c.question)}</p></div></div><div class="face bk"><div class=fc>${figure(c.back_image)}<p>${esc(c.back).replace(/\n/g,'<br>')}</p></div></div></div><div class=nav><button class="btn ghost" id=pv ${i?'':'disabled'}>Précédente</button><button class="btn hot" id=nx>${i<data.length-1?'Suivante':'Terminer'}</button></div>`;
    hydrate(el);
    $('#fl',el).onclick=e=>{if(e.target.closest('img'))return;$('#fl',el).classList.toggle('on');sfx.tap()};$('#pv',el).onclick=()=>{i--;show()};$('#nx',el).onclick=()=>{if(i<data.length-1){i++;show()}else pop()}};
  show()}},
play:{t:'Donjon',tip:'Réponds vite : le bonus rapidité rapporte des NX en plus.',async r(el,a){
  const [d,at]=await Promise.all([sb.from('items_public').select('*').eq('kind',a.k).eq('category_id',a.c).eq('palier',a.p).order('ord'),sb.from('attempts').select('item_id,n').eq('user_id',ME.id)]);
  const m=Object.fromEntries(at.data.map(x=>[x.item_id,x.n])),Q=d.data.filter(x=>(m[x.id]||0)<CFG[ME.plan].replays);let i=0,gain=0;
  const AC=a.k==='nexify'?((await sb.from('app_cfg').select('*').single()).data||{stake_pct:25,stake_max:500}):null,SM=()=>Math.max(1,Math.min(Math.floor(ME.nx*AC.stake_pct/100),AC.stake_max,ME.nx));
  if(!Q.length){el.innerHTML='<p class=empty>Déjà fait.</p>';return}
  const next=()=>{if(i>=Q.length){el.innerHTML=`<div class=center><h2>Terminé</h2><p class=big>${gain>=0?'+':''}${gain} NX</p><button class="btn hot" id=bk>Continuer</button></div>`;$('#bk',el).onclick=()=>{refresh();pop()};return}
    a.k==='nexify'?stake(Q[i]):ask(Q[i],0)};
  const stake=q=>{el.innerHTML=`<div class=card3><h3>Carte Nexify ${i+1}/${Q.length}</h3><p>Réussis et ta mise est multipliée par ×${q.factor}. Rate et tu la perds.</p><p>Solde : <b>${ME.nx} NX</b> · Mise maximum : <b>${SM()} NX</b></p><input id=sk type=number min=1 max=${SM()} placeholder="Ta mise en NX"><button class="btn hot" id=rv>Révéler la carte</button></div>`;
    $('#rv',el).onclick=()=>{const s=Math.floor(+$('#sk',el).value);if(!(s>=1&&s<=SM()&&s<=ME.nx)){sfx.ko();return toast('Mise invalide (maximum '+SM()+' NX)','ko')}ask(q,s)}};
  const ask=(q,s)=>{let t0=Date.now(),done=0,iv;
    el.innerHTML=`<div class=bar><i id=tb></i></div>${figure(q.image)}<h3 class=q>${esc(q.question)}</h3><div class=stack>${q.options.map((o,k)=>`<button class="row opt" data-k=${k+1} disabled>${esc(o)}</button>`).join('')}</div>`;
    const tick=()=>{if(!el.isConnected||el.classList.contains('out')){clearInterval(iv);return}const r=Math.max(0,q.secs*1000-(Date.now()-t0));$('#tb',el).style.width=r/q.secs/10+'%';if(!r)send(0)};
    const send=async k=>{if(done)return;done=1;clearInterval(iv);
      const {data:r,error}=await sb.rpc('answer_item',{p_item:q.id,p_choice:k,p_ms:Date.now()-t0,p_stake:s});
      if(error){sfx.ko();toast(error.message,'ko');return pop()}
      $$('.opt',el).forEach(b=>{const n=+b.dataset.k;b.disabled=true;if(n===r.answer)b.classList.add('good');else if(n===k)b.classList.add('bad')});
      if(r.ok)sfx.ok();else{sfx.ko();el.classList.add('shake')}
      gotBadges(r.badges);gain+=r.delta;ME.nx=r.nx;$('#nxb').textContent=r.nx+' NX';toast((r.delta>0?'+':'')+r.delta+' NX',r.ok?'ok':'ko');
      setTimeout(()=>{el.classList.remove('shake');i++;next()},1500)};
    $$('.opt',el).forEach(b=>b.onclick=()=>send(+b.dataset.k));
    hydrate(el).then(()=>{if(!el.isConnected)return;$$('.opt',el).forEach(b=>b.disabled=false);t0=Date.now();iv=setInterval(tick,100)})};
  next()}},
profile:{t:'Mon profil',tip:'Change ta photo et ton pseudo : c’est lui qu’on voit au classement.',async r(el){await refresh();
  const {data:us}=await sb.from('user_stats').select('answers').eq('user_id',ME.id).maybeSingle(),count=us?.answers||0,s=SECT.find(x=>x.id===ME.sector_id);
  const lc=(await sb.from('league_cfg').select('*').eq('sector_id',ME.sector_id).maybeSingle()).data,LGL=lc?.enabled?lgTag(lc.mode,lc.mode==='rang'?rl(ME.nx):ME.league):'';
  el.innerHTML=`<div class=center><label class=av><img src="${esc(ME.avatar_url||'icons/icon-192.png')}" alt=""><input type=file accept=image/* hidden id=ph></label><h2>${esc(ME.full_name)}</h2><p class=sub>${esc(s?.name||'')} · formule ${esc(ME.plan)}${ME.plan_end?' jusqu’au '+ME.plan_end:''}</p><p class=big>${ME.nx} NX</p><p>Rang ${rank(ME.nx)} · ${count} réponses</p>${LGL?`<p>Ligue ${LGL}</p>`:''}</div><label>Pseudo (visible au classement)<input id=ps value="${esc(ME.pseudo)}" maxlength=20></label><button class="btn hot" id=sv>Enregistrer</button>`;
  const save=async av=>{const {error}=await sb.rpc('set_profile',{p_pseudo:$('#ps',el).value,p_avatar:av??ME.avatar_url});toast(error?'Pseudo indisponible':'Enregistré',error?'ko':'ok');refresh()};
  $('#sv',el).onclick=()=>save();
  $('#ph',el).onchange=async e=>{const f=e.target.files[0];if(!f||f.size>10e6)return toast('Image de 10 Mo maximum','ko');const p=ME.id+'/a';let bl;try{bl=await squareWebp(f)}catch{return toast('Image illisible','ko')}
    const {error}=await sb.storage.from('avatars').upload(p,bl,{upsert:true,contentType:'image/webp'});if(error)return toast('Envoi impossible','ko');
    $('img',el).src=URL.createObjectURL(bl);save(sb.storage.from('avatars').getPublicUrl(p).data.publicUrl+'?t='+Date.now())}}},
badges:{t:'Badges',tip:'Débloque des badges en jouant. Les badges verrouillés montrent comment les obtenir.',async r(el){
  const [D,{data:u}]=await Promise.all([bdefs(),sb.from('user_badges').select('code,at').eq('user_id',ME.id)]);
  const G=Object.fromEntries((u||[]).map(x=>[x.code,x.at])),L=Object.values(D);
  el.innerHTML=`<p class=cnt>${Object.keys(G).length} / ${L.length} badges</p><div class=bgrid>${L.map(b=>`<div class="bdg ${G[b.code]?'on':''}"><i>${G[b.code]?b.icon:'🔒'}</i><b>${esc(b.name)}</b><small>${esc(b.descr)}</small>${G[b.code]?`<em>${fd(String(G[b.code]).slice(0,10))}</em>`:''}</div>`).join('')}</div>`}},
rank:{t:'Classement',tip:'Ta place parmi les Nexians de ton secteur. « Cette semaine » repart de zéro à chaque cycle : tout le monde y est à égalité. Seuls les pseudos sont visibles.',async r(el){
  const [{data},{data:st},{data:lc},{data:hats}]=await Promise.all([sb.from('leaderboard').select('*').limit(300),sb.from('weekly_state').select('week_start').single(),
    sb.from('league_cfg').select('*').eq('sector_id',ME.sector_id).maybeSingle(),sb.from('hats').select('*').order('id',{ascending:false})]);
  const LG=!!lc?.enabled,me=(data||[]).find(x=>x.id===ME.id),H=hats||[];let m='w',sc=LG?'l':'s',hi=0;
  const draw2=async()=>{
    const tabs=`<div class=tabs><button data-m=w class="${m==='w'?'on':''}">Cette semaine</button><button data-m=n class="${m==='n'?'on':''}">Général</button>${H.length?`<button data-m=h class="${m==='h'?'on':''}">🎩 Concours</button>`:''}</div>`;
    const bind=()=>{$$('[data-m]',el).forEach(b=>b.onclick=()=>{m=b.dataset.m;sfx.tap();draw2()});$$('[data-s]',el).forEach(b=>b.onclick=()=>{sc=b.dataset.s;sfx.tap();draw2()});const hs=$('#hs',el);if(hs)hs.onchange=()=>{hi=+hs.value;draw2()}};
    if(m==='h'){const h=H[hi],{data:B}=await sb.rpc('hat_board',{p_hat:h.id});
      el.innerHTML=tabs+`${H.length>1?`<label>Concours<select id=hs>${H.map((x,i)=>`<option value=${i} ${i===hi?'selected':''}>${esc(x.name)}</option>`).join('')}</select></label>`:''}<p class=cnt>🎩 ${esc(h.name)} · ${h.closed?'terminé le '+fd(String(h.ends_at).slice(0,10)):'en cours depuis le '+fd(String(h.starts_at).slice(0,10))}${h.note?'<br>'+esc(h.note):''}</p><div class=stack>${(B||[]).map((x,i)=>`<div class="row lb ${x.user_id===ME.id?'me':''} ${x.score>0?MC[i]||'':''}"><b>${x.score>0?MED[i]||i+1:i+1}</b><span>${esc(x.pseudo)}</span><b>${x.score}</b></div>`).join('')||'<p class=empty>Personne pour le moment.</p>'}</div>`;bind();return}
    const L=[...(data||[]).filter(x=>!LG||sc==='s'||x.lg===me?.lg)].sort((a,b)=>m==='w'?b.wnx-a.wnx||b.nx-a.nx:b.nx-a.nx).slice(0,100);
    el.innerHTML=tabs+(LG?`<div class=tabs><button data-s=l class="${sc==='l'?'on':''}">${lgTag(lc.mode,me?.lg)} · ma ligue</button><button data-s=s class="${sc==='s'?'on':''}">Tout le secteur</button></div>`:'')+`<p class=cnt>${m==='w'?'Cycle commencé le '+fd(st?.week_start||new Date().toISOString().slice(0,10)):'Cumul de carrière'}</p><div class=stack>${L.map((x,i)=>{const md=m==='n'||x.wnx>0;return `<div class="row lb ${x.id===ME.id?'me':''} ${md?MC[i]||'':''}"><b>${md?MED[i]||i+1:i+1}</b><span>${esc(x.pseudo)}${LG&&sc==='s'?` <small>${lgTag(lc.mode,x.lg)}</small>`:''}</span><em>${rank(x.nx)}</em><b>${m==='w'?x.wnx:x.nx}</b></div>`}).join('')||'<p class=empty>Personne pour le moment.</p>'}</div>`;bind()};
  draw2()}},
hall:{t:'Mur d’honneur',tip:'Les lauréats de chaque cycle dans ton secteur, et tes propres semaines.',async r(el){
  const [{data:h},{data:mine}]=await Promise.all([sb.rpc('hall'),sb.from('weekly_archive').select('week_start,week_end,wnx,pos,badges,active_days,accuracy,league,move').eq('user_id',ME.id).order('week_start',{ascending:false}).limit(12)]);
  const G={};(h||[]).forEach(x=>(G[x.week_start+'|'+x.week_end]??=[]).push(x));
  el.innerHTML=`<h3>Lauréats</h3><div class=stack>${Object.values(G).map(r=>`<div class=card3><p class=cnt>Du ${fd(r[0].week_start)} au ${fd(r[0].week_end)}</p>${r.map(x=>`<div class=row><span>${esc(x.pseudo)}</span><small>${x.badges.map(b=>BD[b]||b).join(' · ')}</small></div>`).join('')}</div>`).join('')||'<p class=empty>Aucun cycle clôturé pour le moment.</p>'}</div><h3>Mes semaines</h3><div class=stack>${(mine||[]).map(x=>`<div class=row><span>${fd(x.week_start)} → ${fd(x.week_end)}<br><small>${x.active_days} jour(s) actif(s) · ${x.accuracy} % de réussite${x.badges.length?' · '+x.badges.map(b=>BD[b]||b).join(' '):''}${x.move>0?' · ⬆️ promu':x.move<0?' · ⬇️ relégué':''}</small></span><b>${x.wnx} NX</b></div>`).join('')||'<p class=empty>Pas encore de semaine archivée.</p>'}</div>`}},
hist:{t:'Historique',tip:'Tes performances et ton activité.',async r(el){
  const [{data:h},{data:st}]=await Promise.all([sb.from('history').select('*').eq('user_id',ME.id).order('at',{ascending:false}).limit(60),sb.from('user_stats').select('*').eq('user_id',ME.id).maybeSingle()]);
  el.innerHTML=`<div class=grid2><div class=stat><b>${st?.donjon_ok??h.filter(x=>x.kind==='donjon'&&x.ok).length}</b>réussites donjon</div><div class=stat><b>${st?.best_gain??Math.max(0,...h.map(x=>x.delta))}</b>meilleur gain</div><div class=stat><b>${Math.max(1,Math.ceil((Date.now()-new Date(st?.first_at||ME.created_at))/864e5))}</b>jours d’activité</div></div><div class=stack>${h.map(x=>`<div class=row><span>${x.kind==='donjon'?'⚔️ Donjon':'🎲 Nexify'} · ${new Date(x.at).toLocaleString('fr')}</span><b style="color:${x.delta>0?'#2dff8a':x.delta<0?'#ff2d45':'inherit'}">${x.delta>0?'+':''}${x.delta}</b></div>`).join('')||'<p class=empty>Aucune partie pour le moment.</p>'}</div>`}},

/* ---------- ADMIN ---------- */
ahub:{t:'NEXI LAB · ADMIN',tip:'Gestion complète de NEXI LAB.',r(el){
  el.innerHTML=`${tiles([['anex','👥','Nexians'],['acont','⚔️','Donjons',{k:'donjon'}],['acont','🎲','Nexify',{k:'nexify'}],['acont','🃏','Cartes',{k:'carte'}],['arank','🏆','Classement'],['abulk','📦','Import massif'],['ahat','🎩','Chapeaux'],['asante','💾','Santé & archives'],['aset','⚙️','Réglages']])}<button class="btn ghost" id=out>Déconnexion</button>`;
  $('#out',el).onclick=async()=>{await sb.auth.signOut();ME=null;ADMIN_UI=false;reset('home')};adminWatch(el)}},
anex:{t:'Nexians',tip:'Crée et modifie les comptes des Nexians.',async r(el){
  const {data}=await sb.from('profiles').select('*').eq('role','nexian').order('full_name');
  el.innerHTML=`<button class="btn hot" data-go=aedit>+ Créer un Nexian</button><div class=stack>${data.map(p=>`<button class=row data-go=aedit data-a="${A(p)}">${esc(p.full_name)}<span>${esc(p.plan)} · ${p.nx} NX</span></button>`).join('')}</div>`}},
aedit:{t:'Nexian',tip:'L’identifiant est fixe. Saisis un mot de passe seulement pour le changer.',r(el,p){const n=!p;
  p??={plan:'freemium',nx:100,league:1,sex:'M',plan_start:new Date().toISOString().slice(0,10)};
  const inp=(k,l,t='text')=>`<label>${l}<input data-f=${k} type=${t} value="${esc(p[k]??'')}" ${k==='login'&&!n?'disabled':''}></label>`;
  el.innerHTML=`${n?'':'<p class=cnt id=bg></p>'}<div class=form>${inp('full_name','Nom complet')}${inp('pseudo','Pseudo par défaut')}${inp('login','Identifiant')}<label>Mot de passe<input id=pw placeholder="${n?'6 caractères minimum':'vide = inchangé'}"></label><label>Secteur<select data-f=sector_id>${sectOpts()}</select></label><label>Sexe<select data-f=sex><option>M<option>F</select></label><label>Formule<select data-f=plan>${Object.keys(CFG).map(k=>`<option>${k}`).join('')}</select></label>${inp('plan_start','Début abonnement','date')}${inp('plan_end','Fin abonnement','date')}${inp('tickets_custom','Tickets par jour (vide = valeur de la formule)','number')}<label>Ligue (modèle promotion/relégation)<select data-f=league>${LGP.map((t,i)=>`<option value=${i+1}>${t[0]} ${t[1]}`).join('')}</select></label>${inp('nx','NX','number')}<button class="btn hot" id=sv>Enregistrer</button></div>`;
  if(!n)Promise.all([bdefs(),sb.from('user_badges').select('code').eq('user_id',p.id)]).then(([D,{data}])=>{const b=$('#bg',el);if(b)b.textContent=(data||[]).length?'Badges : '+data.map(x=>(D[x.code]?.icon||'')+' '+(D[x.code]?.name||x.code)).join(' · '):'Aucun badge pour le moment.'});
  ['sector_id','sex','plan','league'].forEach(k=>{if(p[k]!=null)$(`[data-f=${k}]`,el).value=p[k]});
  $('#sv',el).onclick=async()=>{const o={};$$('[data-f]',el).forEach(i=>{if(!i.disabled)o[i.dataset.f]=i.value===''?null:i.value});
    ['sector_id','nx','tickets_custom','league'].forEach(k=>o[k]!=null&&(o[k]=+o[k]));const pw=$('#pw',el).value;
    try{if(n){const c=supabase.createClient(NEXI.URL,NEXI.KEY,{auth:{persistSession:false,autoRefreshToken:false}});
        const {data,error}=await c.auth.signUp({email:mail(o.login),password:pw});if(error)throw error;
        const {error:e2}=await sb.from('profiles').insert({...o,id:data.user.id,role:'nexian'});if(e2)throw e2}
      else{const {error}=await sb.from('profiles').update(o).eq('id',p.id);if(error)throw error;
        if(pw){const {error:e3}=await sb.rpc('admin_set_password',{p_id:p.id,p_pw:pw});if(e3)throw e3}}
      toast('Enregistré','ok');pop();stack.at(-1).v==='anex'&&draw(stack.at(-1))}catch(x){toast(x.message,'ko')}}}},
acont:{t:'Contenu',tip:'Choisis secteur, catégorie et palier, puis colle une ligne par question. Tu peux joindre un schéma.',r(el,a){
  const car=a.k==='carte';
  el.innerHTML=`<div class=form><label>Secteur<select id=se>${sectOpts()}</select></label><label>Catégorie<select id=ca></select></label><label>Ou nouvelle catégorie<input id=nc></label><label>Palier<input id=pa type=number min=0 value=1></label>${car?'':'<label class=chk ${car?"hidden":""}><input type=checkbox id=wk checked>⭐ Défi de la semaine (compte pour le classement hebdomadaire)</label>'}<label>Une ligne par ${car?'carte':'question'}<textarea id=tx rows=6 placeholder="${esc(HELP[a.k])}"></textarea></label><label>Schéma commun à toutes les lignes (optionnel)<input type=file id=fi accept="${FA}"></label><label>Schémas du lot${esc(HELPIMG)}<input type=file id=fm multiple accept="${FA}"></label><button class="btn hot" id=im>Importer</button></div><div id=li class=stack></div>`;
  const list=async()=>{const c=$('#ca',el).value;if(!c){$('#li',el).innerHTML='';return}
    const {data}=await sb.from('items').select('*').eq('kind',a.k).eq('category_id',c).eq('palier',$('#pa',el).value||0).order('ord');
    $('#li',el).innerHTML=`<p class=cnt>${data.filter(x=>x.published).length} visible(s) · ${data.filter(x=>!x.published).length} masqué(s) — visibles pour les Nexians du secteur « ${esc($('#se',el).selectedOptions[0]?.text||'')} » uniquement</p>`+data.map(x=>`<div class=row><span>${x.image?'🖼 ':''}${x.back_image?'🖼′ ':''}${esc(x.question)}</span><div class=acts>${car?`<button data-i=${x.id} data-s=image>🖼 recto</button><button data-i=${x.id} data-s=back_image>🖼 verso</button>`:`<button data-i=${x.id} data-s=image title="Schéma">🖼</button>`}${x.image||x.back_image?`<button data-c=${x.id} title="Retirer les schémas">🧹</button>`:''}${car?'':`<button data-r=${x.id} title="Réactiver pour tous les joueurs">♻</button>`}${car?'':`<button data-w=${x.id} class=${x.weekly?'vis':''} title="Défi de la semaine : compte pour le classement hebdomadaire">${x.weekly?'⭐ Défi':'☆ Défi'}</button>`}<button data-t=${x.id} class=${x.published?'vis':'hid'} title="Toucher pour ${x.published?'masquer':'rendre visible'}">${x.published?'👁 Visible':'🚫 Masqué'}</button><button data-d=${x.id}>🗑</button></div></div>`).join('');
    const F=id=>data.find(i=>i.id==id),run=async f=>{try{await f()}catch(x){toast(x.message,'ko')}list()};
    $$('[data-i]',el).forEach(b=>b.onclick=()=>pick(f=>run(async()=>{const x=F(b.dataset.i),s=b.dataset.s,p=await upImg(f);const {error}=await sb.from('items').update({[s]:p}).eq('id',x.id);if(error){await rmImg([p]);throw error}await rmImg([x[s]]);toast('Schéma enregistré','ok')})));
    $$('[data-c]',el).forEach(b=>b.onclick=()=>confirm('Retirer les schémas de cette ligne ?')&&run(async()=>{const x=F(b.dataset.c);const {error}=await sb.from('items').update({image:null,back_image:null}).eq('id',x.id);if(error)throw error;await rmImg([x.image,x.back_image])}));
    $$('[data-r]',el).forEach(b=>b.onclick=()=>confirm('Réactiver cette question pour tous les joueurs (efface leurs tentatives) ?')&&run(async()=>{const {error}=await sb.from('attempts').delete().eq('item_id',b.dataset.r);if(error)throw error;toast('Réactivée','ok')}));
    $$('[data-t]',el).forEach(b=>b.onclick=()=>run(async()=>{const x=F(b.dataset.t);const {error}=await sb.from('items').update({published:!x.published}).eq('id',x.id);if(error)throw error}));
    $$('[data-w]',el).forEach(b=>b.onclick=()=>run(async()=>{const x=F(b.dataset.w);const {error}=await sb.from('items').update({weekly:!x.weekly}).eq('id',x.id);if(error)throw error}));
    $$('[data-d]',el).forEach(b=>b.onclick=()=>confirm('Supprimer cette ligne ?')&&run(async()=>{const x=F(b.dataset.d);const {error}=await sb.from('items').delete().eq('id',x.id);if(error)throw error;await rmImg([x.image,x.back_image])}))};
  const cat=async sel=>{const {data}=await sb.from('categories').select('*').eq('sector_id',$('#se',el).value).order('name');
    $('#ca',el).innerHTML=data.map(c=>`<option value=${c.id}>${esc(c.name)}`).join('');if(sel)$('#ca',el).value=sel;list()};
  $('#se',el).onchange=()=>cat();$('#ca',el).onchange=list;$('#pa',el).onchange=list;
  $('#im',el).onclick=async()=>{const bt=$('#im',el),up=[];bt.disabled=true;
    try{let c=$('#ca',el).value;const nc=$('#nc',el).value.trim();
      const rows=$('#tx',el).value.split('\n').map(s=>s.trim()).filter(Boolean).map((l,i)=>{try{return {...parse(a.k,l),kind:a.k,palier:+$('#pa',el).value,weekly:!car&&$('#wk',el).checked}}catch(e){throw Error('Ligne '+(i+1)+' : '+e.message)}});
      if(!rows.length)throw Error('Rien à importer');
      const mp=new Map([...$('#fm',el).files].map(f=>[f.name.toLowerCase(),f])),com=$('#fi',el).files[0],cache=new Map();
      const put=async f=>{const k=f.name+f.size+f.lastModified;if(!cache.has(k)){const p=await upImg(f);up.push(p);cache.set(k,p)}return cache.get(k)};
      const need=n=>{const f=mp.get(n.toLowerCase());if(!f)throw Error('Schéma introuvable dans « Schémas du lot » : '+n);return f};
      rows.forEach(r=>{r._i&&need(r._i);r._b&&need(r._b)});if(rows.some(r=>r._i||r._b||com))toast('Envoi des schémas…');
      for(const r of rows){if(r._i)r.image=await put(need(r._i));else if(com)r.image=await put(com);if(r._b)r.back_image=await put(need(r._b));delete r._i;delete r._b}
      if(nc){const {data,error}=await sb.from('categories').insert({sector_id:$('#se',el).value,name:nc}).select().single();if(error)throw error;c=data.id}
      if(!c)throw Error('Choisis ou crée une catégorie');rows.forEach(r=>r.category_id=+c);
      const {error}=await sb.from('items').insert(rows);if(error)throw error;
      toast(rows.length+' ajoutée(s)','ok');$('#tx',el).value='';$('#nc',el).value='';$('#fi',el).value='';$('#fm',el).value='';await cat(c)}
    catch(x){await rmImg(up);toast(x.message,'ko')}finally{bt.disabled=false}};
  cat()}},
arank:{t:'Classement',tip:'Vrais noms et pseudos, visibles par toi seul. Semaine en cours, cumul général, archives des cycles. Le bouton du bas clôture le cycle.',r(el){
  el.innerHTML=`<label>Secteur<select id=se>${sectOpts()}</select></label><label id=lfw hidden>Ligue<select id=lf></select></label><div class=tabs><button data-m=w class=on>Semaine</button><button data-m=n>Général</button><button data-m=a>Archives</button></div><div id=li class=stack></div><button class="btn hot" id=cl>Clôturer le cycle</button>`;
  let m='w';const L=$('#li',el);
  const go=async()=>{const sec=$('#se',el).value;const {data:lc}=await sb.from('league_cfg').select('*').eq('sector_id',sec).maybeSingle(),LGon=!!lc?.enabled,lgx=x=>LGon?(lc.mode==='rang'?rl(x.nx):x.league):0;
    $('#lfw',el).hidden=!LGon;if(LGon){const cur=$('#lf',el).value||'0';$('#lf',el).innerHTML='<option value=0>Toutes les ligues'+(lc.mode==='rang'?LGR:LGP).map((t,i)=>`<option value=${i+1}>${t[0]} ${t[1]}`).join('');$('#lf',el).value=cur}
    if(m==='a'){const {data,error}=await sb.from('weekly_archive').select('*').eq('sector_id',sec).order('week_start',{ascending:false}).order('pos').limit(400);
      if(error)return toast(error.message,'ko');
      const G={};data.forEach(x=>(G[x.week_start+'|'+x.week_end]??=[]).push(x));
      L.innerHTML=Object.values(G).map(r=>`<h3>Du ${fd(r[0].week_start)} au ${fd(r[0].week_end)}</h3>`+r.filter(x=>x.wnx>0||x.badges.length).slice(0,10).map(x=>`<div class="row lb ${MC[x.pos-1]||''}"><b>${x.pos}</b><span>${esc(x.pseudo)} <small>${esc(x.full_name)}</small><br><small>${x.badges.map(b=>BD[b]||b).join(' · ')||'—'} · ${x.active_days} j actifs · ${x.accuracy} %</small></span><b>${x.wnx}</b></div>`).join('')).join('')||'<p class=empty>Aucune archive.</p>';return}
    const {data}=await sb.from('profiles').select('full_name,pseudo,nx,wnx,league').eq('role','nexian').eq('sector_id',sec).order(m==='w'?'wnx':'nx',{ascending:false});
    const fl=+$('#lf',el).value||0,F=(data||[]).filter(x=>!LGon||!fl||lgx(x)===fl);L.innerHTML=F.map((x,i)=>`<div class="row lb ${MC[i]||''}"><b>${MED[i]||i+1}</b><span>${esc(x.pseudo)} <small>${esc(x.full_name)}</small>${LGon?` <small>${lgTag(lc.mode,lgx(x))}</small>`:''}</span><em>${rank(x.nx)}</em><b>${m==='w'?x.wnx:x.nx}</b></div>`).join('')||'<p class=empty>Aucun Nexian.</p>'};
  const tab=v=>{m=v;$$('[data-m]',el).forEach(b=>b.classList.toggle('on',b.dataset.m===v));go()};
  $$('[data-m]',el).forEach(b=>b.onclick=()=>tab(b.dataset.m));$('#se',el).onchange=go;$('#lf',el).onchange=go;
  $('#cl',el).onclick=async()=>{if(!confirm('Clôturer le cycle en cours ?\n\n• Le classement de chaque secteur est archivé, avec les badges (Or, Argent, Bronze, Progression, Assiduité, Précision, Révélation).\n• Dans les secteurs où les ligues sont activées en mode « promotion », le haut de chaque ligue monte et le bas descend.\n• Les badges permanents sont recalculés.\n• Les NX de la semaine repartent à 0 pour tous les Nexians.\n• Les NX totaux et les rangs ne changent pas.\n\nAction définitive.'))return;
    const b=$('#cl',el);b.disabled=true;try{const {data,error}=await sb.rpc('close_week');if(error)throw error;toast('Cycle clôturé : '+data.archived+' Nexians archivés','ok');tab('a')}catch(x){toast(x.message,'ko')}finally{b.disabled=false}};
  go()}},
ahat:{t:'Chapeaux',tip:'Un chapeau est un groupe de Nexians que tu choisis pour un mini-concours. Seuls ses membres le voient.',async r(el){
  const {data,error}=await sb.from('hats').select('*,hat_members(count)').order('id',{ascending:false});if(error)return el.innerHTML=`<p class=err>${esc(error.message)}</p>`;
  el.innerHTML=`<button class="btn hot" data-go=ahatd>+ Créer un chapeau</button><div class=stack>${data.map(h=>`<button class=row data-go=ahatd data-a="${A(h)}">🎩 ${esc(h.name)}<span>${h.closed?'terminé':'en cours'} · ${h.hat_members?.[0]?.count||0} membre(s)</span></button>`).join('')||'<p class=empty>Aucun chapeau.</p>'}</div>`}},
ahatd:{t:'Chapeau',tip:'Choisis les membres, suis le classement, puis clôture : le vainqueur reçoit le badge Champion de chapeau.',async r(el,h){
  if(!h){
    el.innerHTML=`<div class=form><label>Nom du concours<input id=hn maxlength=60 placeholder="Ex : Mini-concours Génie Chimique"></label><label>Description (visible des membres)<input id=ht maxlength=120></label><label>Secteur (pour proposer les bons Nexians)<select id=hse><option value="">Tous les secteurs${sectOpts()}</select></label><label>Catégorie (optionnel : seules ses questions comptent)<select id=hca><option value="">Toutes les catégories</select></label><button class="btn hot" id=hc>Créer</button></div>`;
    $('#hse',el).onchange=async()=>{const s=$('#hse',el).value;$('#hca',el).innerHTML='<option value="">Toutes les catégories'+(s?((await sb.from('categories').select('*').eq('sector_id',s).order('name')).data||[]).map(c=>`<option value=${c.id}>${esc(c.name)}`).join(''):'')};
    $('#hc',el).onclick=async()=>{const name=$('#hn',el).value.trim();if(!name)return toast('Donne un nom au concours','ko');
      const {data:d,error}=await sb.from('hats').insert({name,note:$('#ht',el).value.trim()||null,sector_id:+$('#hse',el).value||null,category_id:+$('#hca',el).value||null}).select().single();
      if(error)return toast(error.message,'ko');toast('Chapeau créé : ajoute maintenant les membres','ok');const e=stack.at(-1);e.a=d;draw(e)};
    return}
  const [{data:P},{data:M}]=await Promise.all([sb.from('profiles').select('id,full_name,pseudo,nx,league,sector_id').eq('role','nexian').order('full_name'),sb.from('hat_members').select('user_id').eq('hat_id',h.id)]);
  let old=new Set((M||[]).map(x=>x.user_id));const mem=new Set(old),LP=(P||[]).filter(p=>!h.sector_id||p.sector_id===h.sector_id),ro=h.closed;
  el.innerHTML=`<h3>🎩 ${esc(h.name)}</h3><p class=cnt>${ro?'Terminé':'En cours'} depuis le ${fd(String(h.starts_at).slice(0,10))}${h.note?' · '+esc(h.note):''}</p><h3>Classement</h3><div id=bd class=stack></div>${ro?'':'<button class="btn hot" id=hx>Clôturer le concours</button>'}<h3>Membres (<span id=mc>${mem.size}</span>)</h3>${ro?'':`<label>Rechercher<input id=hq></label><label>Cocher toute une ligue<select id=hl><option value=0>Choisir…${LGP.map((t,i)=>`<option value=${i+1}>${t[0]} ${t[1]}`).join('')}</select></label><div class=tabs><button id=ha>Tout cocher</button><button id=hz>Tout décocher</button></div>`}<div id=pl class=stack></div>${ro?'':'<button class="btn hot" id=hs>Enregistrer les membres</button>'}<button class="btn ghost" id=hd>Supprimer ce chapeau</button>`;
  const q=()=>($('#hq',el)?.value||'').toLowerCase(),vis=()=>LP.filter(p=>(p.full_name+' '+p.pseudo).toLowerCase().includes(q()));
  const list=()=>{$('#pl',el).innerHTML=vis().map(p=>`<label class=row><span>${esc(p.full_name)} <small>${esc(p.pseudo)} · ${LGP[p.league-1]?.[1]||''} · ${p.nx} NX</small></span><input type=checkbox data-u=${p.id} ${mem.has(p.id)?'checked':''} ${ro?'disabled':''}></label>`).join('')||'<p class=empty>Aucun Nexian.</p>';
    $$('[data-u]',el).forEach(c=>c.onchange=()=>{c.checked?mem.add(c.dataset.u):mem.delete(c.dataset.u);$('#mc',el).textContent=mem.size})};
  const board=async()=>{const {data:B,error}=await sb.rpc('hat_board',{p_hat:h.id});$('#bd',el).innerHTML=error?`<p class=err>${esc(error.message)}</p>`:(B||[]).map((x,i)=>`<div class="row lb ${x.score>0?MC[i]||'':''}"><b>${x.score>0?MED[i]||i+1:i+1}</b><span>${esc(x.pseudo)} <small>${esc(x.full_name||'')}</small></span><b>${x.score}</b></div>`).join('')||'<p class=empty>Aucun membre pour le moment.</p>'};
  const setAll=(f,on)=>{vis().filter(f).forEach(p=>on?mem.add(p.id):mem.delete(p.id));$('#mc',el).textContent=mem.size;list()};
  if(!ro){$('#hq',el).oninput=list;$('#ha',el).onclick=()=>setAll(()=>true,1);$('#hz',el).onclick=()=>setAll(()=>true,0);$('#hl',el).onchange=e=>{const v=+e.target.value;if(v)setAll(p=>p.league===v,1);e.target.value=0};
    $('#hs',el).onclick=async()=>{try{const rm=[...old].filter(x=>!mem.has(x)),ad=[...mem].filter(x=>!old.has(x));
      if(rm.length){const {error}=await sb.from('hat_members').delete().eq('hat_id',h.id).in('user_id',rm);if(error)throw error}
      if(ad.length){const {error}=await sb.from('hat_members').insert(ad.map(u=>({hat_id:h.id,user_id:u})));if(error)throw error}
      old=new Set(mem);toast('Membres enregistrés','ok');board()}catch(x){toast(x.message,'ko')}};
    $('#hx',el).onclick=async()=>{if(!confirm('Clôturer ce concours ?\n\nLe classement est figé et le vainqueur reçoit le badge Champion de chapeau. Action définitive.'))return;
      const {data:d,error}=await sb.rpc('close_hat',{p_hat:h.id});if(error)return toast(error.message,'ko');toast('Concours clôturé'+(d?.[0]?' · vainqueur : '+d[0].pseudo+' ('+d[0].full_name+')':''),'ok');const e=stack.at(-1);e.a={...h,closed:true,ends_at:new Date().toISOString()};draw(e)}}
  $('#hd',el).onclick=async()=>{if(!confirm('Supprimer ce chapeau et son classement ?'))return;const {error}=await sb.from('hats').delete().eq('id',h.id);if(error)return toast(error.message,'ko');pop()};
  board();list()}},
abulk:{t:'Import massif',tip:'Un seul fichier pour plusieurs catégories et 30+ paliers (donjons, Nexify, cartes, titres, schémas). Vérifie d’abord, importe ensuite. Les questions déjà présentes sont ignorées : tu peux relancer sans risque.',r(el){
  el.innerHTML=`<div class=form><label>Secteur<select id=se>${sectOpts()}</select></label>
  <label>Fichier(s) .txt (ou colle le texte ci-dessous)<input type=file id=ff accept=".txt,text/plain" multiple></label>
  <label>Contenu<textarea id=tx rows=9 placeholder="# Hydrometallurgy&#10;## PALIER 1&#10;### DONJON [20;10;5]&#10;Question | A;B;C (2)"></textarea></label>
  <label>Schémas du lot (tous les fichiers cités par @nom.png)<input type=file id=fm multiple accept="${FA}"></label>
  <label>Questions attendues par bloc (alerte si différent, 0 = ne pas contrôler)<input id=ex type=number min=0 value=10></label>
  <label class=chk><input type=checkbox id=wk>⭐ Marquer donjons et Nexify « Défi de la semaine » (déconseillé pour un gros import)</label>
  <label class=chk><input type=checkbox id=rpl>♻ Remplacer le contenu existant des paliers du fichier (pour corriger : efface les tentatives des joueurs sur ces paliers)</label>
  <div class=tabs><button id=vf>Vérifier</button><button id=md>Télécharger un modèle</button></div><div id=rp class=stack></div><button class="btn hot" id=im disabled>Importer</button><p class=cnt id=pg></p></div>`;
  let ok=null;const rp=$('#rp',el),read=async()=>{let t=$('#tx',el).value;for(const f of $('#ff',el).files)t+='\n'+await f.text();return t};
  $('#md',el).onclick=()=>save(new Blob(['\ufeff'+MTPL],{type:'text/plain'}),'modele-import-nexi-lab.txt');
  ['tx','ff','fm','ex'].forEach(i=>$('#'+i,el).addEventListener('change',()=>{ok=null;$('#im',el).disabled=true}));$('#tx',el).addEventListener('input',()=>{ok=null;$('#im',el).disabled=true});
  $('#vf',el).onclick=async()=>{const r=parseMass(await read(),+$('#ex',el).value||0),have=new Set([...$('#fm',el).files].map(f=>f.name.toLowerCase())),miss=[...r.imgs].filter(x=>!have.has(x));
    miss.forEach(x=>r.errors.push('Schéma introuvable dans « Schémas du lot » : '+x));if(!r.cats.length&&!r.errors.length)r.errors.push('Aucune catégorie trouvée : commence par une ligne « # Nom de la catégorie ».');
    const tot=r.cats.reduce((s,c)=>s+c.rows.length,0);
    rp.innerHTML=(r.errors.length?`<p class=err>❌ ${r.errors.length} erreur(s) : rien ne sera importé tant qu’elles ne sont pas corrigées.</p>`+r.errors.slice(0,12).map(e=>`<p class=err>${esc(e)}</p>`).join('')+(r.errors.length>12?`<p class=cnt>… et ${r.errors.length-12} autre(s)</p>`:''):`<p class=cnt>✅ ${tot} ligne(s) prêtes · ${r.cats.length} catégorie(s)${r.imgs.size?' · '+r.imgs.size+' schéma(s)':''}</p>`)
      +r.cats.map(c=>{const P=[...new Set(c.rows.map(x=>x.palier))],cn=k=>c.rows.filter(x=>x.kind===k).length;return `<div class=row><span>${esc(c.name)}<br><small>${P.length} palier(s) · ${c.titles.size} titre(s) · donjon ${cn('donjon')} · nexify ${cn('nexify')} · carte ${cn('carte')}</small></span><b>${c.rows.length}</b></div>`}).join('')
      +(r.warn.length?`<p class=warn>⚠️ ${r.warn.length} avertissement(s)</p>`+r.warn.slice(0,8).map(e=>`<p class=cnt>${esc(e)}</p>`).join(''):'');
    ok=r.errors.length?null:r;$('#im',el).disabled=!ok};
  $('#im',el).onclick=async e=>{if(!ok)return;const b=e.target,sec=$('#se',el).value;if(!confirm('Importer '+ok.cats.length+' catégorie(s) dans le secteur « '+$('#se',el).selectedOptions[0].text+' » ?'+($('#rpl',el).checked?'\n\n♻ Les paliers du fichier seront REMPLACÉS (tentatives des joueurs effacées).':'')))return;
    b.disabled=true;const files=new Map([...$('#fm',el).files].map(f=>[f.name.toLowerCase(),f])),up=new Map(),done=new Set(),res=[];
    const put=async nm=>{if(!up.has(nm))up.set(nm,await upImg(files.get(nm.toLowerCase())));return up.get(nm)};
    try{for(let ci=0;ci<ok.cats.length;ci++){const c=ok.cats[ci],mine=[];$('#pg',el).textContent='Catégorie '+(ci+1)+' / '+ok.cats.length+' : '+c.name+'…';
      try{const rows=[];for(const r of c.rows){const o={kind:r.kind,palier:r.palier,question:r.question,options:r.options,answer:r.answer,secs:r.secs,nx:r.nx,bonus:r.bonus,factor:r.factor,back:r.back};
          for(const [k,s] of [['image',r._i],['back_image',r._b]])if(s){const had=up.has(s);o[k]=await put(s);if(!had)mine.push(o[k])}
          rows.push(o)}
        const {data,error}=await sb.rpc('import_bulk',{p_sector:+sec,p_cat:c.name,p_rows:rows,p_weekly:$('#wk',el).checked,p_titles:[...c.titles].map(([palier,title])=>({palier,title})),p_replace:$('#rpl',el).checked});if(error)throw error;
        mine.forEach(x=>done.add(x));[...up.values()].forEach(x=>done.add(x));res.push(data)}
      catch(x){await rmImg(mine.filter(y=>!done.has(y)));throw Error(c.name+' : '+(/import_bulk/.test(x.message)?'fonction manquante. Lance supabase/mises-a-jour/migration_import.sql (voir le guide)':x.message))}}
      const I=res.reduce((s,x)=>s+x.inserted,0),K=res.reduce((s,x)=>s+x.skipped,0);
      rp.innerHTML=`<p class=cnt>✅ Terminé : ${I} ajoutée(s), ${K} déjà présente(s) ignorée(s).</p>`+res.map(x=>`<div class=row><span>${esc(x.category)}</span><b>+${x.inserted}</b></div>`).join('');$('#pg',el).textContent='';toast(I+' ligne(s) importée(s)','ok');ok=null}
    catch(x){toast(x.message,'ko');rp.insertAdjacentHTML('afterbegin',`<p class=err>❌ ${esc(x.message)}${res.length?' (catégories déjà importées : '+res.length+' ; relancer ignore les doublons)':''}</p>`);$('#pg',el).textContent=''}
    finally{b.disabled=!ok}}}},
asante:{t:'Santé & archives',tip:'Surveille l’espace utilisé sur Supabase (gratuit : 500 Mo de base, 1 Go de fichiers) et archive l’historique ancien sans rien perdre.',async r(el){
  const [{data:u,error},{data:cfg},{data:log}]=await Promise.all([sb.rpc('usage_report'),sb.from('app_cfg').select('*').single(),sb.from('archive_log').select('*').order('month',{ascending:false})]);
  if(error)return el.innerHTML=`<p class=err>${esc(error.message)}</p>`;
  const MB=b=>(b/1048576).toFixed(b>1e8?0:1),col=p=>p>=90?'#ff2d45':p>=70?'#ffb347':'#3dff9a',
    bar=(l,v,p,lim)=>`<div class=meter><div class=ml><b>${l}</b><span>${MB(v)} Mo / ${lim} Mo · ${p} %</span></div><div class=mb><i style="width:${Math.min(100,p)}%;background:${col(p)}"></i></div></div>`,mo=x=>String(x).slice(0,7);
  el.innerHTML=`${cfg.emergency?'<p class="alert crit">🚨 Mode économie actif : le détail des donjons n’est plus enregistré (scores, NX, classements et badges continuent de fonctionner). Archive et nettoie, puis désactive le mode économie.</p>':''}
  <div class=form>${bar('Base de données',u.db_bytes,u.db_pct,cfg.db_limit_mb)}${bar('Fichiers (schémas, photos, archives)',u.storage_bytes,u.storage_pct,cfg.storage_limit_mb)}
  <p class=cnt>Schémas ${MB(u.buckets.diagrams||0)} Mo · photos ${MB(u.buckets.avatars||0)} Mo · archives ${MB(u.buckets.archives||0)} Mo</p>
  <p class=cnt>Plus grosses tables : ${u.tables.slice(0,4).map(t=>esc(t.name)+' '+MB(t.bytes)+' Mo').join(' · ')}</p></div>
  <div class=form><h3>Archiver l’historique ancien</h3><p class=cnt>Les parties de plus de ${u.keep_days} jours sont enregistrées dans un fichier compressé (conservé dans ton stockage), vérifiées, puis résumées par mois. Les totaux, scores, rangs et badges ne changent pas.</p>
  ${u.months.length?u.months.map(x=>`<div class=row><span>${mo(x.month)}</span><b>${x.rows} lignes</b></div>`).join('')+'<button class="btn hot" id=ar>Archiver maintenant</button>':'<p class=empty>Rien à archiver pour le moment.</p>'}<p class=cnt id=arp></p></div>
  ${(log||[]).length?`<div class=form><h3>Archives conservées</h3>${log.map(x=>`<div class=row><span>${mo(x.month)} · ${x.rows} lignes</span><button class=ghost data-dl="${esc(x.path)}">Télécharger</button></div>`).join('')}</div>`:''}
  <div class=form><h3>Nettoyage</h3><p class=cnt>Supprime les tickets périmés et les fichiers inutilisés (images de questions supprimées, photos de comptes supprimés).</p><button class="btn hot" id=mt>Nettoyer maintenant</button>${cfg.emergency?'<button class="btn ghost" id=em>Désactiver le mode économie</button>':''}</div>
  <div class=form><h3>Sauvegarde</h3><p class=cnt>Un fichier complet (.json) pour tout restaurer, ou des tableaux .csv à ouvrir dans Excel / Google Sheets.</p><button class="btn hot" id=bj>Sauvegarde complète (.json)</button><button class="btn ghost" id=bc>Tableaux pour Google Sheets (.csv)</button></div>
  <div class=form><h3>Réglages</h3><label>Garder le détail des parties pendant (jours, 14 minimum)<input id=kd type=number min=14 value=${cfg.keep_days}></label><label>Limite de la base (Mo) — change-la si tu passes à un plan payant<input id=dl type=number min=1 value=${cfg.db_limit_mb}></label><label>Limite des fichiers (Mo)<input id=sl type=number min=1 value=${cfg.storage_limit_mb}></label><button class="btn hot" id=sv>Enregistrer</button></div>`;
  const busy=async(b,f)=>{b.disabled=true;try{await f()}catch(x){toast(x.message||String(x),'ko')}finally{b.disabled=false}},redo=()=>{const e=stack.at(-1);if(e.v==='asante')draw(e)};
  $('#ar',el)&&($('#ar',el).onclick=e=>busy(e.target,async()=>{let n=0;for(const x of u.months){n+=await archiveMonth(mo(x.month),t=>$('#arp',el).textContent=t)}toast(n+' lignes archivées','ok');redo()}));
  $$('[data-dl]',el).forEach(b=>b.onclick=()=>busy(b,async()=>{const {data,error}=await sb.storage.from('archives').createSignedUrl(b.dataset.dl,120);if(error)throw error;const a=document.createElement('a');a.href=data.signedUrl;a.download=b.dataset.dl;a.click()}));
  $('#mt',el).onclick=e=>busy(e.target,async()=>{const {data:o,error:e0}=await sb.rpc('orphan_files');if(e0)throw e0;const sz=(o||[]).reduce((s,x)=>s+x.size,0);
    if(o.length&&!confirm(o.length+' fichier(s) inutilisé(s) ('+MB(sz)+' Mo) seront supprimés. Continuer ?'))return;
    for(const bk of [...new Set(o.map(x=>x.bucket))]){const N=o.filter(x=>x.bucket===bk).map(x=>x.name);for(let i=0;i<N.length;i+=100)await sb.storage.from(bk).remove(N.slice(i,i+100))}
    const {data:m,error}=await sb.rpc('maintenance');if(error)throw error;toast('Nettoyé : '+o.length+' fichier(s), '+m.tlog+' ligne(s) de tickets','ok');redo()});
  $('#em',el)&&($('#em',el).onclick=e=>busy(e.target,async()=>{const {error}=await sb.from('app_cfg').update({emergency:false}).eq('id',1);if(error)throw error;toast('Mode économie désactivé','ok');redo()}));
  $('#bj',el).onclick=e=>busy(e.target,async()=>{const d=await dumpTables(['profiles','sectors','categories','items','weekly_archive','palier_titles','user_stats','history_monthly','user_badges','hats','hat_members','archive_log']);
    save(new Blob([JSON.stringify({version:1,date:new Date().toISOString(),tables:d})],{type:'application/json'}),'nexi-lab-sauvegarde-'+new Date().toISOString().slice(0,10)+'.json');toast('Sauvegarde téléchargée','ok')});
  $('#bc',el).onclick=e=>busy(e.target,async()=>{const d=await dumpTables(['profiles','weekly_archive','user_stats']),day=new Date().toISOString().slice(0,10);
    const C={profiles:['full_name','pseudo','login','sector_id','plan','plan_end','nx','wnx','league','created_at'],weekly_archive:['week_start','week_end','sector_id','pseudo','full_name','wnx','pos','active_days','answers','accuracy','league','move'],user_stats:['user_id','answers','correct','donjon_ok','best_gain','first_at','last_at']};
    Object.keys(C).forEach((t,i)=>setTimeout(()=>save(new Blob(['\ufeff'+toCsv(C[t],d[t])],{type:'text/csv'}),'nexi-'+t+'-'+day+'.csv'),i*500));toast('Fichiers CSV téléchargés','ok')});
  $('#sv',el).onclick=e=>busy(e.target,async()=>{const {error}=await sb.from('app_cfg').update({keep_days:Math.max(14,+$('#kd',el).value||90),db_limit_mb:+$('#dl',el).value||500,storage_limit_mb:+$('#sl',el).value||1024}).eq('id',1);if(error)throw error;toast('Enregistré','ok');redo()})}},
aset:{t:'Réglages',tip:'Tickets, nombre de parties et accès Nexify par formule, plafond des mises.',async r(el){const AC=(await sb.from('app_cfg').select('*').single()).data||{stake_pct:25,stake_max:500};
  el.innerHTML=Object.values(CFG).map(c=>`<div class=form data-p=${c.plan}><h3>${esc(c.plan)}</h3><label>Tickets par jour<input data-k=tickets type=number value=${c.tickets}></label><label>Parties possibles par question<input data-k=replays type=number min=1 value=${c.replays}></label><label><input data-k=nexify type=checkbox ${c.nexify?'checked':''}>Accès Nexify</label><label><input data-k=cumul type=checkbox ${c.cumul?'checked':''}>Cumul des tickets non utilisés (1 jour)</label><button class="btn hot">Enregistrer</button></div>`).join('');
  el.insertAdjacentHTML('afterbegin',`<div class=form><h3>Mises Nexify (équité)</h3><label>Mise maximum en % du solde<input id=sp type=number min=1 max=100 value=${AC.stake_pct}></label><label>Plafond absolu d’une mise (NX)<input id=sm type=number min=1 value=${AC.stake_max}></label><button class="btn hot" id=sv>Enregistrer</button></div>`);
  const [{data:LC},{data:PL}]=await Promise.all([sb.from('league_cfg').select('*'),sb.from('profiles').select('sector_id').eq('role','nexian')]);
  const cnt={};(PL||[]).forEach(x=>cnt[x.sector_id]=(cnt[x.sector_id]||0)+1);const LM=Object.fromEntries((LC||[]).map(x=>[x.sector_id,x]));
  el.insertAdjacentHTML('afterbegin',`<div class=form id=lgs><h3>Ligues par secteur</h3><p class=cnt>Active les ligues là où il y a assez de joueurs (10 minimum conseillés). « Promotion » : tout le monde démarre Bronze, le haut monte et le bas descend à chaque clôture. « Par rang » : la ligue suit le rang NX.</p>${SECT.map(s=>{const c=LM[s.id]||{},n=cnt[s.id]||0;return `<div class=lgrow data-s=${s.id}><span>${esc(s.name)}<br><small class="${n<10?'warn':''}">${n} Nexian(s)${n<10?' · ⚠️ peu pour une ligue':''}</small></span><label><input type=checkbox data-e ${c.enabled?'checked':''}>Activée</label><select data-md><option value=promo ${c.mode!=='rang'?'selected':''}>Promotion<option value=rang ${c.mode==='rang'?'selected':''}>Par rang</select></div>`}).join('')}</div>`);
  $$('#lgs [data-s]',el).forEach(r=>{const sv=async()=>{const {error}=await sb.from('league_cfg').upsert({sector_id:+r.dataset.s,enabled:$('[data-e]',r).checked,mode:$('[data-md]',r).value},{onConflict:'sector_id'});toast(error?error.message:'Enregistré',error?'ko':'ok')};$('[data-e]',r).onchange=sv;$('[data-md]',r).onchange=sv});
  $('#sv',el).onclick=async()=>{const {error}=await sb.from('app_cfg').update({stake_pct:+$('#sp',el).value,stake_max:+$('#sm',el).value}).eq('id',1);toast(error?error.message:'Enregistré',error?'ko':'ok')};
  $$('[data-p] button',el).forEach(b=>b.onclick=async()=>{const d=b.parentElement,o={};$$('[data-k]',d).forEach(i=>o[i.dataset.k]=i.type==='checkbox'?i.checked:+i.value);
    const {error}=await sb.from('plan_cfg').update(o).eq('plan',d.dataset.p);if(!error)Object.assign(CFG[d.dataset.p],o);toast(error?error.message:'Enregistré',error?'ko':'ok')})}}
};

if('serviceWorker' in navigator)addEventListener('load',()=>navigator.serviceWorker.register('sw.js'));
(async()=>{let ok=false;try{const {data}=await sb.auth.getSession();ok=!!(data?.session&&await boot())}catch(e){console.warn(e)}if(!ok)reset('home')})();
