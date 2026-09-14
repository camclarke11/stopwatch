const vm=require('vm'),fs=require('fs'),assert=require('assert');
const source=fs.readFileSync(require('path').join(__dirname,'../Source/pixel-cat.js'),'utf8');
async function simulate({width=1280,height=720,reduced=false}={}) {
  let now=0,serial=0,cat,bubble,running=true,stopwatch=true,hidden=false,modal=false,randomIndex=0;
  const pending=new Map(),events={},observers=[];
  const context2d={clearRect(){},save(){},restore(){},translate(){},scale(){},fillRect(){},measureText(glyph){return {actualBoundingBoxAscent:height*(glyph===':'?.22:.28)}}};
  const element=()=>({style:{setProperty(){}},classList:{toggle(){}},dataset:{},listeners:{},captured:null,setAttribute(name,value){this[name]=value},getContext:()=>context2d,
    addEventListener(name,fn){this.listeners[name]=fn},
    setPointerCapture(id){this.captured=id},hasPointerCapture(id){return this.captured===id},releasePointerCapture(){this.captured=null},
    getBoundingClientRect(){const [left,top]=(this.style.transform||'translate(0px,0px)').match(/-?\d+/g).map(Number);return {left,top,width:parseFloat(this.style.width),height:parseFloat(this.style.height)}}});
  const baseline=element();baseline.getBoundingClientRect=()=>({top:height*.65});
  const clock={offsetWidth:width*.8,append(){},getBoundingClientRect:()=>({width:width*.8}),querySelectorAll:selector=>[{left:.1,width:.18,text:'5'},{left:.3,width:.18,text:'1'},...(selector.includes('.sep')?[{left:.48,width:.04,text:':'},{left:0,width:0,text:':'}]:[]),{left:.6,width:.18,text:'0'},{left:.8,width:.18,text:'0'}].map(item=>({textContent:item.text,getBoundingClientRect:()=>({left:width*item.left,width:width*item.width})}))};
  const media={matches:reduced,addEventListener(name,cb){events.media=cb}};
  const body={append(node){if(node.className==='pixel-cat')cat=node;else bubble=node},classList:{contains(){return false}}};
  const settings={get open(){return modal}};
  const doc={body,head:{append(){}},get hidden(){return hidden},fonts:{ready:Promise.resolve()},createElement:tag=>tag==='span'?baseline:element(),querySelector:s=>s==='.time'?clock:s==='#pomodoro-settings'?settings:{dataset:{get icon(){return running?'pause':'play'}},getAttribute(){return String(stopwatch)}},addEventListener:(name,fn)=>events[name]=fn};
  const sandbox={document:doc,innerWidth:width,innerHeight:height,matchMedia:()=>media,getComputedStyle:()=>({fontWeight:'700',fontSize:'280px',fontFamily:'DynaPuff'}),performance:{now:()=>now},Math:Object.assign(Object.create(Math),{random:()=>[.6,.8,.6,.8,.6][randomIndex++%5]}),ResizeObserver:class{constructor(fn){observers.push(fn)}observe(){}},MutationObserver:class{constructor(fn){observers.push(fn)}observe(){}},requestAnimationFrame:fn=>{let id=++serial;pending.set(id,{fn,t:now+16});return id},cancelAnimationFrame:id=>pending.delete(id),setTimeout:(fn,ms)=>{let id=++serial;pending.set(id,{fn,t:now+ms});return id},clearTimeout:id=>pending.delete(id),window:{addEventListener:(name,fn)=>events[name]=fn}};
  vm.runInNewContext(source,sandbox);await Promise.resolve();
  const poses=new Set(),positions=new Set();let samples=0;
  function advance(ms) {
    const end=now+ms;
    while(pending.size) {
      const [id,item]=[...pending].sort((a,b)=>a[1].t-b[1].t)[0];
      if(item.t>end)break;
      now=item.t;pending.delete(id);item.fn(now);
      if(cat.style.transform){
        const [x,y]=cat.style.transform.match(/-?\d+/g).map(Number),w=parseFloat(cat.style.width),h=parseFloat(cat.style.height);
        assert(x>=0&&y>=0&&x+w<=sandbox.innerWidth&&y+h<=sandbox.innerHeight,'Cat stays in viewport');
        poses.add(cat.dataset.pose);positions.add(cat.style.transform);samples++;
      }
    }
    now=end;
  }
  advance(50);
  events['cat:focus-nudge']();advance(50);assert(!bubble.hidden,'Nudge appears for running stopwatch');
  const first=bubble.textContent;
  advance(4700);assert(bubble.hidden,'Nudge disappears');
  events['cat:focus-nudge']();assert(bubble.hidden,'Repeated motion has cooldown');
  advance(46000);events['cat:focus-nudge']();assert(!bubble.hidden&&bubble.textContent!==first,'Next nudge varies');
  events.blur();assert(bubble.hidden,'Blur dismisses bubble');
  advance(46000);running=false;events['cat:focus-nudge']();assert(bubble.hidden,'Paused timer does not nudge');
  running=true;stopwatch=false;events['cat:focus-nudge']();assert(bubble.hidden,'Other modes do not nudge');
  stopwatch=true;
  advance(125000);
  if(reduced){assert.deepEqual([...poses],['sleep']);assert.equal(positions.size,1)}
  else {assert(poses.has('jump')&&poses.has('sleep')&&poses.has('sit'),'Hops, rests and naps all occur');assert(positions.size>10)}
  function pointer(type,x,y,id=1,button=0) {cat.listeners[type]({clientX:x,clientY:y,pointerId:id,button,isPrimary:true,preventDefault(){},stopPropagation(){}})}
  const rect=cat.getBoundingClientRect();
  pointer('pointerdown',rect.left+rect.width/2,rect.top+rect.height/2);
  assert.equal(cat.dataset.pose,'held');assert.equal(cat.captured,1);
  pointer('pointermove',width*.75,height*.75);
  const heldAt=cat.style.transform;
  advance(5000);assert.equal(cat.style.transform,heldAt,'A held cat does not wander');
  pointer('pointerup',width*.1,height*.2,2);assert.equal(cat.captured,1,'Other pointer cannot drop cat');
  pointer('pointerup',width*.75,height*.75);
  advance(2000);
  assert.equal(cat.captured,null);assert(!cat.dataset.dragging);
  let landed=cat.getBoundingClientRect();
  assert(landed.top+landed.height>=height-14,'Drop below digits lands at floor');
  const resting=cat.style.transform;advance(4000);assert.equal(cat.style.transform,resting,'Stays where placed for a while');
  pointer('pointerdown',landed.left+landed.width/2,landed.top+landed.height/2);
  pointer('pointermove',width*.69,8);
  pointer('pointerup',width*.69,8);
  advance(2000);landed=cat.getBoundingClientRect();
  assert(landed.top+landed.height<height*.75,'Drop above a digit catches the clock');
  pointer('pointerdown',landed.left+landed.width/2,landed.top+landed.height/2);
  pointer('pointermove',width*.5,8);
  pointer('pointerup',width*.5,8);
  advance(2000);landed=cat.getBoundingClientRect();
  assert(Math.abs(landed.left+landed.width/2-width*.5)<2,'Cat can land on colon center');
  assert(Math.abs(landed.top+landed.height*(26/28)-height*.43)<2,'Colon uses its own visible top, not digit height');
  pointer('pointerdown',landed.left+landed.width/2,landed.top+landed.height/2);
  pointer('pointermove',-200,height+500);advance(100);
  pointer('pointercancel',-200,height+500);advance(2000);
  assert.equal(cat.captured,null);assert(!cat.dataset.dragging,'Cancelled drag recovers');
  modal=true;observers.forEach(fn=>fn());advance(2500);const whenModal=cat.style.transform;advance(4000);assert.equal(cat.style.transform,whenModal,'Settings freeze motion');
  hidden=true;events.visibilitychange();advance(1000);assert.equal(pending.size,0,'No work scheduled in a hidden document');
  hidden=false;events.visibilitychange();modal=false;advance(1000);assert(pending.size>0,'Resumes after visibility change');
  sandbox.innerWidth=320;sandbox.innerHeight=220;events.resize();advance(2000);
  console.log(`Passed pixel cat: ${width}x${height}, reduced motion ${reduced}; ${samples} samples.`);
}
(async()=>{await simulate();await simulate({width:320,height:220});await simulate({reduced:true})})().catch(error=>{console.error(error);process.exit(1)});
