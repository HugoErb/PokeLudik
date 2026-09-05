import {
  Component,
  CUSTOM_ELEMENTS_SCHEMA,
  OnDestroy,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { NgClass } from '@angular/common';
import { Router, ActivatedRoute } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
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
import { DuelIntroComponent } from '../../components/duel-intro/duel-intro.component';
import { EndGameActionsComponent } from '../../components/end-game-actions/end-game-actions.component';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import {
  computeDuoCoverageScore as computePokemonDuoCoverageScore,
  computeFinalScore,
  computeRating as computePokemonRating,
  computeStatsScore as computePokemonStatsScore,
  computeTotal as computePokemonTotal,
  getRatingWidth as getPokemonRatingWidth,
  getScoreBarColor as getPokemonScoreBarColor,
  getScoreColor as getPokemonScoreColor,
  pickNUnique as pickNUniquePokemon,
  pickOneLegendary as pickOneLegendaryPokemon,
  pickOneStarter as pickOneStarterPokemon,
  preloadImages as preloadPokemonImages,
} from '../../utils/draft-utils';

export interface Trainer {
  nom: string;
  region: string;
  generation: number | string;
  role: string;
  version: string;
  image: string;
  pokemons: number[];
}

type Phase = 'loading' | 'playing' | 'complete';
type SlotState = 'idle' | 'leaving' | 'entering';

@Component({
  selector: 'app-draft-trainer',
  imports: [NgClass, PokemonCardComponent, DraftHelpModalComponent, DuelIntroComponent, EndGameActionsComponent, AppHeaderComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  animations: [slotsGridAnimation, slotStateAnimation, lockAnimation, scoreRevealAnimation],
  templateUrl: './draft-trainer.component.html',
})
export class DraftTrainerComponent implements OnInit, OnDestroy {
  protected readonly ICONS = ICONS;
  protected readonly TYPE_COLORS = TYPE_COLORS;
  protected readonly TYPE_ICONS = TYPE_ICONS;

  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly pokemonService = inject(PokemonService);
  private readonly supabaseService = inject(SupabaseService);

  private readonly allPokemon = toSignal(this.pokemonService.loadAll(), {
    initialValue: [] as Pokemon[],
  });

  private readonly trainerPool = computed(() => {
    const all = this.allPokemon();
    const trainer = this.trainer();
    if (!trainer) return all;

    const genValue = trainer.generation;

    // Cas spéciaux (Pato, etc.)
    if (genValue === 'Toutes' || genValue === 'Toutes régions' || trainer.nom === 'Pato') {
      return all;
    }

    // Cas spécial Red (Gen 1 + Gen 2)
    if (trainer.nom === 'Red') {
      return all.filter(p => p.generation === 1 || p.generation === 2);
    }

    // Gestion des nombres
    if (typeof genValue === 'number') {
      return all.filter(p => p.generation === genValue);
    }

    // Gestion des chaînes (ex: "1, 2" ou "1-2")
    if (typeof genValue === 'string') {
      if (genValue.includes(',') || genValue.includes('-')) {
        const parts = genValue.split(/[,\-]/).map(s => parseInt(s.trim(), 10)).filter(n => !isNaN(n));
        if (parts.length > 0) {
          if (genValue.includes('-') && parts.length === 2) {
            // Range (ex: "1-3")
            return all.filter(p => p.generation >= parts[0] && p.generation <= parts[1]);
          }
          // Liste (ex: "1, 2")
          return all.filter(p => parts.includes(p.generation));
        }
      }
      
      const gen = parseInt(genValue, 10);
      if (!isNaN(gen)) return all.filter(p => p.generation === gen);
    }

    return all;
  });

  private readonly statsRange = computed(() => {
    const all = this.trainerPool();
    if (all.length === 0) return { min: 0, max: 1 };
    const totals = all.map(p => this.computeTotal(p));
    return { min: Math.min(...totals), max: Math.max(...totals) };
  });

  readonly phase = signal<Phase>('loading');
  readonly trainer = signal<Trainer | null>(null);
  readonly showHelpModal = signal(false);
  readonly showDuelIntro = signal(false);
  readonly duelPlayer1 = signal<{ username: string; avatar_url?: string } | null>(null);
  readonly duelPlayer2 = signal<{ username: string; avatar_url?: string } | null>(null);
  readonly selectedPokemon = signal<Pokemon | null>(null);

  readonly slots = signal<(Pokemon | null)[]>([null, null, null, null, null, null]);
  readonly lockedIndices = signal<Set<number>>(new Set());
  readonly lockedPokemon = signal<(Pokemon | null)[]>([null, null, null, null, null, null]);
  private readonly usedIds = signal<Set<number>>(new Set());
  readonly slotStates = signal<SlotState[]>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
  readonly lockedCount = computed(() => this.lockedIndices().size);

  readonly timerValue = signal(10);
  readonly timerProgress = signal(1.0);
  private timerInterval: ReturnType<typeof setInterval> | null = null;
  private startTimerAfterIntro = false;
  private isLockingPick = false;

  readonly timerColor = computed(() => {
    const v = this.timerValue();
    if (v > 6) return 'text-green-400';
    if (v > 3) return 'text-yellow-400';
    return 'text-red-400';
  });
  readonly timerBarColor = computed(() => {
    const v = this.timerValue();
    if (v > 6) return 'bg-green-400';
    if (v > 3) return 'bg-yellow-400';
    return 'bg-red-400';
  });

  readonly myTeamPokemons = signal<Pokemon[]>([]);
  readonly opponentTeamPokemons = computed(() => {
    const t = this.trainer();
    const all = this.allPokemon();
    if (!t || all.length === 0) return [];
    const byId = new Map(all.map(p => [p.id, p]));
    return t.pokemons.map(id => byId.get(id)).filter((p): p is Pokemon => !!p);
  });
  readonly showScores = signal(false);
  private confettiFired = false;

  readonly myStatsScore = computed(() => this.computeStatsScore(this.myTeamPokemons()));
  readonly opponentStatsScore = computed(() => this.computeStatsScore(this.opponentTeamPokemons()));

  readonly myCoverageScore = computed(() =>
    this.computeDuoCoverageScore(this.myTeamPokemons(), this.opponentTeamPokemons())
  );
  readonly opponentCoverageScore = computed(() =>
    this.computeDuoCoverageScore(this.opponentTeamPokemons(), this.myTeamPokemons())
  );

  readonly myFinalScore = computed(() => {
    const s = this.myStatsScore();
    const c = this.myCoverageScore();
    if (s === 0 && c === 0) return 0;
    return computeFinalScore(s, c);
  });
  readonly opponentFinalScore = computed(() => {
    const s = this.opponentStatsScore();
    const c = this.opponentCoverageScore();
    if (s === 0 && c === 0) return 0;
    return computeFinalScore(s, c);
  });

  readonly winner = computed((): 'me' | 'opponent' | 'draw' => {
    const my = this.myFinalScore();
    const opp = this.opponentFinalScore();
    if (my > opp) return 'me';
    if (opp > my) return 'opponent';
    return 'draw';
  });

  /** Lifecycle Angular : initialise le composant. */
  async ngOnInit(): Promise<void> {
    try {
      const res = await fetch('/assets/trainers.json');
      const trainers = await res.json() as Trainer[];
      const idParam = this.route.snapshot.paramMap.get('id');
      const id = idParam ? parseInt(idParam, 10) : 0;

      if (!Number.isInteger(id) || id < 0 || id >= trainers.length) {
        void this.router.navigate(['/trainer-select']);
        return;
      }

      const user = this.supabaseService.getCurrentUser();
      const defeated = user ? await this.supabaseService.getDefeatedTrainers(user.id) : [];
      if (this.isTrainerLocked(id, defeated)) {
        void this.router.navigate(['/trainer-select']);
        return;
      }

      const selectedTrainer = trainers[id];
      this.trainer.set(selectedTrainer);

      if (this.allPokemon().length === 0) {
        const unsub = this.pokemonService.loadAll().subscribe(all => {
          if (all.length > 0) {
            unsub.unsubscribe();
            void this.initDraft();
          }
        });
      } else {
        void this.initDraft();
      }
    } catch {
      this.router.navigate(['/home']);
    }
  }

  /** Lifecycle Angular : nettoie les abonnements et timers du composant. */
  ngOnDestroy(): void {
    this.stopTimer();
  }

  /** Retourne true si le dresseur demande n'est pas encore debloque. */
  private isTrainerLocked(index: number, defeatedIndices: number[]): boolean {
    if (index === 0) return false;
    return !defeatedIndices.includes(index - 1);
  }

  /** Initialise l'etat du draft. */
  private async initDraft(): Promise<void> {
    const pool = this.trainerPool();
    const starter = this.pickOneStarter(pool, new Set());
    const legendary = this.pickOneLegendary(pool, new Set(starter ? [starter.id] : []));
    const excludeForNormal = new Set([
      ...(starter ? [starter.id] : []),
      ...(legendary ? [legendary.id] : []),
    ]);
    const normal = this.pickNUnique(this.normalSlotPool(pool), excludeForNormal, 4);
    const initial: (Pokemon | null)[] = [starter, ...normal, legendary];
    this.usedIds.set(new Set(initial.filter((p): p is Pokemon => p !== null).map(p => p.id)));
    this.slots.set(initial);
    this.lockedIndices.set(new Set());
    this.lockedPokemon.set([null, null, null, null, null, null]);
    this.slotStates.set(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
    this.isLockingPick = false;
    
    this.phase.set('playing');
    this.startTimerAfterIntro = true;
    const introShown = await this.triggerDuelIntro();
    if (introShown) {
      return;
    }
    this.startTimerAfterIntro = false;
    this.startTimer();
  }

  /** Ferme l'intro de duel. */
  onDuelIntroClosed(): void {
    this.showDuelIntro.set(false);
    if (this.startTimerAfterIntro && this.phase() === 'playing') {
      this.startTimerAfterIntro = false;
      this.startTimer();
    }
  }

  /** Declenche l'intro de duel si ses donnees sont disponibles. */
  private async triggerDuelIntro(): Promise<boolean> {
    const trainer = this.trainer();
    if (!trainer) return false;

    const idParam = this.route.snapshot.paramMap.get('id');
    const cached = this.readDuelIntroCache(`draft-trainer-intro-data-${idParam ?? '0'}`);
    this.duelPlayer1.set(cached?.[0] ?? { username: 'Moi', avatar_url: undefined });
    this.duelPlayer2.set(cached?.[1] ?? { username: trainer.nom, avatar_url: trainer.image });
    this.showDuelIntro.set(true);

    try {
      const user = this.supabaseService.getCurrentUser();
      const profile = user
        ? await this.supabaseService.getProfile(user.id).catch(() => ({ username: 'Moi', avatar_url: undefined }))
        : { username: 'Moi', avatar_url: undefined };

      const player1 = { username: profile.username, avatar_url: profile.avatar_url };
      const player2 = { username: trainer.nom, avatar_url: trainer.image };

      this.duelPlayer1.set(player1);
      this.duelPlayer2.set(player2);
      return true;
    } catch {
      return true;
    }
  }

  /** Lit les donnees de l'intro de duel depuis le cache local. */
  private readDuelIntroCache(key: string): { username: string; avatar_url?: string }[] | null {
    try {
      const cached = sessionStorage.getItem(key);
      return cached ? JSON.parse(cached) : null;
    } catch {
      return null;
    }
  }

  /** Gere le clic sur un slot de draft. */
  async onSlotClick(index: number): Promise<void> {
    if (this.isLockingPick || this.lockedIndices().has(index) || this.phase() !== 'playing') return;
    const picked = this.slots()[index];
    if (!picked) return;
    await this.lockPokemon(index, picked);
  }

  /** Choisit automatiquement un slot de draft. */
  private async autoPickSlot(): Promise<void> {
    if (this.isLockingPick) return;
    const unlocked = [0, 1, 2, 3, 4, 5].filter(i => !this.lockedIndices().has(i));
    if (unlocked.length === 0) return;
    const randomIndex = unlocked[Math.floor(Math.random() * unlocked.length)];
    const picked = this.slots()[randomIndex];
    if (picked) await this.lockPokemon(randomIndex, picked);
  }

  /** Verrouille le Pokemon choisi dans un slot de draft. */
  private async lockPokemon(index: number, picked: Pokemon): Promise<void> {
    if (this.isLockingPick) return;
    this.isLockingPick = true;
    this.stopTimer();

    this.lockedIndices.update(s => new Set([...s, index]));
    this.lockedPokemon.update(arr => {
      const next = [...arr];
      next[index] = picked;
      return next;
    });
    this.usedIds.update(s => new Set([...s, picked.id]));

    const unlocked = [0, 1, 2, 3, 4, 5].filter(i => !this.lockedIndices().has(i));

    if (unlocked.length === 0) {
      await this.enterCompletePhase();
      this.isLockingPick = false;
      return;
    }

    this.slotStates.update(states => {
      const next = [...states] as SlotState[];
      unlocked.forEach(i => (next[i] = 'leaving'));
      return next;
    });

    const slot0Unlocked = unlocked.includes(0);
    const slot5Unlocked = unlocked.includes(5);
    const unlockedNormal = unlocked.filter(i => i !== 0 && i !== 5);

    const newStarter = slot0Unlocked ? this.pickOneStarter(this.trainerPool(), this.usedIds()) : null;
    const excludeForNormal = new Set([...this.usedIds(), ...(newStarter ? [newStarter.id] : [])]);
    const newNormal = this.pickNUnique(this.normalSlotPool(this.trainerPool()), excludeForNormal, unlockedNormal.length);
    const excludeForLegend = new Set([...excludeForNormal, ...newNormal.map(p => p.id)]);
    const newLegendary = slot5Unlocked ? this.pickOneLegendary(this.trainerPool(), excludeForLegend) : null;

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
        if (this.phase() === 'playing') this.startTimer();
      }, unlocked.length * 60 + 400);
    });
  }

  /** Demarre le timer de choix. */
  private startTimer(): void {
    this.stopTimer();
    const start = Date.now();
    const duration = 10_000;
    this.timerValue.set(10);
    this.timerProgress.set(1.0);

    this.timerInterval = setInterval(() => {
      const elapsed = Date.now() - start;
      const rem = Math.max(0, duration - elapsed);
      this.timerValue.set(Math.ceil(rem / 1000));
      this.timerProgress.set(rem / duration);

      if (rem <= 0) {
        this.stopTimer();
        void this.autoPickSlot();
      }
    }, 200);
  }

  /** Arrete le timer de choix. */
  private stopTimer(): void {
    if (this.timerInterval) {
      clearInterval(this.timerInterval);
      this.timerInterval = null;
    }
  }

  /** Passe le draft en phase terminee. */
  private async enterCompletePhase(): Promise<void> {
    this.stopTimer();
    
    const myTeam = this.lockedPokemon().filter((p): p is Pokemon => p !== null);
    this.myTeamPokemons.set(myTeam);

    this.phase.set('complete');

    setTimeout(() => {
      this.showScores.set(true);
      if (this.winner() === 'me') {
        this.launchConfetti();
        
        // Enregistrer la victoire
        const user = this.supabaseService.getCurrentUser();
        const idParam = this.route.snapshot.paramMap.get('id');
        if (user && idParam) {
          const trainerIndex = parseInt(idParam, 10);
          this.supabaseService.recordTrainerDefeat(user.id, trainerIndex).catch(console.error);
        }
      }
    }, 800);
  }

  /** Navigue vers la page d'accueil. */
  async goHome(): Promise<void> {
    void this.router.navigate(['/home']);
  }

  /** Relance une partie. */
  async replay(): Promise<void> {
    this.phase.set('loading');
    this.showScores.set(false);
    this.confettiFired = false;
    this.isLockingPick = false;
    this.myTeamPokemons.set([]);
    
    // Petit délai pour l'effet visuel
    setTimeout(() => {
      void this.initDraft();
    }, 500);
  }

  /** Navigue vers la selection de dresseur. */
  async goToTrainerSelect(): Promise<void> {
    void this.router.navigate(['/trainer-select']);
  }

  /** Calcule le total des statistiques d'un Pokemon. */
  private computeTotal(p: Pokemon): number {
    return computePokemonTotal(p);
  }

  /** Calcule la note d'un Pokemon sur la plage donnee. */
  private computeRating(p: Pokemon): number {
    return computePokemonRating(p, this.statsRange());
  }

  /** Calcule le score moyen de statistiques d'une equipe. */
  private computeStatsScore(team: Pokemon[]): number {
    return computePokemonStatsScore(team, this.statsRange());
  }

  /** Calcule le score de couverture offensive et defensive d'une equipe contre une autre. */
  private computeDuoCoverageScore(myTeam: Pokemon[], opponentTeam: Pokemon[]): number {
    return computePokemonDuoCoverageScore(myTeam, opponentTeam);
  }

  /** Retourne la note d'un Pokemon. */
  getRating(p: Pokemon): number {
    return this.computeRating(p);
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

  /** Retourne la classe CSS de couleur associee a un score. */
  getScoreColor(score: number): string {
    return getPokemonScoreColor(score);
  }

  /** Retourne la classe CSS de barre associee a un score. */
  getScoreBarColor(score: number): string {
    return getPokemonScoreBarColor(score);
  }

  /** Retourne la classe CSS de couleur associee a un type Pokemon. */
  getTypeColor(type: string): string {
    return TYPE_COLORS[type] ?? 'bg-gray-500';
  }

  /** Retourne l'icone associee a un type Pokemon. */
  getTypeIcon(type: string): string {
    return TYPE_ICONS[type] ?? 'mdi:circle-outline';
  }

  /** Ouvre la modal de details d'un Pokemon. */
  openPokemonDetails(pokemon: Pokemon): void {
    this.selectedPokemon.set(pokemon);
  }

  /** Ferme la modal de details d'un Pokemon. */
  closePokemonDetails(): void {
    this.selectedPokemon.set(null);
  }

  /** Selectionne un starter disponible dans le pool. */
  private pickOneStarter(pool: Pokemon[], exclude: Set<number>): Pokemon {
    return pickOneStarterPokemon(pool, exclude, this.slots());
  }

  /** Selectionne un Pokemon legendaire ou fabuleux disponible dans le pool. */
  private pickOneLegendary(pool: Pokemon[], exclude: Set<number>): Pokemon {
    return pickOneLegendaryPokemon(pool, exclude, this.slots());
  }

  /** Retourne le pool utilisable pour un slot normal. */
  private normalSlotPool(pool: Pokemon[]): Pokemon[] {
    if (this.trainer()?.nom === 'Pato') return pool;
    return pool.filter(p => p.category !== 'légendaire' && p.category !== 'fabuleux');
  }

  /** Selectionne plusieurs Pokemon uniques dans le pool. */
  private pickNUnique(pool: Pokemon[], exclude: Set<number>, n: number): Pokemon[] {
    return pickNUniquePokemon(pool, exclude, n);
  }

  /** Precharge les images donnees. */
  private preloadImages(urls: string[]): Promise<void[]> {
    return preloadPokemonImages(urls);
  }

  /** Lance l'animation de confettis. */
  private launchConfetti(): void {
    if (this.confettiFired) return;
    this.confettiFired = true;
    const colors = ['#ef4444', '#facc15', '#a855f7', '#3b82f6', '#ffffff'];
    confetti({ particleCount: 160, spread: 110, origin: { x: 0.5, y: 0.4 }, colors });
  }
}
