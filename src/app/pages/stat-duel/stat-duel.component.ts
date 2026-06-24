import { Component, OnInit, OnDestroy, CUSTOM_ELEMENTS_SCHEMA, inject, signal, computed } from '@angular/core';
import confetti from 'canvas-confetti';
import { NgClass } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';
import { PokemonService } from '../../services/pokemon.service';
import { SupabaseService } from '../../services/supabase.service';
import { Pokemon } from '../../models/pokemon.model';
import { StatDuelRoom, StatPick } from '../../models/room.model';
import { ICONS } from '../../constants/icons';
import { DuelIntroComponent } from '../../components/duel-intro/duel-intro.component';
import { ModeSelectCardComponent } from '../../components/mode-select-card/mode-select-card.component';
import { ModeSelectComponent } from '../../components/mode-select-card/mode-select.component';
import { HelpModalComponent } from '../../components/help-modal/help-modal.component';
import { EndGameActionsComponent } from '../../components/end-game-actions/end-game-actions.component';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import { environment } from '../../../environments/environment';
import { GameSettingsPanelComponent } from '../../components/game-settings-panel/game-settings-panel.component';
import { DEFAULT_MODE_SETTINGS, ModeSettings, normalizeModeSettings, toGuessSettings } from '../../models/game-settings.model';
import { shouldRevealStatDuelRound } from '../../utils/stat-duel-sync';

type Phase = 'mode-select' | 'waiting' | 'playing' | 'result';
type StatConfigMode = 'solo';

interface StatDef {
    key: keyof Pokemon['stats'];
    label: string;
    colorClass: string;
    bgClass: string;
}

const STAT_DEFS: StatDef[] = [
    { key: 'pv', label: 'PV', colorClass: 'text-green-400', bgClass: 'bg-green-500' },
    { key: 'attaque', label: 'ATQ', colorClass: 'text-red-400', bgClass: 'bg-red-500' },
    { key: 'defense', label: 'DEF', colorClass: 'text-blue-400', bgClass: 'bg-blue-500' },
    { key: 'atq_spe', label: 'ATQ S', colorClass: 'text-purple-400', bgClass: 'bg-purple-500' },
    { key: 'def_spe', label: 'DEF S', colorClass: 'text-pink-400', bgClass: 'bg-pink-500' },
    { key: 'vitesse', label: 'VIT', colorClass: 'text-yellow-400', bgClass: 'bg-yellow-500' },
];

const ROUND_COUNT = 6;
const ROUND_PICK_TIME_MS = 10_000;
const ROUND_TRANSITION_TIME_MS = 5_000;
const ROUND_DURATION_MS = ROUND_PICK_TIME_MS + ROUND_TRANSITION_TIME_MS;

@Component({
    selector: 'app-stat-duel',
    standalone: true,
    imports: [NgClass, DuelIntroComponent, ModeSelectCardComponent, ModeSelectComponent, HelpModalComponent, EndGameActionsComponent, AppHeaderComponent, CancelModalComponent, GameSettingsPanelComponent],
    schemas: [CUSTOM_ELEMENTS_SCHEMA],
    templateUrl: './stat-duel.component.html',
    styles: [`
    @keyframes statPop {
      0%   { transform: scale(0.4); opacity: 0; }
      60%  { transform: scale(1.2); opacity: 1; }
      100% { transform: scale(1); }
    }
    .stat-pop { animation: statPop 0.3s cubic-bezier(0.34, 1.56, 0.64, 1) forwards; }

    @keyframes pokemonAppear {
      0%   { opacity: 0; transform: scale(0.75) translateY(14px); }
      65%  { transform: scale(1.04) translateY(-2px); }
      100% { opacity: 1; transform: scale(1) translateY(0); }
    }
    .pokemon-appear { animation: pokemonAppear 0.45s cubic-bezier(0.34, 1.56, 0.64, 1) forwards; }
  `],
})
export class StatDuelComponent implements OnInit, OnDestroy {
    protected readonly ICONS = ICONS;
    protected readonly STAT_DEFS = STAT_DEFS;
    protected readonly isDevEnv = environment.devMode;
    protected readonly ROUND_COUNT = ROUND_COUNT;
    protected readonly INDICES = [0, 1, 2, 3, 4, 5];

    private readonly route = inject(ActivatedRoute);
    private readonly router = inject(Router);
    private readonly pokemonService = inject(PokemonService);
    private readonly supabaseService = inject(SupabaseService);

    // --- Phase & mode ------------------------------------------------------------
    phase = signal<Phase>('mode-select');
    statConfigMode = signal<StatConfigMode | null>(null);
    isSolo = signal(true);
    isDevMode = signal(false);
    isPlayer1 = signal(false);
    roomId: string | null = null;
    settings = signal<ModeSettings>({ ...DEFAULT_MODE_SETTINGS.stat_duel });

    // Game state
    pokemonList = signal<Pokemon[]>([]);
    currentRound = signal(0);
    timerValue = signal(10);
    timerProgress = signal(10);
    justPickedStat = signal<StatPick | null>(null);
    myPicks = signal<StatPick[]>([]);
    opponentPicks = signal<StatPick[]>([]);
    room = signal<StatDuelRoom | null>(null);
    revealedRound = signal(-1);
    waitingForReveal = signal(false);
    pendingMyPickStat = signal<string | null>(null);
    justRevealedOpponentPick = signal<StatPick | null>(null);
    nextRoundCountdown = signal<number | null>(null);

