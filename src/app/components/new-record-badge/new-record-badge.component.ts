import { Component, CUSTOM_ELEMENTS_SCHEMA, computed, input } from '@angular/core';
import { ICONS } from '../../constants/icons';
import { SoloLeaderboardMode, SoloScoreResult } from '../../models/leaderboard.model';
import { formatLeaderboardScore } from '../../utils/leaderboard-utils';

/** Badge « Nouveau record » des écrans de fin solo, affiché quand la partie bat le record du joueur. */
@Component({
  selector: 'app-new-record-badge',
  standalone: true,
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  styles: [`
    @keyframes recordPop {
      0%   { transform: scale(0.4) rotate(-6deg); opacity: 0; }
      60%  { transform: scale(1.12) rotate(2deg); opacity: 1; }
      100% { transform: scale(1) rotate(0); }
    }
    @keyframes recordShine {
      0%, 60% { transform: translateX(-120%); }
      100%    { transform: translateX(220%); }
    }
    .record-pop { animation: recordPop 0.55s cubic-bezier(0.34, 1.56, 0.64, 1) both; }
    .record-shine { animation: recordShine 2.4s ease-in-out 0.6s infinite; }
  `],
  template: `
    @if (result()?.is_record) {
      <div class="record-pop relative inline-flex items-center gap-2 overflow-hidden rounded-full border border-yellow-300/50 bg-gradient-to-r from-yellow-500/25 via-amber-400/20 to-orange-500/25 px-4 py-1.5 shadow-[0_0_24px_rgba(250,204,21,0.25)]">
        <span class="record-shine pointer-events-none absolute inset-y-0 left-0 w-1/3 bg-gradient-to-r from-transparent via-white/25 to-transparent"></span>
        <iconify-icon [icon]="ICONS.crown" class="relative text-lg text-yellow-300"></iconify-icon>
        <span class="relative text-sm font-black uppercase tracking-[0.12em] text-yellow-100">Nouveau record !</span>
        @if (previousBest(); as previous) {
          <span class="relative text-[11px] font-semibold text-yellow-200/60">ancien : {{ previous }}</span>
        }
      </div>
    }
  `,
})
export class NewRecordBadgeComponent {
  result = input<SoloScoreResult | null>(null);
  mode = input.required<SoloLeaderboardMode>();

  protected readonly ICONS = ICONS;

  protected readonly previousBest = computed(() => {
    const result = this.result();
    if (result?.previous_best === null || result?.previous_best === undefined) return null;
    return formatLeaderboardScore(this.mode(), result.settings_key, result.previous_best);
  });
}
