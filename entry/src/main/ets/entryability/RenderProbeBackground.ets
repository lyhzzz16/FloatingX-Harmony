/** One-shot Demo trigger: create the probe after the main window enters background. */
export class RenderProbeBackground {
  static pending?: () => void;
  static run(): void {const pending=RenderProbeBackground.pending;RenderProbeBackground.pending=undefined;pending?.();}
}
