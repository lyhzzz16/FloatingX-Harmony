import { FxPoint, FxSize, FxInsets } from '../core/FxTypes';
export interface FxAvoidRect { left: number; top: number; width: number; height: number; edge: 'left' | 'top' | 'right' | 'bottom'; }
/** Rectangles use window px; origin is the measured overlay's window vp, avoiding double subtraction. */
export function intersectAvoidAreas(size: FxSize, origin: FxPoint, density: number, areas: FxAvoidRect[]): FxInsets {
  const result: FxInsets={left:0,top:0,right:0,bottom:0};
  for(let i=0;i<areas.length;i++) {
    const rect=areas[i];if(rect.width<=0 || rect.height<=0)continue;
    const l=rect.left/density-origin.x,t=rect.top/density-origin.y;
    const r=l+rect.width/density,b=t+rect.height/density;
    if(r<=0 || b<=0 || l>=size.width || t>=size.height)continue;
    // Keep the system's edge classification; a short side cutout is not a top strip.
    if(rect.edge==='top' && t<=0)result.top=Math.max(result.top,Math.min(size.height,b));
    if(rect.edge==='bottom' && b>=size.height)result.bottom=Math.max(result.bottom,Math.min(size.height,size.height-t));
    if(rect.edge==='left' && l<=0)result.left=Math.max(result.left,Math.min(size.width,r));
    if(rect.edge==='right' && r>=size.width)result.right=Math.max(result.right,Math.min(size.width,size.width-l));
  }
  return result;
}