    // --- Computed ----------------------------------------------------------------
    currentPokemon = computed(() => this.pokemonList()[this.currentRound()] ?? null);
    pickedStatKeys = computed(() => new Set(this.myPicks().map(p => p.stat)));
    hasPickedThisRound = computed(() => this.myPicks().length > this.currentRound());
    myTotal = computed(() => this.myPicks().reduce((s, p) => s + p.value, 0));
    opponentTotal = computed(() => this.opponentPicks().reduce((s, p) => s + p.value, 0));
    myRevealedPicks = computed(() => this.myPicks().slice(0, this.revealedRound() + 1));
    opponentRevealedPicks = computed(() => this.opponentPicks().slice(0, this.revealedRound() + 1));
    isCurrentRoundRevealed = computed(() => this.revealedRound() >= this.currentRound());
    myRevealedTotal = computed(() => this.myRevealedPicks().reduce((s, p) => s + p.value, 0));
    opponentRevealedTotal = computed(() => this.opponentRevealedPicks().reduce((s, p) => s + p.value, 0));
    opponentLeft = signal(false);

    // --- Timer -------------------------------------------------------------------
    private clockInterval: ReturnType<typeof setInterval> | null = null;
    private roundStartTime = 0;

    // --- Abonnements -------------------------------------------------------------
    private roomSub?: Subscription;
    private inviteResponseSub?: Subscription;
    private broadcastSub?: Subscription;
    private waitingPollInterval: ReturnType<typeof setInterval> | null = null;

    // --- Dev mode bot ------------------------------------------------------------
    private botPickedRounds = new Set<number>();

    // Pokemon animation
    pokemonVisible = signal(false);
    pokemonAnimating = signal(false);
    private readonly ANIMATION_DURATION_MS = 450;

    // --- Duel intro --------------------------------------------------------------
    showDuelIntro = signal(false);
    duelPlayer1 = signal<{ username: string; avatar_url?: string } | null>(null);
    duelPlayer2 = signal<{ username: string; avatar_url?: string } | null>(null);
    private duelShown = false;

    // --- Replay state ------------------------------------------------------------
    iWantReplay = computed(() => {
        const r = this.room();
        if (!r) return false;
        return this.isPlayer1() ? r.p1_ready : r.p2_ready;
    });
    opponentWantsReplay = computed(() => {
        const r = this.room();
        if (!r) return false;
        return this.isPlayer1() ? r.p2_ready : r.p1_ready;
    });

    // --- UI state ----------------------------------------------------------------
    showHelpModal = signal(false);
    statsExpanded = signal(false);
    showCancelModal = signal(false);
    isCancelling = signal(false);

    // --- Partage lien ------------------------------------------------------------
    inviteLink = '';
    linkCopied = signal(false);
    private preloadedImages: HTMLImageElement[] = [];

    // --- Type colors map ---------------------------------------------------------
    protected readonly TYPE_COLORS: Record<string, string> = {
        'Normal': 'bg-gray-400', 'Feu': 'bg-orange-500', 'Eau': 'bg-blue-500',
        'Électrik': 'bg-yellow-400', 'Plante': 'bg-green-500', 'Glace': 'bg-cyan-400',
        'Combat': 'bg-red-700', 'Poison': 'bg-purple-500', 'Sol': 'bg-yellow-600',
        'Vol': 'bg-indigo-400', 'Psy': 'bg-pink-500', 'Insecte': 'bg-lime-500',
        'Roche': 'bg-yellow-700', 'Spectre': 'bg-violet-700', 'Dragon': 'bg-indigo-600',
        'Ténèbres': 'bg-gray-700', 'Acier': 'bg-slate-400', 'Fée': 'bg-pink-300',
    };

    // --- Animation & Effects --------------------------------------------------
    private confettiFired = false;
    private replayLaunchInProgress = false;


