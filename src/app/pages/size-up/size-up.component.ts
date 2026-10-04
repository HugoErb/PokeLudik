import { Component, CUSTOM_ELEMENTS_SCHEMA, OnDestroy, OnInit, computed, effect, inject, input, signal } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import confetti from 'canvas-confetti';
import { firstValueFrom, Subscription } from 'rxjs';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import { EndGameActionsComponent } from '../../components/end-game-actions/end-game-actions.component';
import { GameSettingsPanelComponent } from '../../components/game-settings-panel/game-settings-panel.component';
import { HelpCardComponent } from '../../components/help-modal/help-card.component';
import { HelpSectionTitleComponent } from '../../components/help-modal/help-section-title.component';
import { LeaderboardModalComponent } from '../../components/leaderboard-modal/leaderboard-modal.component';
import { ModeSelectCardComponent } from '../../components/mode-select-card/mode-select-card.component';
import { ModeSelectComponent } from '../../components/mode-select-card/mode-select.component';
import { NewRecordBadgeComponent } from '../../components/new-record-badge/new-record-badge.component';
import { SizeUpBoardComponent } from '../../components/size-up-board/size-up-board.component';
import { SoloScoreSummaryComponent } from '../../components/solo-score-summary/solo-score-summary.component';
import { ICONS } from '../../constants/icons';
import { DEFAULT_MODE_SETTINGS, ModeSettings, normalizeModeSettings, toSizeUpSettings } from '../../models/game-settings.model';
import { SoloScoreResult } from '../../models/leaderboard.model';
import { Pokemon } from '../../models/pokemon.model';
import { Profile, SizeUpRoom } from '../../models/room.model';
import { PokemonService } from '../../services/pokemon.service';
import { SupabaseService } from '../../services/supabase.service';
import { buildSettingsKey } from '../../utils/leaderboard-utils';
import { isStaleRoomState } from '../../utils/multiplayer-room-state';
import {
  formatMeters,
  pickSizeUpPairs,
  SIZE_UP_TOTAL_ROUNDS,
  sizeUpErrorFactor,
  sizeUpPoints,
  SizeUpPair,
  SizeUpRoundResult,
} from '../../utils/size-up-utils';
import { measureSpriteBounds } from '../../utils/sprite-bounds';
import { buildWhoPokemonPool } from '../../utils/who-that-pokemon-utils';

type Phase = 'setup' | 'solo' | 'waiting' | 'duo' | 'complete';

/** Manche vue depuis le joueur courant (solo ou duo). */
interface RoundView {
  round: number;
  reference: Pokemon;
  target: Pokemon;
  myGuess: number | null;
  myPoints: number;
  opponentGuess: number | null;
  opponentPoints: number;
}

/** Délai de grâce après la fin du chrono avant que le serveur clôture la manche. */
const DEADLINE_GRACE_MS = 2000;
const FINALIZE_RETRY_MS = 1500;

