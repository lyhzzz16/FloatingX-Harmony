import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { loadScopePlatform,ScopeContext,ScopeContent } from './support/FxArkRuntime.mjs';
const require=createRequire(import.meta.url);
const {FxConfig}=require('../work/core/core/FxConfig.js');
const {FxController}=require('../work/core/core/FxController.js');
const FxScopePlatform=loadScopePlatform();
const touch=(type,id,x,y,timeMs)=>({type,changedTouches:[{id,windowX:x,windowY:y}],timestamp:timeMs*1000000});
async function setup(options={},interactions={}) {
 const platform=new FxScopePlatform(interactions); const events=[];
 const config=new FxConfig({adsorb:false,...options});
 const controller=new FxController(platform,config,e=>events.push(e.type),{error() {}});
 const content=new ScopeContent(); const context=new ScopeContext(); platform.bindController(controller);
 platform.mountHost(context,content); platform.layoutHost({width:300,height:500});
 await controller.show(); return {platform,controller,events,context,content,config};
}
test('real scope adapter waits for measured host, remounts fresh nodes and retains hidden intent',async()=>{
 const p=new FxScopePlatform(); const c=new FxController(p,new FxConfig()); p.bindController(c);
 await c.show(); assert.equal(c.isShow(),false);
 const source=new ScopeContent(); const first=new ScopeContext(); p.mountHost(first,source);
 await c.show(); assert.equal(c.isShow(),false);
 p.layoutHost({width:300,height:500}); await c.show(); assert.equal(c.isShow(),true);
 await c.hide(); p.unmountHost(); await c.setHostVisible(false);
 p.mountHost(new ScopeContext(),source); p.layoutHost({width:300,height:500}); await c.setHostVisible(true);
 assert.equal(c.isShow(),false); assert.equal(source.mounts.length,2); assert.equal(source.disposals,1);
 await c.cancel(); assert.equal(source.disposals,2);
});
test('absolute touch frames preserve logical vp, save once after settlement and suppress dragged click',async()=>{
 let clicks=0; const s=await setup({position:{x:10,y:20}},{onClick:()=>clicks++});
 const saves=[];
 const p=new FxScopePlatform({onClick:()=>clicks++}); const c=new FxController(p,new FxConfig({position:{x:10,y:20},adsorb:false})); p.bindController(c);
 c.bindPositionStorage({namespace:'scope',key:'drag',storage:{async load(){},async save(k,v){saves.push(v);},async clear(){}}},()=>p.getGeometry());
 p.mountHost(new ScopeContext(),new ScopeContent()); p.layoutHost({width:300,height:500}); await c.show();
 p.handleTouch(touch(0,1,100,100,0)); p.handleTouch(touch(2,1,120,130,20));
 p.handleTouch(touch(2,1,140,150,40)); assert.deepEqual(p.getPosition(),{x:50,y:70}); assert.equal(saves.length,0);
 p.handleTouch(touch(1,1,140,150,60)); await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
 assert.equal(saves.length,1); assert.equal(clicks,0); assert.deepEqual(saves[0].position,{x:50,y:70});
 await c.cancel(); await s.controller.cancel();
});
test('manual drag interruption of settle animation cannot save its stale completion',async()=>{
 const p=new FxScopePlatform(); const c=new FxController(p,new FxConfig({adsorb:true,animation:{enabled:true,durationMs:300,curve:'ease'}}));
 p.bindController(c); const saves=[];
 c.bindPositionStorage({namespace:'scope',key:'cancel',storage:{async load(){},async save(k,v){saves.push(v);},async clear(){}}},()=>p.getGeometry());
 const context=new ScopeContext(); p.mountHost(context,new ScopeContent()); p.layoutHost({width:300,height:500});
 const showing=c.show(); for(let i=0;i<12;i++) await Promise.resolve(); context.finishes.shift()(); await showing;
 p.handleTouch(touch(0,1,0,0,0)); p.handleTouch(touch(2,1,50,50,50)); p.handleTouch(touch(1,1,50,50,70));
 p.handleTouch(touch(0,1,100,100,100)); for(let i=0;i<8;i++) await Promise.resolve();
 assert.equal(saves.length,0); context.finishes.shift()(); assert.equal(saves.length,0);
 p.unmountHost(); await c.cancel();
});
test('content resize clamps legal position and half-hide projection keeps logical full position',async()=>{
 const s=await setup({position:{x:250,y:400},halfHide:true,edgeAdsorb:'right'});
 assert.equal(s.platform.getSnapshot().projection.visibleSize.width,25);
 assert.equal(s.controller.getX(),250);
 s.platform.layoutContent({width:100,height:100}); assert.equal(s.controller.getX(),200);
 s.platform.layoutHost({width:150,height:200}); assert.equal(s.controller.getX(),50); assert.equal(s.controller.getY(),100);
 await s.controller.cancel();
});
test('hide interrupts real adapter animation and stale native finish cannot revive visibility',async()=>{
 const s=await setup(); s.config.animation.enabled=true; await s.controller.updateConfig(s.config);
 const moving=s.controller.move(100,100,true); for(let i=0;i<6;i++) await Promise.resolve();
 const hiding=s.controller.hide(); await moving; for(let i=0;i<12;i++) await Promise.resolve();
 assert.equal(s.context.finishes.length,2); s.context.finishes[0](); s.context.finishes[1]();
 await Promise.all([moving,hiding]); assert.equal(s.controller.isShow(),false); await s.controller.cancel();
});

