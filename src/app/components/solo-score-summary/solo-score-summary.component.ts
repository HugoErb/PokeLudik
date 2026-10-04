import { Component, CUSTOM_ELEMENTS_SCHEMA, computed, input, output } from '@angular/core';
import { ICONS } from '../../constants/icons';
import { SoloScoreResult } from '../../models/leaderboard.model';

/** Bouton « Voir le classement » des écrans de fin solo, avec record et rangs de la partie. */
@Component({
  selector: 'app-solo-score-summary',
  standalone: true,
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  template: `
    <div class="group/action w-full">
      <button
        type="button"
        (click)="openLeaderboard.emit()"
        class="relative flex min-h-14 w-full transform-gpu will-change-transform items-center gap-3 overflow-hidden rounded-2xl border border-yellow-400/20 bg-yellow-500/[0.07] px-3.5 py-2.5 text-left shadow-[inset_0_1px_0_rgba(255,255,255,0.035)] transition-[transform,border-color,background-color] duration-300 ease-out group-hover/action:-translate-y-0.5 group-hover/action:border-yellow-300/35 group-hover/action:bg-yellow-500/[0.12] active:translate-y-0"
      >
        <span class="pointer-events-none absolute -right-7 -top-8 h-20 w-20 rounded-full bg-yellow-400/10 blur-2xl transition-colors duration-300 group-hover/action:bg-yellow-300/20"></span>
        <span class="relative flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-yellow-300/15 bg-yellow-400/10 text-yellow-200">
          @if (submitting()) {
            <iconify-icon [icon]="ICONS.loading" class="animate-spin text-xl"></iconify-icon>
          } @else {
            <iconify-icon [icon]="ICONS.trophy" class="text-xl"></iconify-icon>
          }
        </span>
        <span class="relative min-w-0 flex-1">
          <span class="block text-[15px] font-black tracking-[0.01em] text-slate-100">Voir le classement</span>
          <span class="mt-0.5 block text-xs font-semibold" [class]="error() ? 'text-red-300/80' : 'text-yellow-200/60'">{{ subtitle() }}</span>
        </span>
      </button>
    </div>
  `,
})
export class SoloScoreSummaryComponent {
  result = input<SoloScoreResult | null>(null);
  submitting = input(false);
  error = input('');
  openLeaderboard = output<void>();

  protected readonly ICONS = ICONS;

  protected readonly subtitle = computed(() => {
    if (this.submitting()) return 'Enregistrement du score…';
    if (this.error()) return this.error();
    const result = this.result();
    if (!result) return 'Compare-toi aux autres dresseurs';
    const week = result.rank_week === result.rank_all_time ? '' : ` · #${result.rank_week} cette semaine`;
    return `Classé #${result.rank_all_time}${week}`;
  });
}
