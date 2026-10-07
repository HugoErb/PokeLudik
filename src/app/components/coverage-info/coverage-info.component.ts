import { Component, CUSTOM_ELEMENTS_SCHEMA, computed, input, signal } from '@angular/core';
import { NgClass } from '@angular/common';
import { ICONS } from '../../constants/icons';
import { TYPE_COLORS } from '../../constants/type-chart';
import { Pokemon } from '../../models/pokemon.model';
import { CoverageEntry, explainDuoCoverage } from '../../utils/draft-utils';
import { PokemonTypeIconComponent } from '../pokemon-type-icon/pokemon-type-icon.component';

let nextId = 0;

/** Bouton « i » qui détaille le calcul de la note de couverture de types d'une équipe. */
@Component({
  selector: 'app-coverage-info',
  standalone: true,
  imports: [NgClass, PokemonTypeIconComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  styles: `:host { display: inline-flex; }`,
  template: `
    <button
      type="button"
      class="inline-flex h-5 w-5 items-center justify-center rounded-full text-slate-400 transition-colors hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-yellow-400"
      [attr.aria-label]="'Détail du calcul de couverture : ' + label()"
      [attr.popovertarget]="popoverId">
      <iconify-icon [icon]="ICONS.help" class="text-base"></iconify-icon>
    </button>

    <!-- Popover natif : couche supérieure, fermeture au clic dehors et avec Échap. -->
    <div
      popover
      [id]="popoverId"
      role="dialog"
      [attr.aria-label]="'Couverture de types : ' + label()"
      class="m-auto max-h-[75vh] w-[calc(100%-2rem)] max-w-md overflow-hidden rounded-2xl border border-slate-600 bg-slate-900 p-0 text-left shadow-2xl backdrop:bg-slate-950/50"
      (toggle)="open.set($any($event).newState === 'open')">
      @if (open()) {
      <div class="flex max-h-[75vh] flex-col">
        <div class="flex items-center justify-between gap-2 border-b border-slate-700/60 px-4 py-3">
          <p class="text-sm font-black text-white">Couverture de types · {{ label() }}</p>
          <button type="button" class="text-slate-400 hover:text-white" aria-label="Fermer" [attr.popovertarget]="popoverId" popovertargetaction="hide">
            <iconify-icon [icon]="ICONS.close" class="text-lg"></iconify-icon>
          </button>
        </div>

        @if (detail().joker; as joker) {
          <p class="px-4 py-4 text-sm text-slate-300">
            <b class="text-yellow-300">{{ joker.name }}</b> change de type à volonté : couverture maximale d'office
            (<b class="text-white">10/10</b>), c'est le joker.
          </p>
        } @else {
          <ul class="min-h-0 flex-1 space-y-2 overflow-y-auto px-4 py-3">
            @for (entry of detail().entries; track $index) {
              <li class="rounded-xl bg-slate-800/70 px-3 py-2 text-xs text-slate-300">
                <div class="mb-1 flex items-center gap-1.5 font-bold text-white">
                  <span class="truncate">{{ entry.opponent.name }}</span>
                  @for (type of entry.opponent.types; track type) {
                    <span class="inline-flex items-center gap-0.5 rounded px-1 py-0.5 text-[9px] font-bold text-white" [ngClass]="typeColor(type)"><app-pokemon-type-icon [type]="type" size="compact" />{{ type }}</span>
                  }
                  <span class="ml-auto shrink-0 font-mono text-slate-400">{{ entryPoints(entry) }}</span>
                </div>
                @if (entry.isArceus) {
                  <p>Joker adverse : il change de type, impossible à exploiter et personne ne lui résiste (0 pt).</p>
                } @else {
                  <p>
                    <span class="text-slate-500">Attaque :</span>
                    @if (entry.attackPoints === 2) {
                      <b class="text-green-300">{{ entry.attacker?.name }}</b>
                      @if (entry.attackType; as attackType) {
                        <span class="inline-flex items-center gap-0.5 rounded px-1 py-0.5 text-[9px] font-bold text-white" [ngClass]="typeColor(attackType)"><app-pokemon-type-icon [type]="attackType" size="compact" />{{ attackType }}</span>
                      }
                      est fort contre lui : ×{{ formatMultiplier(entry.multiplier) }} → 2 pts
                    } @else if (entry.attackPoints === 1) {
                      aucun type super efficace, au mieux ×1 → 1 pt
                    } @else {
                      <span class="text-red-300">tous tes types sont résistés</span>
                      (au mieux ×{{ formatMultiplier(entry.multiplier) }}) → 0 pt
                    }
                  </p>
                  <p>
                    <span class="text-slate-500">Résistance :</span>
                    @if (entry.resistor) {
                      <b class="text-green-300">{{ entry.resistor.name }}</b> résiste à ses types → 1 pt
                    } @else {
                      personne ne résiste à tous ses types → 0 pt
                    }
                  </p>
                  <p>
                    <span class="text-slate-500">Faiblesses :</span>
                    @if (entry.weakMembers.length) {
                      menace <b class="text-red-300">{{ entry.weakMembers.length }}/{{ detail().teamSize }}</b>
                      ({{ names(entry.weakMembers) }}) → {{ entry.safeCount }}/{{ detail().teamSize }} à l'abri
                    } @else {
                      aucun de tes Pokémon n'est faible → {{ entry.safeCount }}/{{ detail().teamSize }} à l'abri
                    }
                  </p>
                }
              </li>
            }
          </ul>

          <div class="space-y-1 border-t border-slate-700/60 bg-slate-950/60 px-4 py-3 font-mono text-[11px] text-slate-300">
            <p>Attaque {{ detail().attackPoints }}/{{ 2 * detail().opponentCount }} → {{ detail().attackScore }}/10 × 50 %</p>
            <p>+ Résistance {{ detail().resistPoints }}/{{ detail().opponentCount }} → {{ detail().resistScore }}/10 × 25 %</p>
            <p>+ Faiblesses {{ detail().safePoints }}/{{ detail().opponentCount * detail().teamSize }} → {{ detail().safeScore }}/10 × 25 %</p>
            <p class="pt-1 text-sm font-black text-white">= {{ detail().score }}/10</p>
          </div>
        }
      </div>
      }
    </div>
  `,
})
export class CoverageInfoComponent {
  readonly team = input.required<Pokemon[]>();
  readonly opponent = input.required<Pokemon[]>();
  readonly label = input('Ton équipe');

  protected readonly ICONS = ICONS;
  protected readonly open = signal(false);
  protected readonly detail = computed(() => explainDuoCoverage(this.team(), this.opponent()));
  protected readonly popoverId = `coverage-info-${nextId++}`;

  protected entryPoints(entry: CoverageEntry): string {
    return `${entry.attackPoints} + ${entry.resistor ? 1 : 0} + ${entry.safeCount}/${this.detail().teamSize}`;
  }

  protected typeColor(type: string): string {
    return TYPE_COLORS[type] ?? 'bg-slate-500';
  }

  protected formatMultiplier(value: number): string {
    return String(value).replace('.', ',');
  }

  protected names(members: Pokemon[]): string {
    return members.map(member => member.name).join(', ');
  }
}
