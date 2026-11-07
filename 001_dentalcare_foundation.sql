/* Dental OS Care - receptionist + dentist clinic manager (no server, runs in browser) */
const PINS={receptionist:'1111',dentist:'2222'}; // CHANGE THESE
const PROCS={
"Diagnosis":[["Consultation / Checkup",500],["IOPA X-ray",500],["OPG X-ray",2500],["CBCT Scan",6000]],
"Preventive":[["Scaling & Polishing",3000],["Fluoride Application",1500],["Fissure Sealant",1500]],
"Restorative":[["Composite Filling",3000],["GIC Filling",2000],["Amalgam Filling",2000],["Temporary Filling",1000],["Core Buildup",3000]],
"Endodontics (RCT)":[["RCT Anterior",8000],["RCT Premolar",10000],["RCT Molar",15000],["Re-RCT",15000],["Pulpotomy",3000],["Pulpectomy",4000]],
"Oral Surgery":[["Simple Extraction",2000],["Surgical Extraction",5000],["Wisdom Tooth Removal",8000],["Abscess Drainage",2000],["Apicectomy",12000],["Biopsy",5000]],
"Prosthodontics":[["PFM Crown",12000],["Zirconia Crown",25000],["Bridge (per unit)",12000],["Complete Denture",30000],["Partial Denture",15000],["Veneer",25000],["Post & Core",5000]],
"Implants":[["Implant Placement",80000],["Bone Graft",30000],["Sinus Lift",60000]],
"Orthodontics":[["Metal Braces",80000],["Ceramic Braces",120000],["Clear Aligners",250000],["Retainer",10000],["Monthly Adjustment",3000]],
"Gums (Perio)":[["Deep Cleaning (SRP)",5000],["Gingivectomy",5000],["Flap Surgery",10000]],
"Cosmetic":[["Teeth Whitening",15000],["Smile Design",50000],["Gum Contouring",10000]],
"Pediatric":[["Pulpotomy (Child)",3000],["Stainless Steel Crown",5000],["Space Maintainer",5000]]};
const UP=[18,17,16,15,14,13,12,11,21,22,23,24,25,26,27,28],LO=[48,47,46,45,44,43,42,41,31,32,33,34,35,36,37,38];
const $=s=>document.querySelector(s),h=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const today=()=>new Date().toISOString().slice(0,10),uid=()=>Math.random().toString(36).slice(2,10),rs=n=>'Rs '+Number(n||0).toLocaleString('en-PK');
let db=JSON.parse(localStorage.getItem('dentalos')||'{"patients":[]}');
const save=()=>localStorage.setItem('dentalos',JSON.stringify(db));
const S={user:sessionStorage.getItem('role'),view:'list',pid:null,sel:[],q:'',due:false};
const cur=()=>db.patients.find(x=>x.id===S.pid);
/* image store (IndexedDB) */
const idb=new Promise(r=>{const q=indexedDB.open('dentalos-img',1);q.onupgradeneeded=()=>q.result.createObjectStore('i');q.onsuccess=()=>r(q.result)});
const tx=async(m,f)=>{const d=await idb;return new Promise(r=>{const t=d.transaction('i',m),s=f(t.objectStore('i'));t.oncomplete=()=>r(s.result)})};
const imgPut=(k,v)=>tx('readwrite',s=>s.put(v,k)),imgGet=k=>tx('readonly',s=>s.get(k)),imgDel=k=>tx('readwrite',s=>s.delete(k));
const shrink=f=>new Promise(res=>{const r=new FileReader();r.onload=()=>{const i=new Image();i.onload=()=>{const k=Math.min(1,1400/Math.max(i.width,i.height)),c=document.createElement('canvas');c.width=i.width*k;c.height=i.height*k;c.getContext('2d').drawImage(i,0,0,c.width,c.height);res(c.toDataURL('image/jpeg',.8))};i.src=r.result};r.readAsDataURL(f)});
/* helpers */
const money=p=>{const t=p.treatments.reduce((a,x)=>a+ +x.fee,0),pd=p.payments.reduce((a,x)=>a+ +x.amount,0);return{t,pd,b:t-pd}};
const tstat=(p,t)=>{let s='';p.treatments.forEach(x=>{if(x.teeth.includes(t))s=x.status==='done'?'done':(s||'plan')});return s};
const isDue=p=>p.followUp&&p.followUp.date&&p.followUp.date<=today();
const go=(v,id)=>{S.view=v;if(id!==undefined)S.pid=id;S.sel=[];render();scrollTo(0,0)};
/* login */
function login(){const r=$('#role').value;if($('#pin').value===PINS[r]){S.user=r;sessionStorage.setItem('role',r);render()}else alert('Wrong PIN')}
function logout(){S.user=null;sessionStorage.removeItem('role');render()}
/* views */
function render(){const a=$('#app');
 if(!S.user){a.innerHTML=`<div class="login card"><h2>Dental OS Care</h2><select id="role"><option value="receptionist">Receptionist</option><option value="dentist">Dentist</option></select><input id="pin" type="password" placeholder="PIN" onkeydown="if(event.key==='Enter')login()"><button onclick="login()">Log in</button></div>`;return}
 a.innerHTML=`<div class="bar"><b>Dental OS Care</b><span>${S.user}</span><button onclick="backup()">Backup</button><label><button onclick="this.nextElementSibling.click()">Restore</button><input type="file" accept=".json" hidden onchange="restore(this.files[0])"></label><button onclick="logout()">Log out</button></div>`+
 (S.view==='list'?listView():S.view==='form'?formView():patientView());
 if(S.view==='patient')document.querySelectorAll('img[data-id]').forEach(async e=>e.src=await imgGet(e.dataset.id)||'');
 if(S.view==='list')rows()}