test('unmount before queued initial show prevents create and keeps show intent',async()=>{
 const p=new FxScopePlatform(); const events=[]; const c=new FxController(p,new FxConfig(),e=>events.push(e.type),{error(){}}); p.bindController(c);
 const source=new ScopeContent(); p.mountHost(new ScopeContext(),source); p.layoutHost({width:300,height:500});
 const showing=c.show(); p.unmountHost(); await showing; assert.equal(c.isShow(),false); assert.equal(source.mounts.length,0);
 p.mountHost(new ScopeContext(),source); p.layoutHost({width:300,height:500}); await c.setHostVisible(true);
 assert.equal(c.isShow(),true); assert.deepEqual(events,['attach','show']); await c.cancel();
});

test('cancel before first create releases mounted host and prevents remount resurrection',async()=>{
 const p=new FxScopePlatform(); const c=new FxController(p,new FxConfig()); p.bindController(c);
 const source=new ScopeContent(); p.mountHost(new ScopeContext(),source); await c.cancel();
 p.mountHost(new ScopeContext(),source); assert.equal(p.isHostVisible(),false);
 assert.equal(p.getSnapshot().content,undefined);
});
test('final primary up coordinate is included in drag settlement',async()=>{
 const s=await setup({position:{x:10,y:20}});
 s.platform.handleTouch(touch(0,1,100,100,0)); s.platform.handleTouch(touch(2,1,120,120,20));
 s.platform.handleTouch(touch(1,1,160,170,40)); await Promise.resolve();
 assert.deepEqual(s.platform.getPosition(),{x:70,y:90}); await s.controller.cancel();
});


test('native content dispose failure still releases platform-owned host and snapshot references',async()=>{
 const p=new FxScopePlatform(); const c=new FxController(p,new FxConfig(),undefined,{error(){}}); p.bindController(c);
 p.mountHost(new ScopeContext(),{size:{width:50,height:50},create(){return {content:{},dispose(){throw new Error('native dispose');}};}});
 p.layoutHost({width:300,height:500}); await c.show(); await assert.rejects(c.cancel(),{code:'WINDOW_OPERATION_FAILED'});
 assert.equal(p.isHostVisible(),false); assert.equal(p.getSnapshot().content,undefined);
});

test('unmount captures native dispose error and releases source for remount',async()=>{
 const p=new FxScopePlatform(); const errors=[]; const c=new FxController(p,new FxConfig(),e=>{if(e.error)errors.push(e.error);},{error(){}});p.bindController(c);
 p.mountHost(new ScopeContext(),{size:{width:50,height:50},create(){return {content:{},dispose(){throw new Error('unmount dispose');}};}});
 p.layoutHost({width:300,height:500}); await c.show(); assert.doesNotThrow(()=>p.unmountHost());
 assert.equal(errors.length,1); p.mountHost(new ScopeContext(),new ScopeContent()); p.layoutHost({width:300,height:500});
 await c.setHostVisible(true); assert.equal(c.isShow(),true); await c.cancel();
});