@Component({
  selector: 'app-size-up',
  imports: [AppHeaderComponent, CancelModalComponent, EndGameActionsComponent, GameSettingsPanelComponent, HelpCardComponent, HelpSectionTitleComponent, LeaderboardModalComponent, ModeSelectCardComponent, ModeSelectComponent, NewRecordBadgeComponent, SizeUpBoardComponent, SoloScoreSummaryComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './size-up.component.html',
  styles: [`
    @keyframes resultIn {
      from { opacity: 0; transform: translateY(8px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .result-in { animation: resultIn 260ms ease-out both; }
  `],
})
export class SizeUpComponent implements OnInit, OnDestroy {
  protected readonly ICONS = ICONS;
  protected readonly totalRounds = SIZE_UP_TOTAL_ROUNDS;
  protected readonly formatMeters = formatMeters;

  readonly roomId = input<string | undefined>();
  private readonly pokemonService = inject(PokemonService);
  private readonly supabaseService = inject(SupabaseService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  readonly phase = signal<Phase>('setup');
  readonly configMode = signal<'solo' | null>(null);
  readonly settings = signal<ModeSettings>({ ...DEFAULT_MODE_SETTINGS.size_up });
  readonly allPokemons = signal<Pokemon[]>([]);
  readonly guess = signal(1);
  readonly feedback = signal('');
  readonly isBusy = signal(false);
  readonly isSubmitting = signal(false);
  readonly showHelpModal = signal(false);
  readonly showCancelModal = signal(false);
  readonly isCancelling = signal(false);
  readonly showLeaderboard = signal(false);
  readonly linkCopied = signal(false);
  readonly opponentLeft = signal(false);
  readonly opponentProfile = signal<Pick<Profile, 'id' | 'username' | 'avatar_url'> | null>(null);
  readonly now = signal(Date.now());

  // Solo
  readonly soloPairs = signal<SizeUpPair[]>([]);
  readonly soloRoundIndex = signal(0);
  readonly soloResults = signal<SizeUpRoundResult[]>([]);
  readonly soloRevealed = signal(false);
  readonly soloDeadline = signal<number | null>(null);
  readonly scoreResult = signal<SoloScoreResult | null>(null);
  readonly scoreSubmitting = signal(false);
  readonly scoreError = signal('');
  private soloRunId: string | null = null;

  // Duo
  readonly room = signal<SizeUpRoom | null>(null);
  readonly isPlayer1 = signal(false);
  private serverOffset = 0;
  private roomSub?: Subscription;
  private broadcastSub?: Subscription;
  private inviteResponseSub?: Subscription;
  private pollInterval?: ReturnType<typeof setInterval>;
  private tickInterval?: ReturnType<typeof setInterval>;
  private autoSubmittedRound = 0;
  private lastFinalizeAttempt = 0;
  private replayLaunchInProgress = false;
  private confettiFired = false;
  private currentRoundKey = '';

  readonly leaderboardKey = computed(() => buildSettingsKey('size_up', toSizeUpSettings(this.settings())));
  private readonly pokemonById = computed(() => new Map(this.allPokemons().map(pokemon => [pokemon.id, pokemon])));

  readonly roundNumber = computed(() => this.room()?.round ?? this.soloRoundIndex() + 1);

  readonly currentPair = computed<SizeUpPair | null>(() => {
    const room = this.room();
    if (room) {
      if (!room.reference_pokemon_id || !room.target_pokemon_id) return null;
      return { referenceId: room.reference_pokemon_id, targetId: room.target_pokemon_id };
    }
    return this.soloPairs()[this.soloRoundIndex()] ?? null;
  });
  readonly reference = computed(() => this.pokemonFor(this.currentPair()?.referenceId));
  readonly target = computed(() => this.pokemonFor(this.currentPair()?.targetId));

  readonly revealed = computed(() => {
    const room = this.room();
    return room ? room.status === 'playing' && room.round_phase === 'reveal' : this.soloRevealed();
  });

  readonly hasSubmitted = computed(() => {
    const room = this.room();
    if (!room) return false;
    return this.isPlayer1() ? room.p1_submitted : room.p2_submitted;
  });
  readonly opponentHasSubmitted = computed(() => {
    const room = this.room();
    if (!room) return false;
    return this.isPlayer1() ? room.p2_submitted : room.p1_submitted;
  });

  readonly locked = computed(() => {
    if (this.revealed()) return true;
    if (this.phase() === 'solo') return false;
    return this.hasSubmitted() || this.room()?.status !== 'playing' || this.isSubmitting();
  });

  readonly canValidate = computed(() => !this.locked() && !!this.reference() && !!this.target());

  readonly history = computed<RoundView[]>(() => {
    const room = this.room();
    if (!room) {
      return this.soloResults().flatMap((result, index) => {
        const reference = this.pokemonFor(result.referenceId);
        const target = this.pokemonFor(result.targetId);
        if (!reference || !target) return [];
        return [{ round: index + 1, reference, target, myGuess: result.guess, myPoints: result.points, opponentGuess: null, opponentPoints: 0 }];
      });
    }
    const p1 = this.isPlayer1();
    return room.history.flatMap(entry => {
      const reference = this.pokemonFor(entry.reference_id);
      const target = this.pokemonFor(entry.target_id);
      if (!reference || !target) return [];
      return [{
        round: entry.round,
        reference,
        target,
        myGuess: p1 ? entry.p1_guess : entry.p2_guess,
        myPoints: p1 ? entry.p1_points : entry.p2_points,
        opponentGuess: p1 ? entry.p2_guess : entry.p1_guess,
        opponentPoints: p1 ? entry.p2_points : entry.p1_points,
      }];
    });
  });

  /** Résultat de la manche en cours, affiché pendant la révélation. */
  readonly currentResult = computed<RoundView | null>(() => {
    if (!this.revealed()) return null;
    return this.history().find(entry => entry.round === this.roundNumber()) ?? null;
  });

  readonly myScore = computed(() => {
    const room = this.room();
    if (!room) return this.soloResults().reduce((total, result) => total + result.points, 0);
    return this.isPlayer1() ? room.p1_score : room.p2_score;
  });
  readonly opponentScore = computed(() => {
    const room = this.room();
    if (!room) return 0;
    return this.isPlayer1() ? room.p2_score : room.p1_score;
  });

  /** Secondes restantes au chrono de la manche, null sans chrono. */
  readonly timeLeft = computed<number | null>(() => {
    if (this.revealed()) return null;
    const deadline = this.roundDeadlineMs();
    if (deadline === null) return null;
    return Math.max(0, Math.ceil((deadline - this.serverNow()) / 1000));
  });
  readonly timerPercent = computed(() => {
    const left = this.timeLeft();
    const total = this.settings().roundTimer;
    if (left === null || total <= 0) return 100;
    return Math.min(100, (left / total) * 100);
  });

  readonly revealTimeLeft = computed<number | null>(() => {
    const room = this.room();
    if (!room?.reveal_until || !this.revealed()) return null;
    return Math.max(0, Math.ceil((new Date(room.reveal_until).getTime() - this.serverNow()) / 1000));
  });

  readonly isVictory = computed(() => {
    const room = this.room();
    if (!room) return false;
    return (room.winner === 'player1' && this.isPlayer1()) || (room.winner === 'player2' && !this.isPlayer1());
  });

  readonly statusTitle = computed(() => {
    const room = this.room();
    if (!room) return 'Partie terminée';
    if (room.winner === 'draw') return 'Égalité !';
    if (!room.winner) return 'Partie interrompue';
    return this.isVictory() ? 'Victoire !' : 'Défaite';
  });

  get inviteLink(): string {
    return `${window.location.origin}/invite/${this.roomId()}?mode=size_up`;
  }

  constructor() {
    // Nouvelle manche : l'estimation repart de la taille du Pokémon de référence.
    effect(() => {
      const pair = this.currentPair();
      const reference = this.reference();
      const key = pair ? `${this.roundNumber()}:${pair.referenceId}:${pair.targetId}` : '';
      if (!pair || !reference || key === this.currentRoundKey) return;
      this.currentRoundKey = key;
      this.guess.set(reference.height);
    });

    effect(() => {
      if (this.phase() !== 'complete') {
        this.confettiFired = false;
        return;
      }
      if (this.isVictory()) setTimeout(() => this.launchConfetti(), 300);
    });
  }

  async ngOnInit(): Promise<void> {
    this.supabaseService.trackPresence(this.roomId() ? 'in_game' : 'online');
    this.allPokemons.set(await firstValueFrom(this.pokemonService.loadAll()));
    this.tickInterval = setInterval(() => this.tick(), 250);
    if (this.roomId()) await this.loadDuoRoom();
  }

  ngOnDestroy(): void {
    this.roomSub?.unsubscribe();
    this.broadcastSub?.unsubscribe();
    this.inviteResponseSub?.unsubscribe();
    if (this.pollInterval) clearInterval(this.pollInterval);
    if (this.tickInterval) clearInterval(this.tickInterval);
  }

  updateGameSettings(settings: ModeSettings): void {
    this.settings.set(settings);
    void this.persistWaitingSettings();
  }

  setGuess(meters: number): void {
    if (!this.locked()) this.guess.set(meters);
  }

  // ── Solo ────────────────────────────────────────────────────────────────

  startSolo(): void {
    const pool = buildWhoPokemonPool(this.allPokemons(), this.settings());
    const pairs = pickSizeUpPairs(pool, SIZE_UP_TOTAL_ROUNDS);
    if (pairs.length < SIZE_UP_TOTAL_ROUNDS) {
      this.feedback.set('Il faut au moins 2 Pokémon correspondant aux filtres.');
      return;
    }
    this.soloPairs.set(pairs);
    this.soloRoundIndex.set(0);
    this.soloResults.set([]);
    this.soloRevealed.set(false);
    this.currentRoundKey = '';
    this.soloRunId = crypto.randomUUID();
    this.scoreResult.set(null);
    this.scoreError.set('');
    this.feedback.set('');
    this.prefetchPairs(pairs);
    this.phase.set('solo');
    this.startSoloTimer();
  }

  nextSoloRound(): void {
    if (!this.soloRevealed()) return;
    const next = this.soloRoundIndex() + 1;
    if (next >= SIZE_UP_TOTAL_ROUNDS) {
      this.finishSolo();
      return;
    }
    this.soloRoundIndex.set(next);
    this.soloRevealed.set(false);
    this.startSoloTimer();
  }

  /** Valide l'estimation courante (bouton ou fin du chrono). */
  async validate(): Promise<void> {
    if (!this.canValidate()) return;
    const pair = this.currentPair();
    const target = this.target();
    if (!pair || !target) return;
    const guess = this.guess();

    if (this.phase() === 'solo') {
      this.soloResults.update(results => [...results, { ...pair, guess, points: sizeUpPoints(guess, target.height) }]);
      this.soloRevealed.set(true);
      this.soloDeadline.set(null);
      return;
    }

    const room = this.room();
    if (!room) return;
    this.isSubmitting.set(true);
    this.feedback.set('');
    try {
      await this.supabaseService.submitSizeUpGuess(room.id, room.round, guess);
      await this.refreshRoom();
    } catch {
      this.feedback.set("Impossible d'envoyer ton estimation pour le moment.");
    } finally {
      this.isSubmitting.set(false);
    }
  }

  private startSoloTimer(): void {
    const seconds = this.settings().roundTimer;
    this.soloDeadline.set(seconds > 0 ? Date.now() + seconds * 1000 : null);
  }

  /** Termine la partie solo et l'enregistre au classement (une seule fois par partie). */
  private finishSolo(): void {
    this.phase.set('complete');
    const runId = this.soloRunId;
    if (!runId) return;
    this.soloRunId = null;
    this.scoreSubmitting.set(true);
    this.scoreError.set('');
    const rounds = this.soloResults().map(result => ({ reference_id: result.referenceId, target_id: result.targetId, guess: result.guess }));
    this.supabaseService.submitSizeUpScore(runId, toSizeUpSettings(this.settings()), rounds)
      .then(result => this.scoreResult.set(result))
      .catch(err => {
        console.error('[SizeUp] Score non enregistré', err);
        this.scoreError.set('Score non enregistré au classement');
      })
      .finally(() => this.scoreSubmitting.set(false));
  }

  // ── Duo ─────────────────────────────────────────────────────────────────

  async createDuoRoom(): Promise<void> {
    if (this.isBusy()) return;
    this.isBusy.set(true);
    try {
      const roomId = await this.supabaseService.createSizeUpRoom(toSizeUpSettings(this.settings()));
      await this.router.navigate(['/lobby', roomId], { queryParams: { mode: 'size_up' } });
    } catch {
      this.feedback.set('Impossible de créer la partie.');
    } finally {
      this.isBusy.set(false);
    }
  }

  async launchDuoGame(): Promise<void> {
    const room = this.room();
    if (!room || !this.isPlayer1() || !room.player2_id || this.isBusy()) return;
    this.isBusy.set(true);
    try {
      await this.supabaseService.startSizeUpGame(room.id, toSizeUpSettings(this.settings()));
      await this.refreshRoom();
      this.feedback.set('');
    } catch {
      this.feedback.set('Impossible de lancer la partie pour le moment.');
    } finally {
      this.isBusy.set(false);
    }
  }

  async replay(): Promise<void> {
    const room = this.room();
    if (!room) {
      this.phase.set('setup');
      this.feedback.set('');
      return;
    }
    this.feedback.set('');
    try {
      const current = await this.supabaseService.getSizeUpRoom(room.id);
      if (current.status !== 'finished') return;
      await this.supabaseService.updateSizeUpRoom(room.id, this.isPlayer1() ? { p1_ready: true } : { p2_ready: true });
      const refreshed = await this.refreshRoom();
      if (refreshed) await this.launchReplayIfReady(refreshed);
    } catch {
      this.feedback.set('Impossible de demander une revanche pour le moment.');
    }
  }

  goHome(): void {
    void this.router.navigate(['/home']);
  }

  handleQuit(): void {
    if (this.room()) {
      this.showCancelModal.set(true);
      return;
    }
    this.goHome();
  }

  async confirmCancel(): Promise<void> {
    this.isCancelling.set(true);
    await this.supabaseService.broadcastPlayerLeft().catch(() => undefined);
    const room = this.room();
    if (room) {
      await this.supabaseService.updateSizeUpRoom(room.id, { status: 'finished', winner: null, p1_ready: false, p2_ready: false }).catch(() => undefined);
    }
    void this.router.navigate(['/home']);
  }

  async copyLink(): Promise<void> {
    await navigator.clipboard.writeText(this.inviteLink);
    this.linkCopied.set(true);
    setTimeout(() => this.linkCopied.set(false), 2000);
  }

  errorFactorLabel(guess: number | null, actual: number): string {
    if (guess === null) return 'Pas de réponse';
    const factor = sizeUpErrorFactor(guess, actual);
    if (factor < 1.005) return 'Parfait !';
    const direction = guess > actual ? 'trop grand' : 'trop petit';
    return `×${factor.toFixed(2).replace('.', ',')} ${direction}`;
  }

  private serverNow(): number {
    return this.now() + (this.room() ? this.serverOffset : 0);
  }

  private roundDeadlineMs(): number | null {
    const room = this.room();
    if (!room) return this.phase() === 'solo' ? this.soloDeadline() : null;
    return room.status === 'playing' && room.round_deadline ? new Date(room.round_deadline).getTime() : null;
  }

  /** Horloge commune : chrono solo, auto-validation et clôture des manches duo. */
  private tick(): void {
    this.now.set(Date.now());
    const phase = this.phase();
    if (phase === 'solo') {
      const deadline = this.soloDeadline();
      if (deadline !== null && !this.soloRevealed() && Date.now() >= deadline) void this.validate();
      return;
    }

    const room = this.room();
    if (phase !== 'duo' || !room || room.status !== 'playing') return;
    const serverNow = this.serverNow();

    if (room.round_phase === 'guessing') {
      const deadline = this.roundDeadlineMs();
      if (deadline === null) return;
      if (serverNow >= deadline && !this.hasSubmitted() && this.autoSubmittedRound !== room.round && !this.isSubmitting()) {
        this.autoSubmittedRound = room.round;
        void this.validate();
      }
      if (serverNow >= deadline + DEADLINE_GRACE_MS) void this.tryFinalize(room);
      return;
    }

    if (room.reveal_until && serverNow >= new Date(room.reveal_until).getTime()) void this.tryFinalize(room);
  }

  /** Demande au serveur de clôturer la manche ; il ne fait rien si le délai n'est pas écoulé. */
  private async tryFinalize(room: SizeUpRoom): Promise<void> {
    if (Date.now() - this.lastFinalizeAttempt < FINALIZE_RETRY_MS) return;
    this.lastFinalizeAttempt = Date.now();
    try {
      await this.supabaseService.finalizeSizeUpRound(room.id, room.round);
      await this.refreshRoom();
    } catch {
      // Nouvelle tentative au prochain tick.
    }
  }

  private async loadDuoRoom(): Promise<void> {
    const roomId = this.roomId()!;
    const user = this.supabaseService.getCurrentUser();
    if (!user) {
      void this.router.navigate(['/login']);
      return;
    }
    const [room, offset] = await Promise.all([
      this.supabaseService.getSizeUpRoom(roomId),
      this.supabaseService.getServerClockOffset(),
    ]);
    this.serverOffset = offset;
    this.isPlayer1.set(room.player1_id === user.id);
    this.applyRoom(room);
    await this.loadOpponentProfile(room);

    this.roomSub = this.supabaseService.subscribeToSizeUpRoom(roomId).subscribe(updated => this.applyRoom(updated));
    this.pollInterval = setInterval(() => void this.refreshRoom(), 2000);
    this.broadcastSub = this.supabaseService.broadcastEvents$.subscribe(({ event }) => {
      if (event !== 'player_left') return;
      if (this.phase() === 'complete') {
        this.opponentLeft.set(true);
        return;
      }
      void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
    });

    const inviteId = this.route.snapshot.queryParamMap.get('inviteId');
    const friendName = this.route.snapshot.queryParamMap.get('friendName') ?? 'Ton ami';
    if (inviteId) {
      this.inviteResponseSub = this.supabaseService.subscribeToGameInviteResponse(inviteId).subscribe(invite => {
        if (invite.status === 'declined') void this.router.navigate(['/home'], { queryParams: { declined: friendName } });
      });
    }
  }

  private async refreshRoom(): Promise<SizeUpRoom | null> {
    const roomId = this.roomId();
    if (!roomId) return null;
    try {
      const room = await this.supabaseService.getSizeUpRoom(roomId);
      this.applyRoom(room);
      return room;
    } catch {
      return null;
    }
  }

  private applyRoom(room: SizeUpRoom): void {
    if (isStaleRoomState(this.room(), room)) return;
    const previous = this.room();
    this.room.set(room);
    this.settings.set(normalizeModeSettings('size_up', room.settings));

    if (room.status === 'finished' && room.winner === null) {
      if (previous?.status === 'playing' && this.phase() !== 'complete') {
        void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
        return;
      }
      if (this.phase() === 'complete') this.opponentLeft.set(true);
    }
    if (room.status === 'playing') this.opponentLeft.set(false);
    if (room.status === 'waiting') void this.loadOpponentProfile(room);
    if (room.status === 'playing' && previous?.round !== room.round) this.prefetchCurrentRoom(room);

    this.phase.set(room.status === 'waiting' ? 'waiting' : room.status === 'playing' ? 'duo' : 'complete');
    void this.launchReplayIfReady(room);
  }

  private async persistWaitingSettings(): Promise<void> {
    const room = this.room();
    if (!room || !this.isPlayer1() || room.status !== 'waiting') return;
    await this.supabaseService.updateSizeUpRoom(room.id, { settings: toSizeUpSettings(this.settings()) }).catch(() => undefined);
  }

  private async launchReplayIfReady(room: SizeUpRoom): Promise<void> {
    if (!this.isPlayer1() || this.replayLaunchInProgress || room.status !== 'finished' || !room.p1_ready || !room.p2_ready) return;
    this.replayLaunchInProgress = true;
    try {
      await this.supabaseService.startSizeUpGame(room.id, toSizeUpSettings(this.settings()));
      await this.refreshRoom();
    } catch {
      this.feedback.set('Impossible de relancer la partie pour le moment.');
    } finally {
      this.replayLaunchInProgress = false;
    }
  }

  private async loadOpponentProfile(room: SizeUpRoom): Promise<void> {
    const opponentId = this.isPlayer1() ? room.player2_id : room.player1_id;
    if (!opponentId) {
      this.opponentProfile.set(null);
      return;
    }
    if (this.opponentProfile()?.id === opponentId) return;
    try {
      const profile = await this.supabaseService.getProfile(opponentId);
      this.opponentProfile.set({ id: profile.id, username: profile.username, avatar_url: profile.avatar_url });
    } catch {
      this.opponentProfile.set({ id: opponentId, username: 'Adversaire', avatar_url: undefined });
    }
  }

  private pokemonFor(id: number | null | undefined): Pokemon | null {
    return id ? this.pokemonById().get(id) ?? null : null;
  }

  /** Précharge et mesure les sprites pour que chaque manche s'affiche sans attente. */
  private prefetchPairs(pairs: SizeUpPair[]): void {
    const urls = pairs.flatMap(pair => [this.pokemonFor(pair.referenceId)?.sprite, this.pokemonFor(pair.targetId)?.sprite])
      .filter((url): url is string => !!url);
    // Même requête CORS que le plateau : le cache du navigateur est partagé.
    urls.forEach(url => void measureSpriteBounds(url));
  }

  private prefetchCurrentRoom(room: SizeUpRoom): void {
    if (room.reference_pokemon_id && room.target_pokemon_id) {
      this.prefetchPairs([{ referenceId: room.reference_pokemon_id, targetId: room.target_pokemon_id }]);
    }
  }

  private launchConfetti(): void {
    if (this.confettiFired) return;
    this.confettiFired = true;
    const colors = ['#10b981', '#facc15', '#38bdf8', '#a855f7', '#ffffff'];
    confetti({ particleCount: 160, spread: 110, origin: { x: 0.5, y: 0.4 }, colors });
  }
}
