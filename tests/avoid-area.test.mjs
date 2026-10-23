import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {intersectAvoidAreas}=require('../work/core/geometry/FxAvoidArea.js');
test('avoid rectangles convert px once and do not subtract an already avoided overlay twice',()=>{
 const areas=[{left:0,top:0,width:800,height:48,edge:'top'},{left:0,top:1560,width:800,height:40,edge:'bottom'}];
 assert.deepEqual(intersectAvoidAreas({width:400,height:800},{x:0,y:0},2,areas),{left:0,top:24,right:0,bottom:20});
 assert.deepEqual(intersectAvoidAreas({width:400,height:756},{x:0,y:24},2,areas),{left:0,top:0,right:0,bottom:0});
 assert.deepEqual(intersectAvoidAreas({width:400,height:800},{x:0,y:0},2,[{left:0,top:0,width:40,height:1600,edge:'left'}]),{left:20,top:0,right:0,bottom:0});
 assert.deepEqual(intersectAvoidAreas({width:400,height:800},{x:0,y:0},2,[{left:0,top:400,width:40,height:20,edge:'left'}]),{left:20,top:0,right:0,bottom:0});
});