test('replacement host during show animation receives a fresh show and consistent actual visibility',async()=>{
 const p=new FxScopePlatform(); const events=[]; const c=new FxController(p,new FxConfig({animation:{enabled:true,durationMs:300,curve:'ease'}}),e=>events.push(e.type),{error(){}}); p.bindController(c);
 const content=new ScopeContent(); const first=new ScopeContext(); p.mountHost(first,content); p.layoutHost({width:300,height:500});
 const showing=c.show(); for(let i=0;i<16;i++) await Promise.resolve(); assert.equal(first.finishes.length,1);
 p.unmountHost(); const replacement=new ScopeContext(); p.mountHost(replacement,content); p.layoutHost({width:300,height:500});
 for(let i=0;i<16;i++) await Promise.resolve();
 assert.equal(replacement.finishes.length,1,'replacement content needs its own show animation');
 assert.equal(c.isShow(),false,'old-host completion cannot commit visible');
 first.finishes[0](); replacement.finishes[0](); await showing; await c.setHostVisible(true);
 assert.equal(p.getSnapshot().visible,true); assert.equal(c.isShow(),true);
 assert.deepEqual(events,['attach','detach','attach','show']); await c.cancel();
});
test('detach interrupts pending hide with exactly one actual hidden transition',async()=>{
 const s=await setup(); s.config.animation.enabled=true; await s.controller.updateConfig(s.config);
 const hiding=s.controller.hide(); for(let i=0;i<12;i++) await Promise.resolve(); assert.equal(s.context.finishes.length,1);
 s.platform.unmountHost(); await hiding; s.context.finishes[0]();
 assert.deepEqual(s.events,['attach','show','config','hide','detach']);
 assert.equal(s.controller.isShow(),false); await s.controller.cancel();
});
test('failed native disposal still emits terminal actual cleanup lifecycle exactly once',async()=>{
 const p=new FxScopePlatform(); const events=[]; const c=new FxController(p,new FxConfig(),e=>events.push(e.type),{error(){}}); p.bindController(c);
 p.mountHost(new ScopeContext(),{size:{width:50,height:50},create(){return {content:{},dispose(){throw new Error('native dispose');}};}});
 p.layoutHost({width:300,height:500}); await c.show();
 await assert.rejects(c.cancel(),{code:'WINDOW_OPERATION_FAILED'}); await assert.rejects(c.cancel(),{code:'WINDOW_OPERATION_FAILED'});
 assert.equal(c.getState(),'destroyed'); assert.equal(c.isShow(),false);
 assert.deepEqual(events,['attach','show','hide','detach','destroy','error']);
});
test('native hide completion failure rolls back visible snapshot after fade',async()=>{
 const s=await setup();await assert.rejects(s.platform.hide(()=>{throw Error('native hide');}));
 assert.equal(s.platform.getSnapshot().visible,true);assert.equal(s.platform.getSnapshot().opacity,1);await s.controller.cancel();
});

test('clipped view area cannot replace measured full content and late size observer cannot revive a disposed mount',async()=>{
 const p=new FxScopePlatform();const source=new ScopeContent();let full={width:50,height:50};let listener;
 source.create=()=>({content:{},measure:()=>full,observeSize:fn=>{listener=fn;},dispose(){}});
 const context=new ScopeContext();p.mountHost(context,source);p.layoutHost({width:300,height:300});await p.create();
 p.layoutContent({width:25,height:50});assert.deepEqual(p.getSnapshot().size,{width:50,height:50});
 full={width:80,height:60};listener(full);assert.deepEqual(p.getSnapshot().size,full);
 await p.destroy();listener({width:99,height:99});assert.deepEqual(p.getSnapshot().size,{width:80,height:60});assert.equal(p.getSnapshot().content,undefined);
});