function listView(){return `<div class="wrap"><div class="row"><input type="search" id="q" placeholder="Search name or phone" value="${h(S.q)}" oninput="S.q=this.value;rows()"><button onclick="S.due=!S.due;render()">${S.due?'Show all':'Follow-ups due'}</button><button onclick="S.pid=null;go('form')">+ New patient</button></div><div class="card"><table><thead><tr><th>Patient</th><th>Phone</th><th>Balance</th><th>Next follow-up</th></tr></thead><tbody id="rows"></tbody></table></div></div>`}
function rows(){const q=S.q.toLowerCase(),l=db.patients.filter(p=>(p.name+p.phone).toLowerCase().includes(q)&&(!S.due||isDue(p)));
 $('#rows').innerHTML=l.map(p=>`<tr class="pt" onclick="go('patient','${p.id}')"><td>${h(p.name)}</td><td>${h(p.phone)}</td><td>${rs(money(p).b)}</td><td>${p.followUp&&p.followUp.date?`<span class="${isDue(p)?'tag due':''}">${h(p.followUp.date)}</span>`:'-'}</td></tr>`).join('')||'<tr><td colspan="4" class="muted">No patients yet. Add the first one.</td></tr>'}
function formView(){const p=cur()||{};const f=(id,l,t='text')=>`<label>${l}<input id="${id}" type="${t}" value="${h(p[id])}"></label>`;
 return `<div class="wrap"><button class="ghost" onclick="go('${p.id?'patient':'list'}')">← Back</button><div class="card"><h3>${p.id?'Edit patient':'New patient'}</h3><div class="grid">${f('name','Full name')}${f('phone','Phone number','tel')}${f('age','Age','number')}<label>Gender<select id="gender">${['Male','Female','Other'].map(g=>`<option ${p.gender===g?'selected':''}>${g}</option>`).join('')}</select></label></div><div class="grid" style="margin-top:10px">${f('address','Address')}${f('history','Allergies / medical history')}</div><div class="row"><button onclick="saveP()">Save patient</button></div></div></div>`}
