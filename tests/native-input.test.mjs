import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {loadScopePlatform,loadFloatViewPolicy} from './support/FxArkRuntime.mjs';
const require=createRequire(import.meta.url);const {FxConfig}=require('../work/core/core/FxConfig.js');
loadScopePlatform();
const {FxFloatView,device}=loadFloatViewPolicy();
function surface(options={}) {
 const view=new FxFloatView();const config=new FxConfig({gestureMode:'android-2',...options});
 view.platform={getSnapshot:()=>({config,visible:true}),canStartPan:()=>true,isInterceptDisallowed:()=>false,handlePan(){}};return {view,config};
}
const recognizer=(tag,state=GestureRecognizerState.DETECTING)=>({getTag:()=>tag,getState:()=>state,prevented:0,preventBegin(){this.prevented++;}});
const touchRecognizer=id=>({getEventTargetInfo:()=>({getId:()=>id}),cancelled:0,cancelTouch(){this.cancelled++;}});
test('content-owned parent Tap rejects before competing child cancellation; normal Tap remains available',()=>{
 const {view,config}=surface({contentOwnsTap:true});const child=recognizer('child');const touch=touchRecognizer('child');
 assert.equal(view.judge({},recognizer(view.surfaceId+'tap'),[child],[touch]),GestureJudgeResult.REJECT);
 assert.equal(view.judge({},child,[],[touch]),GestureJudgeResult.CONTINUE);
 assert.equal(child.prevented,0);assert.equal(touch.cancelled,0);
 config.contentOwnsTap=false;assert.equal(view.judge({},recognizer(view.surfaceId+'tap'),[child],[touch]),GestureJudgeResult.CONTINUE);
});
test('only winning parent Pan cancels children, preserves its own terminal receiver and rejects other axis',()=>{
 const {view}=surface({contentOwnsTap:true});const x=recognizer(view.surfaceId+'x'),y=recognizer(view.surfaceId+'y'),child=recognizer('child');
 const own=touchRecognizer(view.surfaceId),content=touchRecognizer('child');
 view.platform.canStartPan=()=>false;
 assert.equal(view.judge({},x,[y,child],[own,content]),GestureJudgeResult.REJECT);assert.equal(content.cancelled,0);
 view.platform.canStartPan=()=>true;
 assert.equal(view.judge({},x,[y,child],[own,content]),GestureJudgeResult.CONTINUE);
 assert.equal(child.prevented,1);assert.equal(y.prevented,0);assert.equal(content.cancelled,1);assert.equal(own.cancelled,0);
 assert.equal(view.judge({},y,[x,child],[own,content]),GestureJudgeResult.REJECT);assert.equal(content.cancelled,1);
});
test('native root isolates hierarchy, preserves DisplayOnly and legacy modes, and guards API20 enum access',()=>{
 const {view,config}=surface();assert.equal(view.hitTestMode(0),HitTestMode.BLOCK_HIERARCHY);
 config.displayMode='display-only';assert.equal(view.hitTestMode(0),HitTestMode.None);
 config.displayMode='normal';config.gestureMode='legacy';assert.equal(view.hitTestMode(0),HitTestMode.Transparent);
 config.gestureMode='android-2';device.sdkApiVersion=19;
 const value=HitTestMode.BLOCK_HIERARCHY;
 Object.defineProperty(HitTestMode,'BLOCK_HIERARCHY',{configurable:true,get(){throw Error('API20 enum accessed');}});
 try{assert.equal(view.hitTestMode(0),HitTestMode.Default);assert.equal(view.judge({},recognizer(view.surfaceId+'tap'),[]),GestureJudgeResult.REJECT);}
 finally{Object.defineProperty(HitTestMode,'BLOCK_HIERARCHY',{configurable:true,writable:true,value});device.sdkApiVersion=26;}
});

test('hidden and prepared surfaces reject recognition without canceling children or blocking lower content',()=>{
 for(const gestureMode of ['android-2','legacy'])for(const displayMode of ['normal','click-only','display-only']) {
  const {view,config}=surface({gestureMode,displayMode});
  let visible=true;view.platform.getSnapshot=()=>({config,visible});
  const child=recognizer('child'),touch=touchRecognizer('child');
  let starts=0;view.platform.canStartPan=()=>{starts++;return true;};
  for(const prepared of [true,false]) {
   config.layoutOnly=prepared;visible=prepared;
   assert.equal(view.hitTestMode(0),HitTestMode.None);
   for(const tag of [view.surfaceId+'tap',view.surfaceId+'x',view.surfaceId+'y','child'])
    assert.equal(view.judge({},recognizer(tag),[child],[touch]),GestureJudgeResult.REJECT);
  }
  assert.equal(starts,0);assert.equal(child.prevented,0);assert.equal(touch.cancelled,0);
  visible=true;config.layoutOnly=false;
  assert.equal(view.hitTestMode(0),displayMode==='display-only'?HitTestMode.None:gestureMode==='legacy'?HitTestMode.Transparent:HitTestMode.BLOCK_HIERARCHY);
 }
});

test('successful native child retains terminal delivery; only undecided recognizers are prevented',()=>{
 const {view}=surface();const successful=recognizer('long',GestureRecognizerState.SUCCESSFUL),failed=recognizer('failed',GestureRecognizerState.FAILED),pending=recognizer('tap');
 view.judge({},recognizer(view.surfaceId+'x'),[successful,failed,pending]);
 assert.equal(successful.prevented,0);assert.equal(failed.prevented,0);assert.equal(pending.prevented,1);
});
test('disallow does not cancel child or reject parallel pan; revocation can take over without a synthetic DOWN',()=>{
 const {view}=surface();let disallowed=true;let starts=[];
 view.platform.isInterceptDisallowed=()=>disallowed;view.platform.handlePan=(_e,starting)=>starts.push(starting);
 const child=recognizer('child'),touch=touchRecognizer('child');
 assert.equal(view.judge({},recognizer(view.surfaceId+'x'),[child],[touch]),GestureJudgeResult.CONTINUE);
 view.pan({},true);view.pan({});assert.deepEqual(starts,[]);assert.equal(child.prevented,0);assert.equal(touch.cancelled,0);
 disallowed=false;view.pan({});view.pan({});
 assert.deepEqual(starts,[true,false]);assert.equal(child.prevented,1);assert.equal(touch.cancelled,1);
});