for(const [edge,start,expected] of [
 ['right',{x:250,y:225},{x:450,y:125}],['left',{x:0,y:225},{x:0,y:125}],
 ['top',{x:125,y:0},{x:225,y:0}],['bottom',{x:125,y:450},{x:225,y:250}]
]) test('live scope resize preserves '+edge+' edge, other axis ratio and half hide',async()=>{
 const s=await setup({adsorb:true,edgeAdsorb:edge,halfHide:true,position:start});
 s.platform.layoutHost({width:500,height:300});assert.deepEqual(s.platform.getPosition(),expected);
 const slice=s.platform.getSnapshot().projection.visibleSize;assert.equal(edge==='left'||edge==='right'?slice.width:slice.height,25);
 s.platform.layoutHost({width:300,height:500});assert.deepEqual(s.platform.getPosition(),start);await s.controller.cancel();
});
test('live scope safe area change remaps using complete historical bounds',async()=>{
 const s=await setup({adsorb:true,edgeAdsorb:'right',halfHide:true,position:{x:250,y:225}});
 s.platform.layoutHost({width:300,height:500},{left:20,top:30,right:40,bottom:70});
 assert.deepEqual(s.platform.getPosition(),{x:210,y:205});assert.equal(s.platform.getSnapshot().projection.visibleSize.width,25);
 s.platform.layoutHost({width:300,height:500});assert.deepEqual(s.platform.getPosition(),{x:250,y:225});await s.controller.cancel();
});
for(const kind of ['click','longPress','drag'])for(const asyncFailure of [false,true])test(kind+' '+(asyncFailure?'async':'sync')+' callback failure is sanitized and cleanup continues',async()=>{
 const secret='business payload sentinel';const logs=[];const events=[];
 const fail=()=>{if(asyncFailure)return Promise.reject(Error(secret));throw Error(secret);};
 const p=new FxScopePlatform({['on'+kind[0].toUpperCase()+kind.slice(1)]:fail});
 const c=new FxController(p,new FxConfig({adsorb:false}),e=>events.push(e),{error:e=>logs.push(e)});p.bindController(c);
 p.mountHost(new ScopeContext(),new ScopeContent());p.layoutHost({width:300,height:500});await c.show();
 p.handleTouch(touch(0,1,0,0,0));
 if(kind==='longPress')p.handleTouch(touch(2,1,0,0,501));
 if(kind==='drag')p.handleTouch(touch(2,1,30,30,20));
 p.handleTouch(touch(1,1,kind==='drag'?30:0,kind==='drag'?30:0,kind==='longPress'?520:40));
 await new Promise(r=>setImmediate(r));await c.cancel();
 assert.equal(logs.length,1);assert.equal(logs[0].code,'EVENT_CALLBACK_FAILED');assert.equal(JSON.stringify(logs).includes(secret),false);
 assert.deepEqual(events.filter(e=>e.error),[]);assert.equal(c.getState(),'destroyed');assert.equal(p.getSnapshot().content,undefined);
});