function saveP(){const v=k=>$('#'+k).value.trim();if(!v('name')||!v('phone'))return alert('Name and phone are required');
 let p=cur();if(!p){p={id:uid(),treatments:[],payments:[],images:[],followUp:{}};db.patients.push(p);S.pid=p.id}
 Object.assign(p,{name:v('name'),phone:v('phone'),age:v('age'),gender:$('#gender').value,address:v('address'),history:v('history')});save();go('patient')}
function editP(){go('form')}
function delP(){const p=cur();if(!confirm('Delete '+p.name+' and all records?'))return;p.images.forEach(i=>imgDel(i.id));db.patients=db.patients.filter(x=>x!==p);save();go('list')}
function chart(p){const b=n=>`<button class="tooth t${n%10} ${tstat(p,n)} ${S.sel.includes(n)?'sel':''}" data-t="${n}" onclick="tt(${n})" title="Tooth ${n}">${n}</button>`;
 return `<div class="chart"><div class="arch">${UP.map(b).join('')}</div><div class="mid"></div><div class="arch low">${LO.map(b).join('')}</div></div>`}
function patientView(){const p=cur(),m=money(p),dn=S.user==='dentist',f=p.followUp||{};
 const opts=Object.entries(PROCS).map(([g,l])=>`<optgroup label="${g}">${l.map(([n,x])=>`<option data-fee="${x}">${h(n)}</option>`).join('')}</optgroup>`).join('');
 return `<div class="wrap"><button class="ghost" onclick="go('list')">← Patients</button>
<div class="head"><div><h2>${h(p.name)}</h2><p class="muted">${h(p.phone)}, ${h(p.address)}, ${h(p.age)} yrs, ${h(p.gender)}</p>${p.history?`<p class="warn">Medical: ${h(p.history)}</p>`:''}</div><div class="row"><button onclick="editP()">Edit</button><button class="danger" onclick="delP()">Delete</button></div></div>
<div class="stats"><div><small>Total treatment</small><b>${rs(m.t)}</b></div><div><small>Paid</small><b>${rs(m.pd)}</b></div><div class="bal"><small>Remaining</small><b>${rs(m.b)}</b></div><div><small>Next follow-up</small><b>${h(f.date||'Not set')}</b></div></div>
<div class="card"><h3>Teeth chart (tap to select)</h3><p class="muted">Green = done, yellow = planned, teal = selected.</p>${chart(p)}<div class="row"><button onclick="full()">Full mouth / general</button><button onclick="S.sel=[];render()">Clear</button><span id="selTxt">Selected: ${S.sel.join(', ')||'none'}</span></div>
${dn?`<div class="grid"><label>Procedure<select id="proc" onchange="pc()"><option value="">Select…</option>${opts}<option data-fee="0">Other (write in notes)</option></select></label><label>Fee (Rs)<input id="fee" type="number" value="0"></label><label>Status<select id="st"><option value="planned">Planned</option><option value="done">Done</option></select></label><label>Notes<input id="tn"></label></div><div class="row"><button onclick="addTx()">Add procedure</button></div>`:'<p class="muted">Only the dentist can add procedures.</p>'}</div>
<div class="card"><h3>Procedures</h3><table>${p.treatments.map(x=>`<tr><td>${h(x.date)}</td><td>${h(x.teeth.join(', '))}</td><td>${h(x.proc)}<br><small class="muted">${h(x.notes)}</small></td><td>${rs(x.fee)}</td><td>${dn?`<button class="tag ${x.status==='done'?'done':''}" onclick="flip('${x.id}')">${x.status}</button> <button class="danger" onclick="del('treatments','${x.id}')">x</button>`:`<span class="tag ${x.status==='done'?'done':''}">${x.status}</span>`}</td></tr>`).join('')||'<tr><td class="muted">No procedures yet.</td></tr>'}</table></div>
<div class="card"><h3>Payments</h3><div class="row"><input id="pa" type="number" placeholder="Amount received"><input id="pn" placeholder="Note (cash / easypaisa)"><button onclick="addPay()">Add payment</button></div><table>${p.payments.map(x=>`<tr><td>${h(x.date)}</td><td>${rs(x.amount)}</td><td>${h(x.note)}</td><td>${h(x.by)}</td><td><button class="danger" onclick="del('payments','${x.id}')">x</button></td></tr>`).join('')}</table></div>
<div class="card"><h3>Next follow-up</h3><div class="row"><input id="fd" type="date" value="${h(f.date)}"><input id="fn" placeholder="Reason / next procedure" value="${h(f.note)}" style="flex:1"><button onclick="saveF()">Save</button></div></div>
<div class="card"><h3>Photos and X-rays</h3><div class="row"><select id="ic"><option>Mouth photo</option><option>X-ray</option><option>Other</option></select><input id="inote" placeholder="Note"><input id="ifile" type="file" accept="image/*" multiple><button onclick="upImg()">Upload${S.sel.length?' (tag teeth '+S.sel.join(',')+')':''}</button></div><div class="imgs">${p.images.map(i=>`<figure><img data-id="${i.id}" alt="${h(i.cat)}" onclick="view('${i.id}')"><b>${h(i.cat)}</b> ${h(i.date)}<br>${i.teeth.length?'Teeth: '+h(i.teeth.join(', '))+'<br>':''}${h(i.note)}<br><button class="danger" onclick="delImg('${i.id}')">Delete</button></figure>`).join('')}</div></div></div>`}
/* actions */
function tt(n){const i=S.sel.indexOf(n);i<0?S.sel.push(n):S.sel.splice(i,1);document.querySelector(`[data-t="${n}"]`).classList.toggle('sel');$('#selTxt').textContent='Selected: '+(S.sel.join(', ')||'none');pc()}
function full(){S.sel=['Full mouth'];render()}
function pc(){const o=$('#proc');if(!o||!o.selectedOptions[0])return;const n=S.sel.filter(t=>t!=='Full mouth').length||1;$('#fee').value=(+o.selectedOptions[0].dataset.fee||0)*n}
function addTx(){const p=cur();if(!S.sel.length)return alert('Select tooth or Full mouth first');const pr=$('#proc').value;if(!pr)return alert('Select a procedure');
 p.treatments.push({id:uid(),date:today(),teeth:[...S.sel],proc:pr,fee:+$('#fee').value||0,status:$('#st').value,notes:$('#tn').value,by:S.user});save();S.sel=[];render()}
