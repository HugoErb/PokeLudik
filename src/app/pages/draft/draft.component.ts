import {
  Component,
  CUSTOM_ELEMENTS_SCHEMA,
  OnInit,
  computed,
  effect,
  inject,
  signal,
  untracked,
} from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { NgClass } from '@angular/common';
import { Router } from '@angular/router';
import { PokemonService } from '../../services/pokemon.service';
import { SupabaseService } from '../../services/supabase.service';
import { Pokemon } from '../../models/pokemon.model';
import { ICONS } from '../../constants/icons';
import { TYPE_COLORS, TYPE_ICONS } from '../../constants/type-chart';
import {
  lockAnimation,
  scoreRevealAnimation,
  slotStateAnimation,
  slotsGridAnimation,
} from '../../constants/animations';
import confetti from 'canvas-confetti';
import { PokemonCardComponent } from '../../components/pokemon-card/pokemon-card.component';
import { DraftHelpModalComponent } from '../../components/draft-help-modal/draft-help-modal.component';
import { ModeSelectCardComponent } from '../../components/mode-select-card/mode-select-card.component';
import { ModeSelectComponent } from '../../components/mode-select-card/mode-select.component';
import { EndGameActionsComponent } from '../../components/end-game-actions/end-game-actions.component';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { GameSettingsPanelComponent } from '../../components/game-settings-panel/game-settings-panel.component';
import { DEFAULT_MODE_SETTINGS, ModeSettings, normalizeModeSettings } from '../../models/game-settings.model';
import {
  computeRating as computePokemonRating,
  computeTotal as computePokemonTotal,
  getRatingWidth as getPokemonRatingWidth,
  getScoreBarColor as getPokemonScoreBarColor,
  getScoreColor as getPokemonScoreColor,
  pickNUnique as pickNUniquePokemon,
  pickOneLegendary as pickOneLegendaryPokemon,
  pickOneStarter as pickOneStarterPokemon,
  preloadImages as preloadPokemonImages,
} from '../../utils/draft-utils';

type SlotState = 'idle' | 'leaving' | 'entering';
type DraftConfigMode = 'solo';