test('primary lifecycle observes stationary up and system cancel, ignores secondary up and hidden input',async()=>{
 const seen=[];const s=await setup({}, {onTouch:e=>seen.push(e)});
 s.platform.handleTouch(touch(0,7,100,100,0));s.platform.handleTouch(touch(0,9,200,200,10));
 s.platform.handleTouch(touch(1,9,200,200,20));s.platform.handleTouch(touch(1,7,100,100,30));
 assert.deepEqual(seen.map(e=>[e.phase,e.pointerId]),[['down',7],['up',7]]);
 assert.equal(seen[1].dragged,false);assert.deepEqual(seen[1].delta,{x:0,y:0});
 s.platform.handleTouch(touch(0,7,100,100,40));s.platform.handleTouch(touch(3,7,100,100,50));
 assert.equal(seen.at(-1).cancelReason,'system');
 await s.controller.hide();s.platform.handleTouch(touch(0,7,0,0,60));assert.equal(seen.length,4);await s.controller.cancel();
});
test('hide cancels active pointer synchronously once and never runs a release decision',async()=>{
 const events=[];let releases=0;const s=await setup({}, {onTouch:e=>events.push(e),onRelease:()=>{releases++;return 'default';}});
 s.platform.handleTouch(touch(0,1,100,100,0));const hiding=s.controller.hide();
 assert.equal(events.at(-1).cancelReason,'hidden');await hiding;await s.controller.cancel();
 assert.deepEqual(events.map(e=>e.phase),['down','cancel']);assert.equal(releases,0);
});
test('consumed release retains pre-settle location and allows reentrant move',async()=>{
 const s=await setup({adsorb:true},{onRelease:e=>{assert.equal(e.position.x,80);s.controller.move(40,60,false);return 'consumed';}});
 s.platform.handleTouch(touch(0,1,0,0,0));s.platform.handleTouch(touch(2,1,80,90,10));s.platform.handleTouch(touch(1,1,80,90,20));
 for(let i=0;i<12;i++)await Promise.resolve();assert.deepEqual(s.platform.getPosition(),{x:40,y:60});await s.controller.cancel();
});
test('release decision precedes click and consumed surface does not click',async()=>{
 const order=[];let consume=false;
 const s=await setup({}, {onTouch:e=>order.push(e.phase),onRelease:()=>{order.push('release');return consume?'consumed':'default';},onClick:()=>order.push('click')});
 s.platform.handleTouch(touch(0,1,0,0,0));s.platform.handleTouch(touch(1,1,0,0,10));assert.deepEqual(order,['down','up','release','click']);
 consume=true;order.length=0;s.platform.handleTouch(touch(0,1,0,0,400));s.platform.handleTouch(touch(1,1,0,0,410));assert.deepEqual(order,['down','up','release']);await s.controller.cancel();
});
test('down callback can cancel without late long press or unmatched up',async()=>{
 const events=[];const s=await setup({}, {onTouch:e=>{events.push(e.phase);if(e.phase==='down')s.controller.cancel();}});
 s.platform.handleTouch(touch(0,1,0,0,0));await s.controller.cancel();s.platform.handleTouch(touch(1,1,0,0,600));
 assert.deepEqual(events,['down','cancel']);
});
test('android bounds display real clipped drag and disabled adsorption does not force a release clamp',async()=>{
 const releases=[];const s=await setup({boundaryMode:'android-2',halfHide:true,halfHideRatio:.5,margin:{left:10,right:10,top:20,bottom:20},position:{x:0,y:20}}, {onRelease:e=>{releases.push(e);return 'default';}});
 s.platform.handleTouch(touch(0,1,100,100,0));s.platform.handleTouch(touch(2,1,0,70,10));
 assert.deepEqual(s.platform.getPosition(),{x:-25,y:0});
 assert.deepEqual(s.platform.getSnapshot().projection,{position:{x:0,y:0},visibleSize:{width:25,height:50},contentOffset:{x:-25,y:0}});
 s.platform.handleTouch(touch(1,1,0,70,20));await Promise.resolve();assert.equal(releases[0].position.x,-25);assert.equal(s.platform.getPosition().y,0);await s.controller.cancel();
});
test('geometry snapshots are detached and declared size is not measured layout',async()=>{
 const s=await setup();const g=s.controller.getGeometrySnapshot();assert.equal(g.measured,false);g.viewport.size.width=1;assert.equal(s.platform.getGeometry().viewport.size.width,300);
 const layouts=[];const unsubscribe=s.controller.subscribeLayout(g=>layouts.push(g));s.platform.layoutContent({width:80,height:60},true);
 assert.equal(layouts.at(-1).measured,true);assert.deepEqual(layouts.at(-1).content,{width:80,height:60});assert.ok(layouts.at(-1).instanceId>0);
 unsubscribe();const count=layouts.length;s.platform.layoutContent({width:90,height:60},true);assert.equal(layouts.length,count);await s.controller.cancel();assert.equal(s.controller.getGeometrySnapshot(),undefined);
});

test('consuming release bypasses default position persistence and settles neither up nor cancel',async()=>{
 for(const end of [1,3]) {
  const saves=[];const p=new FxScopePlatform({onRelease:()=> 'consumed'});const c=new FxController(p,new FxConfig({adsorb:true}));p.bindController(c);
  c.bindPositionStorage({namespace:'parity',key:String(end),storage:{async load(){},async save(k,v){saves.push(v);},async clear(){}}},()=>p.getGeometry());
  p.mountHost(new ScopeContext(),new ScopeContent());p.layoutHost({width:300,height:500});await c.show();
  p.handleTouch(touch(0,1,0,0,0));p.handleTouch(touch(2,1,80,60,10));p.handleTouch(touch(end,1,80,60,20));
  for(let i=0;i<15;i++)await Promise.resolve();assert.equal(saves.length,0);assert.equal(p.getPosition().x,80);await c.cancel();
 }
});
test('cancel callback reentering cancel joins the same resource release',async()=>{
 let nested;const s=await setup({}, {onTouch:e=>{if(e.phase==='cancel')nested=s.controller.cancel();}});
 s.platform.handleTouch(touch(0,1,0,0,0));const cancel=s.controller.cancel();assert.equal(cancel,nested);await cancel;assert.equal(s.content.disposals,1);
});
test('observer cannot mutate the release decision snapshot',async()=>{
 const s=await setup({}, {onTouch:e=>{e.position.x=999;},onRelease:e=>{assert.equal(e.position.x,20);return 'default';}});
 s.platform.handleTouch(touch(0,1,0,0,0));s.platform.handleTouch(touch(2,1,20,20,10));s.platform.handleTouch(touch(1,1,20,20,20));await s.controller.cancel();
});