function flip(id){const x=cur().treatments.find(t=>t.id===id);x.status=x.status==='done'?'planned':'done';save();render()}
function del(k,id){if(!confirm('Delete this entry?'))return;const p=cur();p[k]=p[k].filter(x=>x.id!==id);save();render()}
function addPay(){const a=+$('#pa').value;if(!a)return alert('Enter amount');cur().payments.push({id:uid(),date:today(),amount:a,note:$('#pn').value,by:S.user});save();render()}
function saveF(){cur().followUp={date:$('#fd').value,note:$('#fn').value};save();render()}
async function upImg(){const fs=[...$('#ifile').files];if(!fs.length)return alert('Choose image(s)');const p=cur();
 for(const f of fs){const id=uid();await imgPut(id,await shrink(f));p.images.push({id,cat:$('#ic').value,note:$('#inote').value,date:today(),teeth:[...S.sel],by:S.user})}
 save();render()}
async function delImg(id){if(!confirm('Delete image?'))return;const p=cur();p.images=p.images.filter(i=>i.id!==id);await imgDel(id);save();render()}
async function view(id){const o=document.createElement('div');o.className='ov';o.onclick=()=>o.remove();o.innerHTML=`<img src="${await imgGet(id)}" alt="">`;document.body.append(o)}
async function backup(){const img={};for(const p of db.patients)for(const i of p.images)img[i.id]=await imgGet(i.id);
 const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify({db,img})],{type:'application/json'}));a.download='dental-os-backup-'+today()+'.json';a.click()}
async function restore(f){if(!f||!confirm('This replaces all current data. Continue?'))return;const d=JSON.parse(await f.text());db=d.db;for(const k in d.img)await imgPut(k,d.img[k]);save();go('list')}
render();
