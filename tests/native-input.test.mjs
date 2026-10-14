import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {loadScopePlatform,loadFloatViewPolicy} from './support/FxArkRuntime.mjs';
const require=createRequire(import.meta.url);const {FxConfig}=require('../work/core/core/FxConfig.js');
loadScopePlatform();
const {FxFloatView,device}=loadFloatViewPolicy();
function surface(options={}) {
 const view=new FxFloatView();const config=new FxConfig({gestureMode:'android-2',...options});
 view.platform={getSnapshot:()=>({config}),canStartPan:()=>true};return {view,config};
}
const recognizer=tag=>({getTag:()=>tag,prevented:0,preventBegin(){this.prevented++;}});
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
