import { ArbitrationDemo } from './ArbitrationDemo';
import { RenderLayoutDemo } from './RenderLayoutDemo';
import { InputDemo } from './InputDemo';
import { ParityDemo } from './ParityDemo';
import { MultipleDemo } from './MultipleDemo';
import { ScopeDemo } from './ScopeDemo';
import { SystemDemo } from './SystemDemo';
import { AppDemo } from './AppDemo';
import { FxWindowHost } from 'floatingx';
@Entry({useSharedStorage:true})
@Component
struct Index {
  // Tab 切换不会销毁缓存内容；只挂载当前用例，让原有销毁逻辑释放它的浮窗。
  @State private activeTab: number = 0;
  onPageShow(): void {
    const host=this.getUIContext().getSharedLocalStorage()?.get<FxWindowHost>('fxWindowHost');
    if(host!==undefined) host.setPage('Home');
  }
  build() {
    Tabs() {
      TabContent() { if (this.activeTab === 0) { ArbitrationDemo() } }.tabBar('仲裁探针')
      TabContent() { if (this.activeTab === 1) { RenderLayoutDemo() } }.tabBar('绘制布局')
      TabContent() { if (this.activeTab === 2) { InputDemo() } }.tabBar('输入回归')
      TabContent() { if (this.activeTab === 3) { ParityDemo() } }.tabBar('等价验证')
      TabContent() { if (this.activeTab === 4) { ScopeDemo() } }.tabBar('局部')
      TabContent() { if (this.activeTab === 5) { AppDemo() } }.tabBar('应用')
      TabContent() { if (this.activeTab === 6) { SystemDemo() } }.tabBar('系统')
      TabContent() { if (this.activeTab === 7) { MultipleDemo() } }.tabBar('多实例')
    }.width('100%').height('100%')
      .onChange((index: number) => { this.activeTab = index; })
  }
}
