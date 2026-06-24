import { Component, CUSTOM_ELEMENTS_SCHEMA, OnDestroy, OnInit, computed, effect, inject, input, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import confetti from 'canvas-confetti';
import { firstValueFrom, Subscription } from 'rxjs';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import { EndGameActionsComponent } from '../../components/end-game-actions/end-game-actions.component';
import { HelpCardComponent } from '../../components/help-modal/help-card.component';
import { HelpSectionTitleComponent } from '../../components/help-modal/help-section-title.component';
import { GameSettingsPanelComponent } from '../../components/game-settings-panel/game-settings-panel.component';
import { ModeSelectCardComponent } from '../../components/mode-select-card/mode-select-card.component';
import { ModeSelectComponent } from '../../components/mode-select-card/mode-select.component';
import { ICONS } from '../../constants/icons';
import { Pokemon } from '../../models/pokemon.model';
import { DEFAULT_WHO_SETTINGS, WhoPokemonRoom } from '../../models/room.model';
import { DEFAULT_MODE_SETTINGS, ModeSettings, normalizeModeSettings, toWhoSettings } from '../../models/game-settings.model';
import { PokemonService } from '../../services/pokemon.service';
import { SupabaseService } from '../../services/supabase.service';
import {
  buildWhoPokemonPool,
  getWhoHintOrder,
  nextSoloState,
  pickWhoPokemonSequence,
  resolveWhoInitialHint,
  WHO_MAX_HINTS,
  WHO_TOTAL_ROUNDS,
  WhoInitialHintMode,
  WhoInitialHintSetting,
  WhoRevealedHint,
  WhoSoloState,
} from '../../utils/who-that-pokemon-utils';

type Phase = 'setup' | 'solo' | 'waiting' | 'duo' | 'complete';
type WhoConfigMode = 'solo';

@Component({
  selector: 'app-who-that-pokemon',
  imports: [FormsModule, AppHeaderComponent, EndGameActionsComponent, CancelModalComponent, ModeSelectComponent, ModeSelectCardComponent, HelpSectionTitleComponent, HelpCardComponent, GameSettingsPanelComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './who-that-pokemon.component.html',
  styles: [`
    @keyframes whoToastIn {
      from { opacity: 0; transform: translateY(-8px) scale(0.98); }
      to { opacity: 1; transform: translateY(0) scale(1); }
    }

    @keyframes whoSilhouetteIn {
      0% { opacity: 0; transform: scale(0.75) translateY(14px); }
      65% { transform: scale(1.04) translateY(-2px); }
      100% { opacity: 1; transform: scale(1) translateY(0); }
    }

    @keyframes whoHintSlideIn {
      0% { opacity: 0; transform: translateY(-12px); max-height: 0; }
      100% { opacity: 1; transform: translateY(0); max-height: 320px; }
    }

    .who-toast {
      animation: whoToastIn 180ms ease-out both;
    }

    .who-silhouette-frame-loaded {
      animation: whoSilhouetteIn 0.45s cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
    }

    .who-hint-slide {
      animation: whoHintSlideIn 500ms ease-out both;
      overflow: hidden;
    }
  `],
})
export class WhoThatPokemonComponent implements OnInit, OnDestroy {
  protected readonly ICONS = ICONS;
  protected readonly maxHints = WHO_MAX_HINTS;
  protected readonly hintModes: { value: WhoInitialHintSetting; label: string; icon: string }[] = [
    { value: 'silhouette', label: 'Silhouette', icon: ICONS.whoPokemon },
    { value: 'cry', label: 'Cri', icon: ICONS.sound },
    { value: 'pokedex_number', label: 'Numéro de Pokédex', icon: ICONS.pokedex },
    { value: 'description', label: 'Description', icon: ICONS.rules },
    { value: 'random', label: 'Aléatoire', icon: ICONS.dice },
  ];

  readonly roomId = input<string | undefined>();
  private readonly pokemonService = inject(PokemonService);
  private readonly supabaseService = inject(SupabaseService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  readonly phase = signal<Phase>('setup');
  readonly whoConfigMode = signal<WhoConfigMode | null>(null);
  readonly settings = signal<ModeSettings>({ ...DEFAULT_MODE_SETTINGS.who_that_pokemon });
  readonly allPokemons = signal<Pokemon[]>([]);
  readonly soloSequence = signal<Pokemon[]>([]);
  readonly soloState = signal<WhoSoloState>({ roundIndex: 0, hintsRevealed: 0, score: 0, found: 0, status: 'playing' });
  readonly room = signal<WhoPokemonRoom | null>(null);
  readonly isPlayer1 = signal(false);
  readonly linkCopied = signal(false);
  readonly isBusy = signal(false);
  readonly guessInput = signal('');
  readonly feedback = signal('');
  readonly toastMessage = signal('');
  readonly toastKind = signal<'success' | 'error'>('success');
  readonly toastPokemon = signal<Pokemon | null>(null);
  readonly cryVolume = signal(0.25);
  readonly cryDuration = signal(0);
  readonly cryCurrentTime = signal(0);
  readonly cryPlaying = signal(false);
  readonly silhouetteLoaded = signal(false);
  readonly showHelpModal = signal(false);
  readonly showCancelModal = signal(false);
  readonly isCancelling = signal(false);
  readonly opponentLeft = signal(false);

  private roomSub?: Subscription;
  private broadcastSub?: Subscription;
  private inviteResponseSub?: Subscription;
  private pollInterval?: ReturnType<typeof setInterval>;
  private toastTimeout?: ReturnType<typeof setTimeout>;
  private currentSilhouetteTargetId = 0;
  private confettiFired = false;

  private readonly resetSilhouetteAnimation = effect(() => {
    const targetId = this.targetPokemon()?.id ?? 0;
    if (targetId !== this.currentSilhouetteTargetId) {
      this.currentSilhouetteTargetId = targetId;
      this.silhouetteLoaded.set(false);
    }
  });

  readonly targetPokemon = computed(() => {
    const all = this.allPokemons();
    if (this.phase() === 'solo') return this.soloSequence()[this.soloState().roundIndex] ?? null;
    const targetId = this.room()?.target_pokemon_id ?? null;
    return targetId ? all.find(p => p.id === targetId) ?? null : null;
  });

  readonly statusTitle = computed(() => {
    if (this.phase() === 'complete') {
      const r = this.room();
      if (!r) return this.soloState().status === 'won' ? 'Victoire !' : 'Fin de partie';
      if (r.winner === 'draw') return 'Égalité !';
      const iWin = (r.winner === 'player1' && this.isPlayer1()) || (r.winner === 'player2' && !this.isPlayer1());
      return iWin ? 'Victoire !' : 'Défaite';
    }
    return "Who's That Pokémon ?";
  });

  readonly isVictory = computed(() => {
    const r = this.room();
    if (!r) return this.soloState().status === 'won';
    if (!r.winner || r.winner === 'draw') return false;
    return (r.winner === 'player1' && this.isPlayer1()) || (r.winner === 'player2' && !this.isPlayer1());
  });

  private readonly victoryConfetti = effect(() => {
    if (this.phase() !== 'complete') {
      this.confettiFired = false;
      return;
    }
    if (this.isVictory()) setTimeout(() => this.launchConfetti(), 300);
  });

  readonly myHintsRevealed = computed(() => {
    const r = this.room();
    if (!r) return this.soloState().hintsRevealed;
    return this.isPlayer1() ? r.p1_lives : r.p2_lives;
  });

  readonly opponentHintsRevealed = computed(() => {
    const r = this.room();
    if (!r) return 0;
    return this.isPlayer1() ? r.p2_lives : r.p1_lives;
  });

  readonly myScore = computed(() => {
    const r = this.room();
    if (!r) return this.soloState().score;
    return this.isPlayer1() ? r.p1_score : r.p2_score;
  });

  readonly opponentScore = computed(() => {
    const r = this.room();
    if (!r) return 0;
    return this.isPlayer1() ? r.p2_score : r.p1_score;
  });

  readonly canGuess = computed(() => {
    if (this.phase() === 'solo') return this.soloState().status === 'playing';
    const r = this.room();
    return this.phase() === 'duo' && !!r && r.status === 'playing';
  });

  readonly hasGuessQuery = computed(() => this.guessInput().trim().length > 0);
  readonly guessSuggestions = computed(() => {
    const query = this.guessInput().trim();
    if (!query) return [];
    const hasUppercase = /[A-ZÀ-ÖØ-Þ]/.test(query);
    const normalizedQuery = hasUppercase ? query : this.normalize(query);
    return this.allPokemons()
      .filter(pokemon => hasUppercase ? pokemon.name.includes(query) : this.normalize(pokemon.name).includes(normalizedQuery));
  });
  readonly cryVolumePercent = computed(() => Math.round(this.cryVolume() * 100));
  readonly cryProgressPercent = computed(() => {
    const duration = this.cryDuration();
    if (!duration) return 0;
    return Math.min(100, Math.round((this.cryCurrentTime() / duration) * 100));
  });
  readonly revealedHints = computed<WhoRevealedHint[]>(() => {
    const target = this.targetPokemon();
    if (!target) return [];
    const room = this.room();
    const roundSeed = room ? room.round : this.soloState().roundIndex + 1;
    const playerSeed = room ? (this.isPlayer1() ? 101 : 202) : 0;
    return getWhoHintOrder(target.id + roundSeed + playerSeed, this.initialHint()).slice(0, this.myHintsRevealed());
  });
  readonly initialHint = computed<WhoInitialHintMode>(() => {
    const target = this.targetPokemon();
    if (!target) return 'silhouette';
    const room = this.room();
    const roundSeed = room ? room.round : this.soloState().roundIndex + 1;
    const playerSeed = room ? (this.isPlayer1() ? 101 : 202) : 0;
    return resolveWhoInitialHint(target.id + roundSeed + playerSeed, this.settings().initialHint ?? 'silhouette');
  });
  readonly visibleHints = computed<WhoRevealedHint[]>(() => [this.initialHint(), ...this.revealedHints()]);
  readonly targetAnimationKey = computed(() => this.targetPokemon()?.id ?? 0);

  get inviteLink(): string {
    return `${window.location.origin}/invite/${this.roomId()}?mode=who_that_pokemon`;
  }

  async ngOnInit(): Promise<void> {
    this.supabaseService.trackPresence(this.roomId() ? 'in_game' : 'online');
    this.allPokemons.set(await firstValueFrom(this.pokemonService.loadAll()));
    if (this.roomId()) await this.loadDuoRoom();
  }

  ngOnDestroy(): void {
    this.roomSub?.unsubscribe();
    this.broadcastSub?.unsubscribe();
    this.inviteResponseSub?.unsubscribe();
    if (this.pollInterval) clearInterval(this.pollInterval);
    if (this.toastTimeout) clearTimeout(this.toastTimeout);
  }

  updateGameSettings(settings: ModeSettings): void {
    this.settings.set(settings);
    void this.persistWaitingSettings();
  }

  selectWhoConfigMode(mode: WhoConfigMode): void {
    this.whoConfigMode.set(mode);
  }

  startSolo(): void {
    const pool = buildWhoPokemonPool(this.allPokemons(), this.settings());
    if (pool.length === 0) {
      this.feedback.set('Aucun Pokémon ne correspond aux filtres.');
      return;
    }
    this.soloSequence.set(pickWhoPokemonSequence(pool, WHO_TOTAL_ROUNDS));
    this.soloState.set({ roundIndex: 0, hintsRevealed: 0, score: 0, found: 0, status: 'playing' });
    this.guessInput.set('');
    this.feedback.set('');
    this.phase.set('solo');
  }

  async createDuoRoom(): Promise<void> {
    if (this.isBusy()) return;
    this.isBusy.set(true);
    try {
      const roomId = await this.supabaseService.createWhoPokemonRoom();
      await this.router.navigate(['/lobby', roomId], { queryParams: { mode: 'who_that_pokemon' } });
    } catch {
      this.feedback.set('Impossible de créer la partie.');
    } finally {
      this.isBusy.set(false);
    }
  }

  async launchDuoGame(): Promise<void> {
    const r = this.room();
    if (!r || !this.isPlayer1() || !r.player2_id || this.isBusy()) return;
    const pool = buildWhoPokemonPool(this.allPokemons(), this.settings());
    const target = pickWhoPokemonSequence(pool, 1)[0];
    if (!target) {
      this.feedback.set('Aucun Pokémon ne correspond aux filtres.');
      return;
    }
    this.isBusy.set(true);
    try {
      await this.supabaseService.updateWhoPokemonRoom(r.id, {
        status: 'playing',
        settings: toWhoSettings(this.settings()),
        round: 1,
        target_pokemon_id: target.id,
        used_pokemon_ids: [target.id],
        p1_score: 0,
        p2_score: 0,
        p1_lives: 0,
        p2_lives: 0,
        winner: null,
        p1_ready: false,
      });
      this.phase.set('duo');
    } finally {
      this.isBusy.set(false);
    }
  }

  async submitGuess(): Promise<void> {
    const guessed = this.findPokemonByName(this.guessInput());
    if (!guessed || !this.canGuess()) return;
    this.guessInput.set('');

    if (this.phase() === 'solo') {
      const target = this.targetPokemon();
      const isCorrect = guessed.id === target?.id;
      const hadAllHints = this.soloState().hintsRevealed >= WHO_MAX_HINTS;
      const next = nextSoloState(this.soloState(), isCorrect);
      this.soloState.set(next);
      if (isCorrect) {
        this.feedback.set('');
        this.showToast(target?.name ?? guessed.name, 'success', target);
      } else {
        this.feedback.set('');
        this.showToast(hadAllHints && target ? `C'était ${target.name}.` : 'Indice débloqué.', 'error', hadAllHints ? target : null);
      }
      if (next.status !== 'playing') this.phase.set('complete');
      return;
    }

    const nextTarget = this.pickNextDuoTargetId();
    const target = this.targetPokemon();
    const isCorrect = guessed.id === target?.id;
    const hadAllHints = this.myHintsRevealed() >= WHO_MAX_HINTS;
    try {
      await this.supabaseService.submitWhoPokemonGuess(this.roomId()!, guessed.id, nextTarget);
      if (isCorrect) {
        this.feedback.set('');
        this.showToast(target?.name ?? guessed.name, 'success', target);
      } else {
        this.feedback.set('');
        this.showToast(hadAllHints && target ? `C'était ${target.name}.` : 'Mauvaise réponse, indice débloqué.', 'error', hadAllHints ? target : null);
      }
    } catch {
      this.feedback.set('Réponse impossible pour le moment.');
    }
  }

  async replay(): Promise<void> {
    if (this.room()) {
      const patch = this.isPlayer1() ? { p1_ready: true } : { p2_ready: true };
      await this.supabaseService.updateWhoPokemonRoom(this.roomId()!, patch);
      const refreshed = await this.supabaseService.getWhoPokemonRoom(this.roomId()!);
      this.room.set(refreshed);
      await this.launchReplayIfReady(refreshed);
      return;
    }
    this.phase.set('setup');
    this.feedback.set('');
  }

  goHome(): void {
    void this.router.navigate(['/home']);
  }

  handleQuit(): void {
    if (this.room()) {
      this.promptCancel();
      return;
    }
    this.goHome();
  }

  promptCancel(): void {
    this.showCancelModal.set(true);
  }

  closeCancelModal(): void {
    this.showCancelModal.set(false);
  }

  async confirmCancel(): Promise<void> {
    this.isCancelling.set(true);
    await this.supabaseService.broadcastPlayerLeft().catch(() => undefined);
    const r = this.room();
    if (r) {
      await this.supabaseService.updateWhoPokemonRoom(r.id, {
        status: 'finished',
        winner: null,
        p1_ready: false,
        p2_ready: false,
      }).catch(() => undefined);
    }
    void this.router.navigate(['/home']);
  }

  async copyLink(): Promise<void> {
    await navigator.clipboard.writeText(this.inviteLink);
    this.linkCopied.set(true);
    setTimeout(() => this.linkCopied.set(false), 2000);
  }

  playCry(audio: HTMLAudioElement): void {
    if (!audio.paused) {
      audio.pause();
      this.cryPlaying.set(false);
      return;
    }
    audio.volume = this.cryVolume();
    if (audio.ended) {
      audio.currentTime = 0;
      this.cryCurrentTime.set(0);
    }
    void audio.play();
    this.cryPlaying.set(true);
  }

  updateCryVolume(event: Event, audio?: HTMLAudioElement): void {
    const input = event.target as HTMLInputElement;
    const volume = Number(input.value) / 100;
    this.cryVolume.set(volume);
    if (audio) audio.volume = volume;
  }

  syncCryVolume(audio: HTMLAudioElement): void {
    audio.volume = this.cryVolume();
  }

  syncCryMetadata(audio: HTMLAudioElement): void {
    this.syncCryVolume(audio);
    this.cryDuration.set(Number.isFinite(audio.duration) ? audio.duration : 0);
    this.cryCurrentTime.set(0);
    this.cryPlaying.set(false);
  }

  syncCryProgress(audio: HTMLAudioElement): void {
    this.cryCurrentTime.set(audio.currentTime);
  }

  syncCryPlayback(audio: HTMLAudioElement): void {
    this.cryPlaying.set(!audio.paused && !audio.ended);
    this.cryCurrentTime.set(audio.ended ? 0 : audio.currentTime);
    if (audio.ended) audio.currentTime = 0;
  }

  formatAudioTime(seconds: number): string {
    if (!Number.isFinite(seconds) || seconds <= 0) return '0:00';
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = Math.floor(seconds % 60).toString().padStart(2, '0');
    return `${minutes}:${remainingSeconds}`;
  }

  private async loadDuoRoom(): Promise<void> {
    const room = await this.supabaseService.getWhoPokemonRoom(this.roomId()!);
    const user = this.supabaseService.getCurrentUser();
    if (!user) {
      void this.router.navigate(['/login']);
      return;
    }
    this.room.set(room);
    this.isPlayer1.set(room.player1_id === user.id);
    this.settings.set(normalizeModeSettings('who_that_pokemon', room.settings));
    this.phase.set(room.status === 'waiting' ? 'waiting' : room.status === 'playing' ? 'duo' : 'complete');

    this.roomSub = this.supabaseService.subscribeToWhoPokemonRoom(this.roomId()!).subscribe(updated => {
      this.room.set(updated);
      this.settings.set(normalizeModeSettings('who_that_pokemon', updated.settings));
      if (updated.status === 'finished' && updated.winner === null && this.phase() === 'complete') {
        this.opponentLeft.set(true);
      }
      if (updated.status === 'playing') {
        this.opponentLeft.set(false);
      }
      this.phase.set(updated.status === 'waiting' ? 'waiting' : updated.status === 'playing' ? 'duo' : 'complete');
      void this.launchReplayIfReady(updated);
    });
    this.pollInterval = setInterval(async () => {
      const updated = await this.supabaseService.getWhoPokemonRoom(this.roomId()!);
      if (updated.status === 'finished' && updated.winner === null && this.phase() === 'complete') {
        this.opponentLeft.set(true);
      }
      this.room.set(updated);
    }, 2000);
    this.broadcastSub = this.supabaseService.broadcastEvents$.subscribe(({ event }) => {
      if (event === 'player_left') {
        if (this.phase() === 'complete') {
          this.opponentLeft.set(true);
          return;
        }
        void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
      }
    });

    const inviteId = this.route.snapshot.queryParamMap.get('inviteId');
    const friendName = this.route.snapshot.queryParamMap.get('friendName') ?? 'Ton ami';
    if (inviteId) {
      this.inviteResponseSub = this.supabaseService.subscribeToGameInviteResponse(inviteId).subscribe((invite) => {
        if (invite.status === 'declined') void this.router.navigate(['/home'], { queryParams: { declined: friendName } });
      });
    }
  }

  private async persistWaitingSettings(): Promise<void> {
    const r = this.room();
    if (!r || !this.isPlayer1() || r.status !== 'waiting') return;
    await this.supabaseService.updateWhoPokemonRoom(r.id, { settings: toWhoSettings(this.settings()) }).catch(() => undefined);
  }

  private async launchReplayIfReady(room: WhoPokemonRoom): Promise<void> {
    if (!this.isPlayer1() || room.status !== 'finished' || !room.p1_ready || !room.p2_ready) return;
    const pool = buildWhoPokemonPool(this.allPokemons(), room.settings ?? DEFAULT_WHO_SETTINGS);
    const target = pickWhoPokemonSequence(pool, 1)[0];
    if (!target) return;
    await this.supabaseService.updateWhoPokemonRoom(room.id, {
      status: 'playing',
      round: 1,
      target_pokemon_id: target.id,
      used_pokemon_ids: [target.id],
      p1_score: 0,
      p2_score: 0,
      p1_lives: 0,
      p2_lives: 0,
      winner: null,
      p1_ready: false,
    });
  }

  private pickNextDuoTargetId(): number | null {
    const r = this.room();
    if (!r || r.round >= WHO_TOTAL_ROUNDS) return null;
    const used = new Set(r.used_pokemon_ids);
    const pool = buildWhoPokemonPool(this.allPokemons(), r.settings ?? DEFAULT_WHO_SETTINGS).filter(p => !used.has(p.id));
    return pickWhoPokemonSequence(pool.length > 0 ? pool : buildWhoPokemonPool(this.allPokemons(), r.settings ?? DEFAULT_WHO_SETTINGS), 1)[0]?.id ?? null;
  }

  private findPokemonByName(name: string): Pokemon | null {
    const normalized = this.normalize(name);
    return this.allPokemons().find(p => this.normalize(p.name) === normalized) ?? null;
  }

  private normalize(value: string): string {
    return value.trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  }

  private showToast(message: string, kind: 'success' | 'error', pokemon: Pokemon | null = null): void {
    if (this.toastTimeout) clearTimeout(this.toastTimeout);
    this.toastKind.set(kind);
    this.toastPokemon.set(pokemon);
    this.toastMessage.set(message);
    this.toastTimeout = setTimeout(() => {
      this.toastMessage.set('');
      this.toastPokemon.set(null);
    }, 3000);
  }

  private launchConfetti(): void {
    if (this.confettiFired) return;
    this.confettiFired = true;
    const colors = ['#ef4444', '#facc15', '#a855f7', '#3b82f6', '#ffffff'];
    confetti({ particleCount: 160, spread: 110, origin: { x: 0.5, y: 0.4 }, colors });
  }
}