@Component({
  selector: 'app-draft',
  imports: [NgClass, PokemonCardComponent, DraftHelpModalComponent, ModeSelectCardComponent, ModeSelectComponent, EndGameActionsComponent, AppHeaderComponent, GameSettingsPanelComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  animations: [slotsGridAnimation, slotStateAnimation, lockAnimation, scoreRevealAnimation],
  templateUrl: './draft.component.html',
})
export class DraftComponent implements OnInit {
  protected readonly ICONS = ICONS;
  protected readonly TYPE_COLORS = TYPE_COLORS;
  protected readonly TYPE_ICONS = TYPE_ICONS;

  private readonly router = inject(Router);
  private readonly pokemonService = inject(PokemonService);
  private readonly supabaseService = inject(SupabaseService);

  private readonly allPokemon = toSignal(this.pokemonService.loadAll(), {
    initialValue: [] as Pokemon[],
  });

  private readonly statsRange = computed(() => {
    const all = this.allPokemon();
    if (all.length === 0) return { min: 0, max: 1 };
    const totals = all.map(p => this.computeTotal(p));
    return { min: Math.min(...totals), max: Math.max(...totals) };
  });

  readonly slots = signal<(Pokemon | null)[]>([null, null, null, null, null, null]);
  readonly lockedIndices = signal<Set<number>>(new Set());
  readonly lockedPokemon = signal<(Pokemon | null)[]>([null, null, null, null, null, null]);
  private readonly usedIds = signal<Set<number>>(new Set());
  readonly slotStates = signal<SlotState[]>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
  readonly phase = signal<'mode-select' | 'loading' | 'draft' | 'complete'>('mode-select');
  readonly showScore = signal(false);
  readonly showHelpModal = signal(false);
  readonly isResetting = signal(false);
  readonly isCreatingRoom = signal(false);
  readonly draftConfigMode = signal<DraftConfigMode | null>(null);
  readonly settings = signal<ModeSettings>({ ...DEFAULT_MODE_SETTINGS.draft_duo });

  readonly lockedCount = computed(() => this.lockedIndices().size);
  readonly selectedPokemon = signal<Pokemon | null>(null);
  private confettiFired = false;
  private isLockingPick = false;

  readonly statsScore = computed((): number => {
    const locked = this.lockedPokemon();
    const range = this.statsRange();
    const ratings = locked
      .filter((p): p is Pokemon => p !== null)
      .map(p => this.computeRating(p, range));
    if (ratings.length === 0) return 0;
    return Math.round((ratings.reduce((a, b) => a + b, 0) / ratings.length) * 10) / 10;
  });

  private readonly STORAGE_KEY = 'draft_state';

  /** Sauvegarde l'etat du draft en stockage local. */
  private saveState(): void {
    const state = {
      slots: this.slots().map(p => p?.id ?? null),
      lockedIndices: [...this.lockedIndices()],
      lockedPokemon: this.lockedPokemon().map(p => p?.id ?? null),
      usedIds: [...this.usedIds()],
      phase: this.phase(),
      showScore: this.showScore(),
    };
    sessionStorage.setItem(this.STORAGE_KEY, JSON.stringify(state));
  }

  /** Charge l'etat du draft depuis le stockage local. */
  private loadSavedState(): Record<string, unknown> | null {
    try {
      const raw = sessionStorage.getItem(this.STORAGE_KEY);
      return raw ? JSON.parse(raw) as Record<string, unknown> : null;
    } catch {
      return null;
    }
  }

  /** Supprime l'etat de draft sauvegarde. */
  private clearSavedState(): void {
    sessionStorage.removeItem(this.STORAGE_KEY);
  }

  /** Restaure l'etat du draft depuis une sauvegarde. */
  private restoreState(saved: Record<string, unknown>): void {
    const all = this.allPokemon();
    const byId = new Map(all.map(p => [p.id, p]));

    const slotIds = saved['slots'] as (number | null)[];
    const lockedIds = saved['lockedPokemon'] as (number | null)[];
    const slots = slotIds.map(id => (id !== null ? (byId.get(id) ?? null) : null));
    const lockedPokemon = lockedIds.map(id => (id !== null ? (byId.get(id) ?? null) : null));

    const allFound = [...slots, ...lockedPokemon]
      .filter(id => id !== null)
      .every(p => p !== undefined);
    if (!allFound) {
      this.initDraft();
      return;
    }

    this.slots.set(slots);
    this.lockedIndices.set(new Set(saved['lockedIndices'] as number[]));
    this.lockedPokemon.set(lockedPokemon);
    this.usedIds.set(new Set(saved['usedIds'] as number[]));
    this.slotStates.set(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    this.phase.set(saved['phase'] as 'draft' | 'complete');
    this.showScore.set(saved['showScore'] as boolean);
  }

  constructor() {
    effect(() => {
      const all = this.allPokemon();
      if (all.length > 0 && this.phase() === 'loading') {
        untracked(() => {
          const saved = this.loadSavedState();
          if (saved) {
            this.restoreState(saved);
          } else {
            this.initDraft();
          }
        });
      }
    });

    effect(() => {
      if (this.showScore()) {
        untracked(() => this.launchConfetti());
      }
    });
  }

  /** Demarre une partie solo. */
  startSolo(): void {
    this.phase.set('loading');
  }

  selectDraftConfigMode(mode: DraftConfigMode): void {
    this.draftConfigMode.set(mode);
  }

  /** Demarre le draft contre un dresseur. */
  startTrainer(): void {
    void this.router.navigate(['/trainer-select']);
  }

  /** Demarre un draft duo. */
  async startDuo(): Promise<void> {
    this.isCreatingRoom.set(true);
    try {
      const roomId = await this.supabaseService.createDraftDuoRoom();
      void this.router.navigate(['/lobby', roomId], { queryParams: { mode: 'draft_duo' } });
    } catch (err) {
      console.error('[DraftComponent] Erreur création room duo:', err);
      this.isCreatingRoom.set(false);
    }
  }

  /** Initialise l'etat du draft. */
  private initDraft(): void {
    const pool = this.getConfiguredPokemonPool();
    const starter = this.pickOneStarter(pool, new Set());
    const legendary = this.pickOneLegendary(pool, new Set(starter ? [starter.id] : []));
    const excludeForNormal = new Set([
      ...(starter ? [starter.id] : []),
      ...(legendary ? [legendary.id] : []),
    ]);
    const normal = this.pickNUnique(pool, excludeForNormal, 4);
    const initial: (Pokemon | null)[] = [starter, ...normal, legendary];
    this.usedIds.set(new Set(initial.filter((p): p is Pokemon => p !== null).map(p => p.id)));
    this.slots.set(initial);
    this.lockedIndices.set(new Set());
    this.lockedPokemon.set([null, null, null, null, null, null]);
    this.slotStates.set(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    this.showScore.set(false);
    this.isLockingPick = false;
    this.phase.set('draft');
    this.saveState();
  }

  /** Gere le clic sur un slot de draft. */
  onSlotClick(index: number): void {
    if (this.isLockingPick || this.lockedIndices().has(index) || this.phase() !== 'draft') return;
    this.isLockingPick = true;

    const picked = this.slots()[index];
    if (!picked) return;

    // Verrouiller le slot
    this.lockedIndices.update(s => new Set([...s, index]));
    this.lockedPokemon.update(arr => {
      const next = [...arr];
      next[index] = picked;
      return next;
    });
    this.usedIds.update(s => new Set([...s, picked.id]));

    const unlocked = [0, 1, 2, 3, 4, 5].filter(i => !this.lockedIndices().has(i));

    if (unlocked.length === 0) {
      this.phase.set('complete');
      this.saveState();
      setTimeout(() => {
        this.showScore.set(true);
        this.saveState();
      }, 700);
      this.isLockingPick = false;
      return;
    }

    this.saveState();

    // Animation sortie
    this.slotStates.update(states => {
      const next = [...states] as SlotState[];
      unlocked.forEach(i => (next[i] = 'leaving'));
      return next;
    });

    // Picker les nouveaux Pokémon immédiatement (pendant l'animation de sortie)
    const slot0Unlocked = unlocked.includes(0);
    const slot5Unlocked = unlocked.includes(5);
    const unlockedNormal = unlocked.filter(i => i !== 0 && i !== 5);

    const pool = this.getConfiguredPokemonPool();
    const newStarter = slot0Unlocked ? this.pickOneStarter(pool, this.usedIds()) : null;
    const excludeForNormal = new Set([...this.usedIds(), ...(newStarter ? [newStarter.id] : [])]);
    const newNormal = this.pickNUnique(pool, excludeForNormal, unlockedNormal.length);
    const excludeForLegend = new Set([...excludeForNormal, ...newNormal.map(p => p.id)]);
    const newLegendary = slot5Unlocked ? this.pickOneLegendary(pool, excludeForLegend) : null;

    const allNew = [
      ...(newStarter ? [newStarter] : []),
      ...newNormal,
      ...(newLegendary ? [newLegendary] : []),
    ];
    this.usedIds.update(s => new Set([...s, ...allNew.map(p => p.id)]));

    const newBySlot = new Map<number, Pokemon>();
    if (slot0Unlocked && newStarter) newBySlot.set(0, newStarter);
    unlockedNormal.forEach((slotIdx, i) => newBySlot.set(slotIdx, newNormal[i]));
    if (slot5Unlocked && newLegendary) newBySlot.set(5, newLegendary);

    // Attendre : fin de l'animation sortie ET préchargement des sprites
    const leavingDone = new Promise<void>(resolve => setTimeout(resolve, 300));
    const spritesDone = this.preloadImages(allNew.map(p => p.sprite));

    void Promise.all([leavingDone, spritesDone]).then(() => {
      unlocked.forEach((slotIdx, i) => {
        setTimeout(() => {
          const newPokemon = newBySlot.get(slotIdx);
          if (newPokemon) {
            this.slots.update(arr => {
              const next = [...arr];
              next[slotIdx] = newPokemon;
              return next;
            });
          }
          this.slotStates.update(states => {
            const next = [...states] as SlotState[];
            next[slotIdx] = 'entering';
            return next;
          });
        }, i * 60);
      });

      setTimeout(() => {
        this.slotStates.update(states => {
          const next = [...states] as SlotState[];
          unlocked.forEach(i => (next[i] = 'idle'));
          return next;
        });
        this.isLockingPick = false;
        this.saveState();
      }, unlocked.length * 60 + 400);
    });
  }

  /** Precharge les images donnees. */
  private preloadImages(urls: string[]): Promise<void[]> {
    return preloadPokemonImages(urls);
  }

  /** Relance une partie. */
  replay(): void {
    this.clearSavedState();
    this.confettiFired = false;
    this.isLockingPick = false;
    this.phase.set('loading');
  }

  /** Reinitialise l'equipe draftee. */
  resetTeam(): void {
    if (this.phase() !== 'draft') return;
    this.clearSavedState();
    this.isLockingPick = false;
    this.isResetting.set(true);
    setTimeout(() => {
      this.initDraft();
      this.isResetting.set(false);
    }, 50);
  }

  updateGameSettings(settings: ModeSettings): void {
    this.settings.set(settings);
    if (this.phase() === 'draft') this.saveState();
  }

  /** Navigue vers la page d'accueil. */
  goHome(): void {
    this.clearSavedState();
    void this.router.navigate(['/home']);
  }

  /** Ouvre la modal de details d'un Pokemon. */
  openPokemonDetails(pokemon: Pokemon): void {
    this.selectedPokemon.set(pokemon);
  }

  /** Ferme la modal de details d'un Pokemon. */
  closePokemonDetails(): void {
    this.selectedPokemon.set(null);
  }

  // ─── Calculs rating ──────────────────────────────────────────────────────────

  /** Retourne la classe CSS de couleur associee a un score. */
  getScoreColor(score: number): string {
    return getPokemonScoreColor(score);
  }

  /** Retourne la classe CSS de barre associee a un score. */
  getScoreBarColor(score: number): string {
    return getPokemonScoreBarColor(score);
  }

  /** Calcule le total des statistiques d'un Pokemon. */
  private computeTotal(p: Pokemon): number {
    return computePokemonTotal(p);
  }

  /** Calcule la note d'un Pokemon sur la plage donnee. */
  private computeRating(p: Pokemon, range: { min: number; max: number }): number {
    return computePokemonRating(p, range);
  }

  /** Retourne la note d'un Pokemon. */
  getRating(p: Pokemon): number {
    return this.computeRating(p, this.statsRange());
  }

  /** Retourne la classe CSS de couleur associee a une note. */
  getRatingColor(rating: number): string {
    return getPokemonScoreColor(rating);
  }

  /** Retourne la classe CSS de barre associee a une note. */
  getRatingBarColor(rating: number): string {
    return getPokemonScoreBarColor(rating);
  }

  /** Retourne la largeur CSS correspondant a une note. */
  getRatingWidth(rating: number): string {
    return getPokemonRatingWidth(rating);
  }

  /** Retourne la classe CSS de couleur associee a un type Pokemon. */
  getTypeColor(type: string): string {
    return TYPE_COLORS[type] ?? 'bg-gray-500';
  }

  /** Retourne l'icone associee a un type Pokemon. */
  getTypeIcon(type: string): string {
    return TYPE_ICONS[type] ?? 'mdi:circle-outline';
  }

  // ─── Sélection aléatoire sans doublons ───────────────────────────────────────

  /** Selectionne un starter disponible dans le pool. */
  private pickOneStarter(pool: Pokemon[], exclude: Set<number>): Pokemon {
    return pickOneStarterPokemon(pool, exclude, this.slots());
  }

  /** Selectionne un Pokemon legendaire ou fabuleux disponible dans le pool. */
  private pickOneLegendary(pool: Pokemon[], exclude: Set<number>): Pokemon {
    return pickOneLegendaryPokemon(pool, exclude, this.slots());
  }

  /** Selectionne plusieurs Pokemon uniques dans le pool. */
  private pickNUnique(pool: Pokemon[], exclude: Set<number>, n: number): Pokemon[] {
    return pickNUniquePokemon(pool, exclude, n);
  }

  private getConfiguredPokemonPool(): Pokemon[] {
    const settings = normalizeModeSettings('draft_duo', this.settings());
    return this.allPokemon().filter(pokemon => {
      if (settings.generations.length > 0 && !settings.generations.includes(pokemon.generation)) return false;
      if (settings.categories.length > 0 && !settings.categories.includes(pokemon.category)) return false;
      return true;
    });
  }

  // ─── Confetti ────────────────────────────────────────────────────────────────

  /** Lifecycle Angular : initialise le composant. */
  ngOnInit(): void {
    this.supabaseService.trackPresence('in_game');
  }

  /** Lance l'animation de confettis. */
  private launchConfetti(): void {
    if (this.confettiFired) return;
    this.confettiFired = true;
    const colors = ['#ef4444', '#facc15', '#a855f7', '#3b82f6', '#ffffff'];
    confetti({ particleCount: 160, spread: 110, origin: { x: 0.5, y: 0.4 }, colors });
  }
}