test('Android resize retains primary pointer, absolute origin and one release',async()=>{
 const seen=[];let releases=0;const s=await setup({boundaryMode:'android-2',gestureMode:'android-2',touchSlopVp:8,position:{x:20,y:80}},{onTouch:e=>seen.push(e),onRelease:()=>{releases++;return 'default';}});
 s.platform.handleTouch(touch(0,1,100,100,0));s.platform.handleTouch(touch(2,1,120,130,50));s.platform.layoutContent({width:90,height:60},true);
 s.platform.handleTouch(touch(2,1,125,135,800));assert.deepEqual(s.platform.getPosition(),{x:45,y:115});
 s.platform.handleTouch(touch(1,2,500,500,900));s.platform.handleTouch(touch(1,1,125,135,900));
 assert.equal(releases,1);assert.deepEqual(seen.map(e=>e.phase),['down','move','move','up']);assert.deepEqual(seen.at(-1).delta,{x:25,y:35});await s.controller.cancel();
});
test('native child tap is observer-only; background tap and owned pan may release',async()=>{
 let releases=0,clicks=0;const s=await setup({boundaryMode:'android-2',gestureMode:'android-2',touchSlopVp:8},{onRelease:()=>{releases++;return 'default';},onClick:()=>clicks++});
 s.platform.handleTouch(touch(0,1,10,10,0),true);s.platform.handleTouch(touch(1,1,10,10,50),true);await Promise.resolve();assert.equal(releases,0);assert.equal(clicks,0);
 s.platform.handleTouch(touch(0,1,10,10,400),true);s.platform.completeSurfaceTap();s.platform.handleTouch(touch(1,1,10,10,450),true);await Promise.resolve();assert.equal(releases,1);assert.equal(clicks,1);
 s.platform.handleTouch(touch(0,1,10,10,800),true);s.platform.handleTouch(touch(2,1,18,10,850),true);assert.equal(s.platform.getPosition().x,0);
 s.platform.handlePan({fingerList:[{id:1,globalX:18,globalY:10}],timestamp:850000000});assert.equal(s.platform.getPosition().x,8);
 s.platform.handleTouch(touch(1,1,18,10,900),true);assert.equal(releases,2);assert.equal(clicks,1);await s.controller.cancel();
});
test('first measured Android gravity corrects declared size unless a caller already placed the view',async()=>{
 const s=await setup({boundaryMode:'android-2',gravity:'top-right',halfHide:true});
 s.platform.layoutContent({width:100,height:60},true);assert.equal(s.platform.getPosition().x,200);await s.controller.cancel();
 const moved=await setup({boundaryMode:'android-2',gravity:'top-right',halfHide:true});await moved.controller.move(75,100);
 moved.platform.layoutContent({width:100,height:60},true);assert.deepEqual(moved.platform.getPosition(),{x:75,y:100});await moved.controller.cancel();
});
test('Android parent long callback requires click listener and local Scope rejects unowned safe areas',async()=>{
 let longs=0;const s=await setup({gestureMode:'android-2',touchSlopVp:8},{onLongPress:()=>longs++});
 s.platform.handleTouch(touch(TouchType.Down,1,50,50,0));s.platform.handleTouch(touch(TouchType.Up,1,50,50,600));
 assert.equal(longs,0);s.platform.interactions.onClick=()=>{};
 s.platform.handleTouch(touch(TouchType.Down,1,50,50,1000));s.platform.handleTouch(touch(TouchType.Up,1,50,50,1600));assert.equal(longs,1);
 await assert.rejects(s.controller.updateConfig(new FxConfig({safeAreaPolicy:'avoid-system'})),{code:'CAPABILITY_UNSUPPORTED'});
 await s.controller.cancel();
});