    /** Lifecycle Angular : initialise le composant. */
    ngOnInit(): void {
        this.supabaseService.trackPresence('in_game');
        this.roomId = this.route.snapshot.paramMap.get('roomId');
        if (this.route.snapshot.queryParams['dev'] === '1') {
            this.isDevMode.set(true);
        }
        if (this.roomId) {
            this.isSolo.set(false);
            this.phase.set('waiting');
            void this.initMulti(this.roomId);

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
                    if (this.phase() === 'result') {
                        this.opponentLeft.set(true);
                        return;
                    }
                    void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
                }
            });
        }
    }

    /** Lifecycle Angular : nettoie les abonnements et timers du composant. */
    ngOnDestroy(): void {
        this.stopClock();
        this.roomSub?.unsubscribe();
        this.inviteResponseSub?.unsubscribe();
        this.broadcastSub?.unsubscribe();
        this.stopWaitingPoll();
    }

    /** Lance l'animation de confettis. */
    private launchConfetti(): void {
        if (this.confettiFired) return;
        this.confettiFired = true;
        const colors = ['#ef4444', '#facc15', '#a855f7', '#3b82f6', '#ffffff'];
        confetti({ particleCount: 160, spread: 110, origin: { x: 0.5, y: 0.4 }, colors });
    }

    // --- Mode select -------------------------------------------------------------

    /** Demarre une partie solo. */
    async startSolo(): Promise<void> {
        this.isSolo.set(true);
        const allPokemon = this.getConfiguredPokemonPool(await this.loadAll());
        const list = this.shuffle(allPokemon).slice(0, ROUND_COUNT);
        this.pokemonList.set(list);
        this.preloadImages(list);
        this.myPicks.set([]);
        this.currentRound.set(0);
        this.phase.set('playing');
        this.startPokemonAnimation(() => this.startSoloClock());
    }

    selectStatConfigMode(mode: StatConfigMode): void {
        this.statConfigMode.set(mode);
    }

    /** Cree une room multijoueur. */
    async createMultiRoom(): Promise<void> {
        const roomId = await this.supabaseService.createStatDuelRoom();
        void this.router.navigate(['/lobby', roomId], { queryParams: { mode: 'stat_duel' } });
    }

    /** Demarre le mode developpement. */
    async startDevMode(): Promise<void> {
        const roomId = await this.supabaseService.createStatDuelRoom();
        await this.supabaseService.updateStatDuelRoom(roomId, { settings: toGuessSettings(this.settings()) });
        void this.router.navigate(['/stat-duel', roomId], { queryParams: { dev: '1' } });
    }

    updateGameSettings(settings: ModeSettings): void {
        this.settings.set(settings);
    }

    // --- Multi init --------------------------------------------------------------

    /** Initialise une partie multijoueur. */
    private async initMulti(roomId: string): Promise<void> {
        const me = this.supabaseService.getCurrentUser();
        if (!me) return;

        this.inviteLink = `${window.location.origin}/invite/${roomId}?mode=stat_duel`;

        const room = await this.supabaseService.getStatDuelRoom(roomId);
        this.room.set(room);
        this.settings.set(normalizeModeSettings('stat_duel', room.settings));
        if (room.status === 'finished' && room.winner === null) {
            void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
            return;
        }
        this.isPlayer1.set(room.player1_id === me.id);
        void this.launchReplayIfReady(room);

        // Rejoindre en tant que P2 si la place est libre et qu'on n'est pas P1
        if (!room.player2_id && room.player1_id !== me.id) {
            await this.supabaseService.joinStatDuelRoom(roomId);
            const refreshed = await this.supabaseService.getStatDuelRoom(roomId);
            this.room.set(refreshed);
        }

        if (room.status === 'playing' || room.status === 'finished') {
            await this.loadPokemonAndStartMulti(room);
            if (room.status === 'finished') this.phase.set('result');
        }

        this.roomSub = this.supabaseService.subscribeToStatDuelRoom(roomId).subscribe(async (updated) => {
            this.room.set(updated);
            this.settings.set(normalizeModeSettings('stat_duel', updated.settings));
            if (updated.status === 'finished' && updated.winner === null) {
                if (this.phase() === 'result') {
                    this.stopClock();
                    this.opponentLeft.set(true);
                    return;
                }
                this.stopClock();
                void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
                return;
            }
            if (await this.launchReplayIfReady(updated)) return;
            if (updated.player2_id) this.stopWaitingPoll();

            if (updated.status === 'finished') {
                if (this.phase() !== 'result') {
                    this.endMultiGame(updated);
                } else {
                    this.maybeFireMultiConfetti(updated);
                }
            }

            if (updated.status === 'playing' && (this.phase() === 'waiting' || this.phase() === 'result')) {
                this.resetGameState();
                await this.loadPokemonAndStartMulti(updated);
            }

            if (updated.status === 'playing' && this.phase() === 'playing') {
                const me2 = this.supabaseService.getCurrentUser();
                if (!me2) return;
                const isP1 = updated.player1_id === me2.id;
                // Do not overwrite local state if DB updates lag behind (appendStatPick race)
                const dbMyPicks = isP1 ? updated.p1_picks : updated.p2_picks;
                if (dbMyPicks.length >= this.myPicks().length) {
                    this.myPicks.set(dbMyPicks);
                }
                this.opponentPicks.set(isP1 ? updated.p2_picks : updated.p1_picks);

                // Simultaneous reveal: as soon as both players picked, reveal
                if (shouldRevealStatDuelRound(this.myPicks().length, this.opponentPicks().length, this.currentRound(), this.revealedRound())) {
                    this.triggerReveal();
                }

                if (updated.p1_picks.length === ROUND_COUNT && updated.p2_picks.length === ROUND_COUNT) {
                    this.endMultiGame(updated);
                }
            }
        });

        this.startWaitingPoll(roomId);
    }

    /** Demarre le polling d'attente. */
    private startWaitingPoll(roomId: string): void {
        this.waitingPollInterval = setInterval(async () => {
            if (this.phase() !== 'waiting') {
                this.stopWaitingPoll();
                return;
            }
            const refreshed = await this.supabaseService.getStatDuelRoom(roomId);

            if (refreshed.status === 'finished' && refreshed.winner === null) {
                this.room.set(refreshed);
                void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
                return;
            }

            if (!this.room()?.player2_id && refreshed.player2_id) {
                this.room.set(refreshed);
            }

            if (refreshed.status === 'playing' && this.phase() === 'waiting') {
                this.room.set(refreshed);
                await this.loadPokemonAndStartMulti(refreshed);
            }
        }, 3000);
    }

    /** Arrete le polling d'attente. */
    private stopWaitingPoll(): void {
        if (this.waitingPollInterval) {
            clearInterval(this.waitingPollInterval);
            this.waitingPollInterval = null;
        }
    }

    /** Charge les Pokemon puis demarre la partie multijoueur. */
    private async loadPokemonAndStartMulti(room: StatDuelRoom): Promise<void> {
        if (this.phase() === 'playing') return;
        const allPokemon = await this.loadAll();
        const pokemonMap = new Map(allPokemon.map(p => [p.id, p]));
        const list = room.pokemon_ids.map(id => pokemonMap.get(id)).filter((p): p is Pokemon => !!p);
        this.pokemonList.set(list);
        this.preloadImages(list);

        const me = this.supabaseService.getCurrentUser();
        if (!me) return;
        const isP1 = room.player1_id === me.id;
        this.myPicks.set(isP1 ? room.p1_picks : room.p2_picks);
        this.opponentPicks.set(isP1 ? room.p2_picks : room.p1_picks);

        // On reconnect mid-game, completed rounds are already revealed
        const completedRounds = Math.min(room.p1_picks.length, room.p2_picks.length) - 1;
        this.revealedRound.set(completedRounds);

        this.phase.set('playing');
        void this.triggerDuelIntro(room);
        if (this.isDevMode()) {
            this.botPickedRounds.clear();
            const delayFromNow = Math.max(0, new Date(room.round_start_at!).getTime() - Date.now());
            setTimeout(() => {
                if (this.phase() !== 'playing') return;
                this.startPokemonAnimation(() => this.startMultiPickClock());
            }, delayFromNow);
            return;
        }

        this.startMultiClock(room.round_start_at!);
    }

    // --- Lancer la partie multi (P1) ---------------------------------------------

    protected isLaunching = signal(false);

    /** Lance une partie multijoueur. */
    async launchMultiGame(): Promise<void> {
        if (this.isLaunching() || !this.roomId) return;
        const currentRoom = this.room();
        if (!currentRoom) return;

        this.isLaunching.set(true);
        try {
            const allPokemon = this.getConfiguredPokemonPool(await this.loadAll(), currentRoom.settings);
            const pokemonIds = this.shuffle(allPokemon).slice(0, ROUND_COUNT).map(p => p.id);
            // Delay round start until the VS animation has finished
            const roundStartAt = new Date(Date.now() + 3000).toISOString();

            await this.supabaseService.updateStatDuelRoom(this.roomId, {
                status: 'playing',
                settings: toGuessSettings(normalizeModeSettings('stat_duel', currentRoom.settings ?? this.settings())),
                pokemon_ids: pokemonIds,
                round_start_at: roundStartAt,
            });

            // P1 moves forward locally because the subscription does not always echo
            // changes back to the client that emitted them (Supabase realtime behavior)
            await this.loadPokemonAndStartMulti({
                ...currentRoom,
                status: 'playing',
                pokemon_ids: pokemonIds,
                round_start_at: roundStartAt,
                p1_picks: [],
                p2_picks: [],
            });
        } finally {
            this.isLaunching.set(false);
        }
    }

    // --- Horloges ----------------------------------------------------------------

    /** Demarre le chronometre solo. */
    private startSoloClock(): void {
        this.stopClock();
        this.nextRoundCountdown.set(null);
        this.roundStartTime = Date.now();
        this.timerValue.set(10);
        this.timerProgress.set(10);
        this.clockInterval = setInterval(() => {
            const elapsed = Date.now() - this.roundStartTime;
            const remainingFloat = Math.max(0, ROUND_PICK_TIME_MS / 1000 - elapsed / 1000);
            const remaining = Math.ceil(remainingFloat);
            this.timerValue.set(remaining);
            this.timerProgress.set(remainingFloat);
            if (remaining <= 0 && !this.hasPickedThisRound()) {
                this.autoPickStat();
            }
        }, 200);
    }

    /** Demarre la transition entre deux manches solo. */
    private startSoloTransition(): void {
        this.stopClock();
        const startTime = Date.now();
        this.clockInterval = setInterval(() => {
            const elapsed = Date.now() - startTime;
            const remaining = Math.max(0, (ROUND_TRANSITION_TIME_MS - elapsed) / 1000);
            this.nextRoundCountdown.set(Math.ceil(remaining));
            if (remaining <= 0) {
                this.stopClock();
                this.nextRoundCountdown.set(null);
                this.advanceSoloRound();
            }
        }, 200);
    }

    /** Demarre le chronometre de choix multijoueur. */
    private startMultiPickClock(): void {
        this.stopClock();
        this.nextRoundCountdown.set(null);
        this.roundStartTime = Date.now();
        this.timerValue.set(10);
        this.timerProgress.set(10);
        if (this.isDevMode()) {
            this.scheduleBotPick(this.currentRound());
        }
        this.clockInterval = setInterval(() => {
            const elapsed = Date.now() - this.roundStartTime;
            const remainingFloat = Math.max(0, ROUND_PICK_TIME_MS / 1000 - elapsed / 1000);
            const remaining = Math.ceil(remainingFloat);
            this.timerValue.set(remaining);
            this.timerProgress.set(remainingFloat);

            if (remaining <= 0) {
                if (!this.hasPickedThisRound()) {
                    this.autoPickStat();
                } else if (shouldRevealStatDuelRound(this.myPicks().length, this.opponentPicks().length, this.currentRound(), this.revealedRound())) {
                    this.triggerReveal();
                }
            }
        }, 200);
    }

    /** Demarre la transition entre deux manches multijoueur. */
    private startMultiTransition(): void {
        this.stopClock();
        const startTime = Date.now();
        this.nextRoundCountdown.set(Math.ceil(ROUND_TRANSITION_TIME_MS / 1000));
        this.timerValue.set(0);
        this.timerProgress.set(0);
        this.clockInterval = setInterval(() => {
            const elapsed = Date.now() - startTime;
            const remaining = Math.max(0, (ROUND_TRANSITION_TIME_MS - elapsed) / 1000);
            this.nextRoundCountdown.set(Math.ceil(remaining));
            if (remaining <= 0) {
                this.stopClock();
                this.nextRoundCountdown.set(null);
                this.currentRound.update(round => round + 1);
                this.startPokemonAnimation(() => this.startMultiPickClock());
            }
        }, 200);
    }

    /** Demarre le chronometre multijoueur. */
    private startMultiClock(roundStartAt: string): void {
        this.stopClock();
        const startMs = new Date(roundStartAt).getTime();

        // Initialize prevRound from current state to avoid startup flicker
        const initialElapsed = Date.now() - startMs;
        let prevRound = initialElapsed < 0 ? -1 : Math.floor(initialElapsed / ROUND_DURATION_MS);

        // S'assurer que currentRound est correct avant de commencer l'intervalle
        if (initialElapsed >= 0) {
            this.currentRound.set(Math.min(Math.max(0, prevRound), ROUND_COUNT - 1));
        }

        this.clockInterval = setInterval(() => {
            const now = Date.now();
            const elapsed = now - startMs;

            if (elapsed < 0) {
                this.timerValue.set(10);
                this.timerProgress.set(10);
                this.nextRoundCountdown.set(null);
                return;
            }

            const round = Math.min(Math.floor(elapsed / ROUND_DURATION_MS), ROUND_COUNT - 1);
            const elapsedInRound = elapsed % ROUND_DURATION_MS;

            const remainingPick = Math.max(0, (ROUND_PICK_TIME_MS - elapsedInRound) / 1000);
            const remainingTransition = Math.max(0, (ROUND_DURATION_MS - elapsedInRound) / 1000);

            // Timer and countdown handling
            if (elapsedInRound > ROUND_PICK_TIME_MS) {
                this.nextRoundCountdown.set(Math.ceil(remainingTransition));
                this.timerValue.set(0);
                this.timerProgress.set(0);
            } else {
                this.nextRoundCountdown.set(null);
                this.timerValue.set(Math.ceil(remainingPick));
                this.timerProgress.set(remainingPick);
            }

            // Changement de manche
            if (round !== prevRound) {
                // If we missed rounds (lag/background), catch up auto-picks
                if (prevRound >= 0 && round > prevRound) {
                    for (let r = prevRound; r < round; r++) {
                        if (this.myPicks().length <= r) {
                            // We could auto-pick here for missed rounds
                            // But pickStat depends on currentRound, so it is tricky.
                        }
                    }
                }

                if (prevRound >= 0 && shouldRevealStatDuelRound(this.myPicks().length, this.opponentPicks().length, prevRound, this.revealedRound())) {
                    this.triggerReveal();
                }

                // Animate only when we actually advance
                if (round > prevRound) {
                    this.startPokemonAnimation();
                    this.currentRound.set(round);
                }

                prevRound = round;
            }

            // Auto-pick at the end of the pick window
            if (remainingPick <= 0 && elapsedInRound <= ROUND_PICK_TIME_MS + 200) {
                if (this.myPicks().length <= round) {
                    this.autoPickStat();
                } else if (shouldRevealStatDuelRound(this.myPicks().length, this.opponentPicks().length, round, this.revealedRound())) {
                    this.triggerReveal();
                }
            }

            // Fin du jeu
            if (elapsed >= ROUND_COUNT * ROUND_DURATION_MS) {
                this.stopClock();
                if (!this.isSolo() && this.phase() === 'playing') {
                    const r = this.room();
                    if (r && r.p1_picks.length === ROUND_COUNT && r.p2_picks.length === ROUND_COUNT) {
                        this.endMultiGame(r);
                    }
                }
            }
        }, 200);
    }


    /** Arrete le chronometre en cours. */
    private stopClock(): void {
        if (this.clockInterval) {
            clearInterval(this.clockInterval);
            this.clockInterval = null;
        }
    }

    /** Declenche la revelation du Pokemon courant. */
    private triggerReveal(): void {
        const round = this.currentRound();
        if (!shouldRevealStatDuelRound(this.myPicks().length, this.opponentPicks().length, round, this.revealedRound())) return;

        this.waitingForReveal.set(false);
        this.pendingMyPickStat.set(null);
        this.revealedRound.set(round);
        const myPick = this.myPicks()[round];
        if (myPick) this.justPickedStat.set(myPick);
        const opPick = this.opponentPicks()[round];
        if (opPick) this.justRevealedOpponentPick.set(opPick);
        setTimeout(() => {
            this.justPickedStat.set(null);
            this.justRevealedOpponentPick.set(null);
        }, 2000);

        const bothPicked = this.myPicks().length > round && this.opponentPicks().length > round;
        if (bothPicked) {
            if (round >= ROUND_COUNT - 1) {
                setTimeout(() => {
                    if (this.phase() !== 'playing') return;
                    const currentRoom = this.room();
                    if (!currentRoom) return;
                    const completedRoom: StatDuelRoom = {
                        ...currentRoom,
                        p1_picks: this.isPlayer1() ? this.myPicks() : this.opponentPicks(),
                        p2_picks: this.isPlayer1() ? this.opponentPicks() : this.myPicks(),
                    };
                    this.endMultiGame(completedRoom);
                }, 2000);
                return;
            }

            this.startMultiTransition();
        }
    }

    // --- Pick stat ---------------------------------------------------------------

    /** Selectionne une statistique pour la manche courante. */
    pickStat(statKey: keyof Pokemon['stats']): void {
        if (this.hasPickedThisRound()) return;
        const pokemon = this.currentPokemon();
        if (!pokemon) return;

        const pick: StatPick = { stat: statKey, value: pokemon.stats[statKey] };
        this.myPicks.update(arr => [...arr, pick]);

        if (this.isSolo()) {
            this.stopClock();
            this.justPickedStat.set(pick);
            setTimeout(() => {
                this.justPickedStat.set(null);
                this.startSoloTransition();
            }, 1000);
        } else {
            const me = this.supabaseService.getCurrentUser();
            if (!me || !this.roomId) return;
            const isP1 = this.room()?.player1_id === me.id;
            this.pendingMyPickStat.set(statKey);
            this.waitingForReveal.set(true);
            void this.supabaseService.appendStatPick(this.roomId, isP1 ? 'p1_picks' : 'p2_picks', pick);
            // If the opponent already picked, reveal immediately
            if (shouldRevealStatDuelRound(this.myPicks().length, this.opponentPicks().length, this.currentRound(), this.revealedRound())) {
                this.triggerReveal();
            }
        }
    }

    /** Selectionne automatiquement une statistique disponible. */
    private autoPickStat(): void {
        const available = STAT_DEFS.map(s => s.key).filter(k => !this.pickedStatKeys().has(k));
        if (available.length === 0) return;
        const randomKey = available[Math.floor(Math.random() * available.length)];
        this.pickStat(randomKey);
    }

    // --- Avancer (solo) ----------------------------------------------------------

    /** Passe a la manche solo suivante. */
    private advanceSoloRound(): void {
        const next = this.currentRound() + 1;
        if (next >= ROUND_COUNT) {
            this.phase.set('result');
            setTimeout(() => this.launchConfetti(), 300);
        } else {
            this.currentRound.set(next);
            this.startPokemonAnimation(() => this.startSoloClock());
        }
    }

    // --- Fin de partie multi -----------------------------------------------------

    /** Termine la partie multijoueur. */
    private endMultiGame(room: StatDuelRoom): void {
        this.stopClock();
        if (!this.isPlayer1() || !this.roomId || room.status === 'finished') {
            this.phase.set('result');
            this.maybeFireMultiConfetti(room);
            return;
        }
        const p1Total = room.p1_picks.reduce((s, p) => s + p.value, 0);
        const p2Total = room.p2_picks.reduce((s, p) => s + p.value, 0);
        const winner = p1Total > p2Total ? 'player1' : p2Total > p1Total ? 'player2' : 'draw';
        void this.supabaseService.updateStatDuelRoom(this.roomId, { status: 'finished', winner });
        this.phase.set('result');
        const me = this.supabaseService.getCurrentUser();
        const isMeP1 = me && room.player1_id === me.id;
        const iWon = (winner === 'player1' && isMeP1) || (winner === 'player2' && !isMeP1);
        if (iWon) setTimeout(() => this.launchConfetti(), 300);
    }

    /** Lance les confettis si le resultat multijoueur le justifie. */
    private maybeFireMultiConfetti(room: StatDuelRoom): void {
        const me = this.supabaseService.getCurrentUser();
        if (!me || !room?.winner || room.winner === 'draw') return;
        const isMeP1 = room.player1_id === me.id;
        const iWon = (room.winner === 'player1' && isMeP1) || (room.winner === 'player2' && !isMeP1);
        if (iWon) setTimeout(() => this.launchConfetti(), 300);
    }

    // --- Bot (dev mode) ----------------------------------------------------------

    /** Planifie le choix automatique du bot. */
    private scheduleBotPick(roundIndex: number): void {
        const botDelay = 1500 + Math.random() * 6500; // 1.5s to 8s dans la manche

        setTimeout(async () => {
            if (this.phase() !== 'playing' || !this.roomId) return;
            if (this.botPickedRounds.has(roundIndex)) return;
            if (this.currentRound() !== roundIndex) return;

            const botUsedStats = Array.from(this.botPickedRounds).length;
            if (botUsedStats !== roundIndex) return; // ordre strict

            const currentBotPicks = this.room()?.p2_picks ?? [];
            const available = STAT_DEFS.map(s => s.key).filter(k => !currentBotPicks.some(p => p.stat === k));
            if (available.length === 0) return;

            const pokemon = this.pokemonList()[roundIndex];
            if (!pokemon) return;

            const randomStat = available[Math.floor(Math.random() * available.length)];
            const value = pokemon.stats[randomStat];
            this.botPickedRounds.add(roundIndex);

            await this.supabaseService.appendStatPick(this.roomId, 'p2_picks', { stat: randomStat, value });
        }, botDelay);
    }

    // --- Duel intro --------------------------------------------------------------

    /** Declenche l'intro de duel si ses donnees sont disponibles. */
    private async triggerDuelIntro(room: StatDuelRoom): Promise<void> {
        if (!this.roomId) return;
        const introKey = `stat-duel-intro-shown-${this.roomId}`;
        if (this.duelShown || sessionStorage.getItem(introKey)) return;
        this.duelShown = true;
        sessionStorage.setItem(introKey, '1');
        const cached = this.readDuelIntroCache(`stat-duel-intro-data-${this.roomId}`);
        this.duelPlayer1.set(cached?.[0] ?? { username: 'Joueur 1', avatar_url: undefined });
        this.duelPlayer2.set(cached?.[1] ?? { username: room.player2_id ? 'Joueur 2' : '?', avatar_url: undefined });
        this.showDuelIntro.set(true);
        try {
            const fetchProfile = (id: string | null) =>
                id
                    ? this.supabaseService.getProfile(id).catch(() => ({ username: '?', avatar_url: undefined }))
                    : Promise.resolve({ username: '?', avatar_url: undefined });
            const [p1, p2] = await Promise.all([fetchProfile(room.player1_id), fetchProfile(room.player2_id ?? null)]);
            const p1Data = { username: p1.username, avatar_url: p1.avatar_url };
            const p2Data = { username: p2.username, avatar_url: p2.avatar_url };
            this.duelPlayer1.set(p1Data);
            this.duelPlayer2.set(p2Data);
        } catch {
            // L'intro reste visible avec les libellés de secours.
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

    // --- Rejouer / Navigation ----------------------------------------------------

    /** Relance une partie. */
    replay(): void {
        if (this.isSolo()) {
            this.resetGameState();
            void this.startSolo();
            return;
        }
        void this.requestStatDuelReplay();
    }

    /** Reinitialise l'etat local de la partie. */
    private resetGameState(): void {
        this.myPicks.set([]);
        this.opponentPicks.set([]);
        this.pokemonList.set([]);
        this.currentRound.set(0);
        this.timerValue.set(10);
        this.timerProgress.set(10);
        this.revealedRound.set(-1);
        this.waitingForReveal.set(false);
        this.pendingMyPickStat.set(null);
        this.justPickedStat.set(null);
        this.justRevealedOpponentPick.set(null);
        this.nextRoundCountdown.set(null);
        this.opponentLeft.set(false);
        this.pokemonVisible.set(false);
        this.pokemonAnimating.set(false);
        this.botPickedRounds.clear();
        this.stopClock();

        this.duelShown = false;
        this.confettiFired = false;
        if (this.roomId) {
            sessionStorage.removeItem(`stat-duel-intro-shown-${this.roomId}`);
        }
    }

    /** Demande une revanche en Duel de Base Stats. */
    private async requestStatDuelReplay(): Promise<void> {
        if (!this.roomId) return;
        const isP1 = this.isPlayer1();
        if (this.isDevMode()) {
            await this.supabaseService.updateStatDuelRoom(this.roomId, { p1_ready: true, p2_ready: true });
            const refreshed = await this.supabaseService.getStatDuelRoom(this.roomId);
            this.room.set(refreshed);
            if (refreshed.status === 'finished') {
                await this.launchReplayGame();
            }
            return;
        }

        await this.supabaseService.updateStatDuelRoom(this.roomId, isP1 ? { p1_ready: true } : { p2_ready: true });
        const refreshed = await this.supabaseService.getStatDuelRoom(this.roomId);
        this.room.set(refreshed);
        await this.launchReplayIfReady(refreshed);
    }

    private async launchReplayIfReady(room: StatDuelRoom): Promise<boolean> {
        if (!this.isPlayer1() || this.replayLaunchInProgress) return false;
        if (room.status !== 'finished' || !room.p1_ready || !room.p2_ready) return false;

        this.replayLaunchInProgress = true;
        try {
            await this.launchReplayGame();
            return true;
        } finally {
            this.replayLaunchInProgress = false;
        }
    }

    /** Lance la partie de revanche. */
    private async launchReplayGame(): Promise<void> {
        if (!this.roomId) return;
        const currentRoom = this.room();
        if (!currentRoom) return;
        const allPokemon = this.getConfiguredPokemonPool(await this.loadAll(), currentRoom.settings);
        const pokemonIds = this.shuffle(allPokemon).slice(0, ROUND_COUNT).map(p => p.id);
        const roundStartAt = new Date(Date.now() + 3000).toISOString();
        await this.supabaseService.updateStatDuelRoom(this.roomId, {
            status: 'playing',
            settings: toGuessSettings(normalizeModeSettings('stat_duel', currentRoom.settings ?? this.settings())),
            pokemon_ids: pokemonIds,
            p1_picks: [],
            p2_picks: [],
            winner: null,
            round_start_at: roundStartAt,
            p1_ready: false,
            p2_ready: false,
        });
        this.resetGameState();
        await this.loadPokemonAndStartMulti({
            ...currentRoom,
            status: 'playing',
            pokemon_ids: pokemonIds,
            p1_picks: [],
            p2_picks: [],
            winner: null,
            round_start_at: roundStartAt,
            p1_ready: false,
            p2_ready: false,
        });
    }

    /** Navigue vers la page d'accueil. */
    goHome(): void {
        void this.supabaseService.broadcastPlayerLeft().catch(() => { });
        void this.router.navigate(['/home']);
    }

    /** Affiche la confirmation de sortie pour les modes en ligne. */
    promptCancel(): void {
        if (this.isSolo()) {
            this.goHome();
            return;
        }
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
        if (this.roomId) {
            await this.supabaseService.broadcastPlayerLeft().catch(() => undefined);
            await this.supabaseService.updateStatDuelRoom(this.roomId, {
                status: 'finished',
                winner: null,
                p1_ready: false,
                p2_ready: false,
            }).catch(() => undefined);
        }
        void this.router.navigate(['/home']);
    }

    // --- Partage lien multi ------------------------------------------------------

    /** Copie le lien de la room dans le presse-papiers. */
    async copyRoomLink(): Promise<void> {
        if (!this.inviteLink) return;
        try {
            await navigator.clipboard.writeText(this.inviteLink);
        } catch {
            const el = document.createElement('input');
            el.value = this.inviteLink;
            document.body.appendChild(el);
            el.select();
            document.execCommand('copy');
            document.body.removeChild(el);
        }
        this.linkCopied.set(true);
        setTimeout(() => this.linkCopied.set(false), 2000);
    }

    // --- Utilitaires -------------------------------------------------------------

    /** Precharge les images donnees. */
    private preloadImages(pokemons: Pokemon[]): void {
        this.preloadedImages = pokemons.map(p => {
            const img = new Image();
            img.src = p.sprite;
            return img;
        });
    }

    /** Demarre l'animation du Pokemon courant. */
    private startPokemonAnimation(callback?: () => void): void {
        this.pokemonVisible.set(false);
        this.pokemonAnimating.set(true);
        setTimeout(() => {
            this.pokemonVisible.set(true);
            setTimeout(() => {
                this.pokemonAnimating.set(false);
                callback?.();
            }, this.ANIMATION_DURATION_MS);
        }, 50);
    }

    /** Charge tous les Pokemon. */
    private loadAll(): Promise<Pokemon[]> {
        return new Promise(resolve => {
            this.pokemonService.loadAll().subscribe(all => resolve(all));
        });
    }

    /** Retourne une copie melangee du tableau donne. */
    private shuffle<T>(arr: T[]): T[] {
        const a = [...arr];
        for (let i = a.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [a[i], a[j]] = [a[j], a[i]];
        }
        return a;
    }

    private getConfiguredPokemonPool(pokemons: Pokemon[], sourceSettings: Partial<ModeSettings> | null | undefined = this.settings()): Pokemon[] {
        const settings = normalizeModeSettings('stat_duel', sourceSettings);
        return pokemons.filter(pokemon => {
            if (settings.generations.length > 0 && !settings.generations.includes(pokemon.generation)) return false;
            if (settings.categories.length > 0 && !settings.categories.includes(pokemon.category)) return false;
            return true;
        });
    }

    /** Retourne la largeur CSS d'une barre de statistique. */
    getStatBarWidth(value: number): string {
        return `${Math.min(100, Math.round((value / 200) * 100))}%`;
    }

    /** Retourne true si le Pokemon courant est revele. */
    isCurrentPokemonRevealed(): boolean {
        if (this.isSolo()) return this.hasPickedThisRound();
        return this.myPicks().length > this.currentRound() && this.opponentPicks().length > this.currentRound();
    }

    /** Retourne true si les statistiques du Pokemon courant doivent etre affichees. */
    shouldShowCurrentPokemonStats(): boolean {
        return this.pokemonVisible() && this.isCurrentPokemonRevealed();
    }

    /** Retourne true si la statistique donnee est la plus haute du Pokemon courant. */
    isCurrentPokemonHighestStat(statKey: keyof Pokemon['stats']): boolean {
        const pokemon = this.currentPokemon();
        if (!pokemon) return false;
        const values = Object.values(pokemon.stats) as number[];
        const max = Math.max(...values);
        return pokemon.stats[statKey] === max;
    }

    /** Retourne la classe CSS de couleur du timer. */
    getTimerColor(): string {
        const t = this.timerValue();
        if (t <= 3) return 'text-red-400';
        if (t <= 6) return 'text-yellow-400';
        return 'text-green-400';
    }

    /** Retourne la classe CSS de fond du timer. */
    getTimerBg(): string {
        const t = this.timerValue();
        if (t <= 3) return 'bg-red-500';
        if (t <= 6) return 'bg-yellow-500';
        return 'bg-green-500';
    }

    /** Retourne les classes CSS du bouton de statistique. */
    getStatButtonClass(statKey: keyof Pokemon['stats'], alreadyPicked: boolean): string {
        const base = 'flex flex-col items-center gap-1 px-4 py-3 rounded-xl border transition-all font-bold relative';
        if (!this.isSolo() && this.pendingMyPickStat() === statKey) return `${base} bg-blue-500/15 border-blue-500/50 cursor-not-allowed`;
        if (this.justPickedStat()?.stat === statKey) return `${base} bg-yellow-500/15 border-yellow-500 cursor-not-allowed`;
        if (alreadyPicked) return `${base} bg-slate-700/30 border-slate-700/30 opacity-50 cursor-not-allowed`;
        if (this.hasPickedThisRound() || this.pokemonAnimating() || this.nextRoundCountdown() !== null) return `${base} bg-slate-700/50 border-slate-700/50 opacity-50 cursor-not-allowed`;
        return `${base} bg-slate-700 border-slate-600 hover:border-yellow-500/60 hover:bg-slate-600 cursor-pointer active:scale-95`;
    }

    /** Retourne les classes CSS de la ligne de statistique. */
    getStatRowClass(alreadyPicked: boolean, justPicked: boolean, canPick: boolean): string {
        const base = 'flex items-center gap-2 rounded-xl px-2 py-2 transition-all border';
        if (justPicked) return `${base} border-yellow-500/30 bg-yellow-500/5`;
        if (canPick) return `${base} border-transparent hover:border-white/20 hover:bg-slate-700/40 cursor-pointer active:scale-[0.99]`;
        return `${base} border-transparent`;
    }

    /** Retourne le resultat du joueur courant en multijoueur. */
    isMultiWinner(): boolean | null {
        const me = this.supabaseService.getCurrentUser();
        const room = this.room();
        if (!me || !room?.winner || room.winner === 'draw') return null;
        const isMeP1 = room.player1_id === me.id;
        return (room.winner === 'player1' && isMeP1) || (room.winner === 'player2' && !isMeP1);
    }

    /** Retourne le libelle du resultat de partie. */
    getResultLabel(): string {
        const me = this.supabaseService.getCurrentUser();
        const room = this.room();
        if (!me || !room?.winner) return '';
        if (room.winner === 'draw') return 'Égalité !';
        const isMeP1 = room.player1_id === me.id;
        const iWon = (room.winner === 'player1' && isMeP1) || (room.winner === 'player2' && !isMeP1);
        return iWon ? 'Victoire !' : 'Défaite';
    }

    /** Retourne la classe CSS de couleur du resultat. */
    getResultColor(): string {
        const me = this.supabaseService.getCurrentUser();
        const room = this.room();
        if (!me || !room?.winner) return 'text-white';
        if (room.winner === 'draw') return 'text-yellow-400';
        const isMeP1 = room.player1_id === me.id;
        const iWon = (room.winner === 'player1' && isMeP1) || (room.winner === 'player2' && !isMeP1);
        return iWon ? 'text-yellow-400' : 'text-red-400';
    }

    /** Retourne mon pick pour une statistique. */
    getMyPickForStat(statKey: string): StatPick | undefined {
        return this.myPicks().find(p => p.stat === statKey);
    }

    /** Retourne mon pick revele pour une statistique. */
    getMyRevealedPickForStat(statKey: string): StatPick | undefined {
        return this.myRevealedPicks().find(p => p.stat === statKey);
    }

    /** Retourne le pick adverse pour une statistique. */
    getOpponentPickForStat(statKey: string): StatPick | undefined {
        return this.opponentPicks().find(p => p.stat === statKey);
    }

    /** Retourne le pick adverse revele pour une statistique. */
    getOpponentRevealedPickForStat(statKey: string): StatPick | undefined {
        return this.opponentRevealedPicks().find(p => p.stat === statKey);
    }
}
