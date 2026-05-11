import {
  Component,
  CUSTOM_ELEMENTS_SCHEMA,
  OnDestroy,
  OnInit,
  computed,
  inject,
  input,
  signal,
} from '@angular/core';
import { NgClass } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';
import { toSignal } from '@angular/core/rxjs-interop';
import { PokemonService } from '../../services/pokemon.service';
import { SupabaseService } from '../../services/supabase.service';
import { Pokemon } from '../../models/pokemon.model';
import { DraftDuoRoom } from '../../models/room.model';
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
import { EndGameActionsComponent } from '../../components/end-game-actions/end-game-actions.component';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import {
  computeDuoCoverageScore as computePokemonDuoCoverageScore,
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

type DuoPhase = 'loading' | 'waiting' | 'playing' | 'waiting-opponent' | 'complete';
type SlotState = 'idle' | 'leaving' | 'entering';

@Component({
  selector: 'app-draft-duo',
  imports: [NgClass, PokemonCardComponent, DraftHelpModalComponent, EndGameActionsComponent, AppHeaderComponent, CancelModalComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  animations: [slotsGridAnimation, slotStateAnimation, lockAnimation, scoreRevealAnimation],
  templateUrl: './draft-duo.component.html',
})
export class DraftDuoComponent implements OnInit, OnDestroy {
  protected readonly ICONS = ICONS;
  protected readonly TYPE_COLORS = TYPE_COLORS;
  protected readonly TYPE_ICONS = TYPE_ICONS;

  readonly roomId = input.required<string>();

  private readonly route = inject(ActivatedRoute);
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

  // ─── État de la partie ──────────────────────────────────────────────────────
  readonly phase = signal<DuoPhase>('loading');
  readonly room = signal<DraftDuoRoom | null>(null);
  readonly isPlayer1 = signal(false);
  readonly player2Username = signal<string | null>(null);
  readonly isLaunching = signal(false);
  readonly linkCopied = signal(false);
  readonly showHelpModal = signal(false);
  readonly selectedPokemon = signal<Pokemon | null>(null);
  readonly showCancelModal = signal(false);
  readonly isCancelling = signal(false);

  // ─── Draft local ────────────────────────────────────────────────────────────
  readonly slots = signal<(Pokemon | null)[]>([null, null, null, null, null, null]);
  readonly lockedIndices = signal<Set<number>>(new Set());
  readonly lockedPokemon = signal<(Pokemon | null)[]>([null, null, null, null, null, null]);
  private readonly usedIds = signal<Set<number>>(new Set());
  readonly slotStates = signal<SlotState[]>(['idle', 'idle', 'idle', 'idle', 'idle', 'idle']);
  readonly lockedCount = computed(() => this.lockedIndices().size);

  // ─── Timer ──────────────────────────────────────────────────────────────────
  readonly timerValue = signal(10);
  readonly timerProgress = signal(1.0);
  private timerInterval: ReturnType<typeof setInterval> | null = null;

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

  // ─── Progression adversaire ─────────────────────────────────────────────────
  readonly opponentPickCount = signal(0);
  readonly opponentLockedPokemons = signal<Pokemon[]>([]);

  // ─── Statut adversaire ──────────────────────────────────────────────────────
  readonly opponentLeft = signal(false);

  // ─── Rejouer ─────────────────────────────────────────────────────────────────
  readonly iWantReplay = computed(() => {
    const r = this.room();
    if (!r) return false;
    return this.isPlayer1() ? r.p1_ready : r.p2_ready;
  });
  readonly opponentWantsReplay = computed(() => {
    const r = this.room();
    if (!r) return false;
    return this.isPlayer1() ? r.p2_ready : r.p1_ready;
  });

  // ─── Scores (phase complete) ─────────────────────────────────────────────────
  readonly myTeamPokemons = signal<Pokemon[]>([]);
  readonly opponentTeamPokemons = signal<Pokemon[]>([]);
  readonly showScores = signal(false);

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
    return Math.round(((s + c) / 2) * 10) / 10;
  });
  readonly opponentFinalScore = computed(() => {
    const s = this.opponentStatsScore();
    const c = this.opponentCoverageScore();
    if (s === 0 && c === 0) return 0;
    return Math.round(((s + c) / 2) * 10) / 10;
  });

  readonly winner = computed((): 'me' | 'opponent' | 'draw' => {
    const my = this.myFinalScore();
    const opp = this.opponentFinalScore();
    if (my > opp) return 'me';
    if (opp > my) return 'opponent';
    return 'draw';
  });

  private roomSub?: Subscription;
  private inviteResponseSub?: Subscription;
  private broadcastSub?: Subscription;
  private pollInterval: ReturnType<typeof setInterval> | null = null;
  private enteringComplete = false;
  private confettiFired = false;
  private isLockingPick = false;
  private replayLaunchInProgress = false;

  // ─── Cycle de vie ────────────────────────────────────────────────────────────

  /** Lifecycle Angular : initialise le composant. */
  async ngOnInit(): Promise<void> {
    this.supabaseService.trackPresence('in_game');
    try {
      const room = await this.supabaseService.getDraftDuoRoom(this.roomId());
      this.room.set(room);
      if (room.status === 'finished' && room.winner === null) {
        void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
        return;
      }

      const currentUser = this.supabaseService.getCurrentUser();
      if (!currentUser) { this.router.navigate(['/login']); return; }
      this.isPlayer1.set(room.player1_id === currentUser.id);
      void this.launchReplayIfReady(room);

      // Subscription Realtime
      this.roomSub = this.supabaseService.subscribeToDraftDuoRoom(this.roomId()).subscribe(updated => {
        this.onRoomUpdated(updated);
      });

      // Polling de secours
      this.pollInterval = setInterval(async () => {
        const r = await this.supabaseService.getDraftDuoRoom(this.roomId());
        this.onRoomUpdated(r);
      }, 2000);

      if (room.status === 'playing') {
        await this.enterPlayingPhase(room);
      } else if (room.status === 'finished') {
        await this.enterCompletePhase(room);
      } else {
        this.phase.set('waiting');
        if (room.player2_id) {
          await this.loadPlayer2Username(room.player2_id);
        }
      }

      const inviteId = this.route.snapshot.queryParamMap.get('inviteId');
      const friendName = this.route.snapshot.queryParamMap.get('friendName') ?? 'Ton ami';
      if (inviteId) {
        this.inviteResponseSub = this.supabaseService.subscribeToGameInviteResponse(inviteId).subscribe((invite) => {
          if (invite.status === 'declined') {
            void this.router.navigate(['/home'], { queryParams: { declined: friendName } });
          }
        });
      }

      this.broadcastSub = this.supabaseService.broadcastEvents$.subscribe(({ event }) => {
        if (event === 'player_left') {
          void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
        }
      });
    } catch {
      this.router.navigate(['/home']);
    }
  }

  /** Lifecycle Angular : nettoie les abonnements et timers du composant. */
  ngOnDestroy(): void {
    this.stopTimer();
    this.roomSub?.unsubscribe();
    this.inviteResponseSub?.unsubscribe();
    this.broadcastSub?.unsubscribe();
    if (this.pollInterval) clearInterval(this.pollInterval);
  }

  // ─── Gestion des mises à jour de la room ────────────────────────────────────

  /** Synchronise l'etat local apres une mise a jour de room. */
  private async onRoomUpdated(updated: DraftDuoRoom): Promise<void> {
    const prev = this.room();
    this.room.set(updated);

    if (updated.status === 'finished' && updated.winner === null) {
      this.stopTimer();
      void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
      return;
    }

    if (await this.launchReplayIfReady(updated)) return;

    // P2 vient de rejoindre
    if (!prev?.player2_id && updated.player2_id && this.phase() === 'waiting') {
      await this.loadPlayer2Username(updated.player2_id);
    }

    // La partie a démarré (P1 a cliqué "Lancer")
    if (prev?.status !== 'playing' && updated.status === 'playing' && this.phase() === 'waiting') {
      await this.enterPlayingPhase(updated);
      return;
    }

    // Rejouer : la room a été réinitialisée pour une nouvelle partie
    if (prev?.status === 'finished' && updated.status === 'playing' && this.phase() === 'complete') {
      this.resetForReplay();
      await this.enterPlayingPhase(updated);
      return;
    }

    // Mettre à jour la progression de l'adversaire en cours de partie
    if (this.phase() === 'playing' || this.phase() === 'waiting-opponent') {
      const opponentTeamIds = this.isPlayer1() ? updated.p2_team : updated.p1_team;
      this.opponentPickCount.set(opponentTeamIds.length);

      const all = this.allPokemon();
      if (all.length > 0) {
        const byId = new Map(all.map(p => [p.id, p]));
        this.opponentLockedPokemons.set(
          opponentTeamIds.map(id => byId.get(id)).filter((p): p is Pokemon => !!p)
        );
      }

      // L'adversaire a terminé → phase complete
      if (opponentTeamIds.length === 6 && this.lockedCount() === 6) {
        await this.enterCompletePhase(updated);
      }
    }

    // Room terminée
    if (updated.status === 'finished') {
      if (this.phase() !== 'complete') {
        await this.enterCompletePhase(updated);
      } else if (this.winner() === 'me') {
        this.launchConfetti();
      }
    }
  }

  /** Charge le pseudo du joueur 2. */
  private async loadPlayer2Username(player2Id: string): Promise<void> {
    try {
      const profile = await this.supabaseService.getProfile(player2Id);
      this.player2Username.set(profile.username);
    } catch {
      this.player2Username.set('Adversaire');
    }
  }

  // ─── Démarrage du jeu ───────────────────────────────────────────────────────

  /** Lance la partie. */
  async launchGame(): Promise<void> {
    if (this.isLaunching() || !this.room()?.player2_id) return;
    this.isLaunching.set(true);
    try {
      await this.supabaseService.updateDraftDuoRoom(this.roomId(), { status: 'playing' });
    } catch {
      this.isLaunching.set(false);
    }
  }

  /** Passe la room en phase de jeu. */
  private async enterPlayingPhase(room: DraftDuoRoom): Promise<void> {
    // Charger adversaire si pas encore fait
    if (!this.player2Username() && room.player2_id) {
      await this.loadPlayer2Username(room.player2_id);
    }

    // Mettre à jour progression adversaire
    const opponentTeamIds = this.isPlayer1() ? room.p2_team : room.p1_team;
    this.opponentPickCount.set(opponentTeamIds.length);

    const all = this.allPokemon();
    if (all.length > 0) {
      const byId = new Map(all.map(p => [p.id, p]));
      this.opponentLockedPokemons.set(
        opponentTeamIds.map(id => byId.get(id)).filter((p): p is Pokemon => !!p)
      );
    }

    // Si Pokémon pas encore chargés, attendre
    if (this.allPokemon().length === 0) {
      const unsub = this.pokemonService.loadAll().subscribe(all => {
        if (all.length > 0) {
          unsub.unsubscribe();
          this.initDraft();
          this.phase.set('playing');
          this.startTimer();
        }
      });
    } else {
      this.initDraft();
      this.phase.set('playing');
      this.startTimer();
    }
  }

  // ─── Draft local ────────────────────────────────────────────────────────────

  /** Initialise l'etat du draft. */
  private initDraft(): void {
    const pool = this.allPokemon();
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
    this.isLockingPick = false;
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

    // Sauvegarder en DB
    const newTeam = this.lockedPokemon()
      .filter((p): p is Pokemon => p !== null)
      .map(p => p.id);
    try {
      const patch = this.isPlayer1() ? { p1_team: newTeam } : { p2_team: newTeam };
      await this.supabaseService.updateDraftDuoRoom(this.roomId(), patch);
    } catch { /* on continue même si l'écriture échoue */ }

    const unlocked = [0, 1, 2, 3, 4, 5].filter(i => !this.lockedIndices().has(i));

    if (unlocked.length === 0) {
      // Tous les 6 sélectionnés → vérifier si l'adversaire a terminé
      const currentRoom = this.room();
      const opponentTeam = this.isPlayer1() ? currentRoom?.p2_team : currentRoom?.p1_team;
      if (opponentTeam && opponentTeam.length === 6) {
        // Les deux ont terminé
        const updatedRoom = await this.supabaseService.getDraftDuoRoom(this.roomId());
        await this.enterCompletePhase(updatedRoom);
      } else {
        this.phase.set('waiting-opponent');
      }
      this.isLockingPick = false;
      return;
    }

    // Animer la sortie et charger de nouveaux Pokémon
    this.slotStates.update(states => {
      const next = [...states] as SlotState[];
      unlocked.forEach(i => (next[i] = 'leaving'));
      return next;
    });

    const slot0Unlocked = unlocked.includes(0);
    const slot5Unlocked = unlocked.includes(5);
    const unlockedNormal = unlocked.filter(i => i !== 0 && i !== 5);

    const newStarter = slot0Unlocked ? this.pickOneStarter(this.allPokemon(), this.usedIds()) : null;
    const excludeForNormal = new Set([...this.usedIds(), ...(newStarter ? [newStarter.id] : [])]);
    const newNormal = this.pickNUnique(this.allPokemon(), excludeForNormal, unlockedNormal.length);
    const excludeForLegend = new Set([...excludeForNormal, ...newNormal.map(p => p.id)]);
    const newLegendary = slot5Unlocked ? this.pickOneLegendary(this.allPokemon(), excludeForLegend) : null;

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
        // Relancer le timer pour le prochain pick
        this.isLockingPick = false;
        if (this.phase() === 'playing') this.startTimer();
      }, unlocked.length * 60 + 400);
    });
  }

  // ─── Timer ──────────────────────────────────────────────────────────────────

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

  // ─── Phase complète ──────────────────────────────────────────────────────────

  /** Passe le draft en phase terminee. */
  private async enterCompletePhase(room: DraftDuoRoom): Promise<void> {
    if (this.enteringComplete || this.phase() === 'complete') return;
    this.enteringComplete = true;
    this.stopTimer();
    const all = this.allPokemon().length > 0
      ? this.allPokemon()
      : await new Promise<Pokemon[]>(resolve => {
          const unsub = this.pokemonService.loadAll().subscribe(list => {
            if (list.length > 0) { unsub.unsubscribe(); resolve(list); }
          });
        });

    const byId = new Map(all.map(p => [p.id, p]));
    const myTeamIds = this.isPlayer1() ? room.p1_team : room.p2_team;
    const opponentTeamIds = this.isPlayer1() ? room.p2_team : room.p1_team;

    this.myTeamPokemons.set(myTeamIds.map(id => byId.get(id)).filter((p): p is Pokemon => !!p));
    this.opponentTeamPokemons.set(opponentTeamIds.map(id => byId.get(id)).filter((p): p is Pokemon => !!p));

    this.phase.set('complete');

    setTimeout(() => {
      this.showScores.set(true);
      void this.saveWinner(room);
      if (this.winner() === 'me') {
        this.launchConfetti();
      }
    }, 800);
  }

  /** Enregistre le gagnant de la partie. */
  private async saveWinner(room: DraftDuoRoom): Promise<void> {
    if (room.winner !== null) return;
    const my = this.myFinalScore();
    const opp = this.opponentFinalScore();
    let winnerValue: 'player1' | 'player2' | 'draw';
    if (my === opp) {
      winnerValue = 'draw';
    } else {
      const iWin = my > opp;
      winnerValue = (this.isPlayer1() ? iWin : !iWin) ? 'player1' : 'player2';
    }
    try {
      await this.supabaseService.updateDraftDuoRoom(this.roomId(), {
        status: 'finished',
        winner: winnerValue,
      });
    } catch { /* silencieux */ }
  }

  // ─── Invitation ──────────────────────────────────────────────────────────────

  /** Retourne le lien d'invitation de la room. */
  get inviteLink(): string {
    return `${window.location.origin}/invite/${this.roomId()}?mode=draft_duo`;
  }

  /** Copie le lien d'invitation dans le presse-papiers. */
  async copyLink(): Promise<void> {
    try {
      await navigator.clipboard.writeText(this.inviteLink);
      this.linkCopied.set(true);
      setTimeout(() => this.linkCopied.set(false), 2000);
    } catch { /* ignore */ }
  }

  // ─── Navigation ──────────────────────────────────────────────────────────────

  /** Navigue vers la page d'accueil. */
  async goHome(): Promise<void> {
    await this.supabaseService.broadcastPlayerLeft().catch(() => {});
    void this.router.navigate(['/home']);
  }

  /** Affiche la confirmation de sortie. */
  promptCancel(): void {
    this.showCancelModal.set(true);
  }

  /** Ferme la confirmation de sortie. */
  closeCancelModal(): void {
    this.showCancelModal.set(false);
  }

  /** Confirme la sortie et termine la room pour l'adversaire. */
  async confirmCancel(): Promise<void> {
    if (this.isCancelling()) return;
    this.isCancelling.set(true);
    await this.supabaseService.broadcastPlayerLeft().catch(() => undefined);
    await this.supabaseService.updateDraftDuoRoom(this.roomId(), {
      status: 'finished',
      winner: null,
      p1_ready: false,
      p2_ready: false,
    }).catch(() => undefined);
    void this.router.navigate(['/home']);
  }

  /** Relance une partie. */
  async replay(): Promise<void> {
    try {
      const patch = this.isPlayer1() ? { p1_ready: true } : { p2_ready: true };
      await this.supabaseService.updateDraftDuoRoom(this.roomId(), patch);

      const refreshed = await this.supabaseService.getDraftDuoRoom(this.roomId());
      this.room.set(refreshed);

      await this.launchReplayIfReady(refreshed);
    } catch { /* silencieux */ }
  }

  private async launchReplayIfReady(room: DraftDuoRoom): Promise<boolean> {
    if (!this.isPlayer1() || this.replayLaunchInProgress) return false;
    if (room.status !== 'finished' || !room.p1_ready || !room.p2_ready) return false;

    this.replayLaunchInProgress = true;
    try {
      await this.supabaseService.updateDraftDuoRoom(this.roomId(), {
        status: 'playing',
        p1_team: [],
        p2_team: [],
        winner: null,
        p1_ready: false,
        p2_ready: false,
      });

      const finalRoom = await this.supabaseService.getDraftDuoRoom(this.roomId());
      await this.onRoomUpdated(finalRoom);
      return true;
    } finally {
      this.replayLaunchInProgress = false;
    }
  }

  /** Reinitialise l'etat local pour une revanche. */
  private resetForReplay(): void {
    this.isLockingPick = false;
    this.enteringComplete = false;
    this.confettiFired = false;
    this.showScores.set(false);
    this.myTeamPokemons.set([]);
    this.opponentTeamPokemons.set([]);
    this.opponentPickCount.set(0);
    this.opponentLockedPokemons.set([]);
  }

  // ─── Calculs scores ──────────────────────────────────────────────────────────

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

  // ─── Helpers UI ─────────────────────────────────────────────────────────────

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

  // ─── Sélection aléatoire ────────────────────────────────────────────────────

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
