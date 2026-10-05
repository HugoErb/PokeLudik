import { Component, computed, CUSTOM_ELEMENTS_SCHEMA, inject, input, OnDestroy, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { NgClass } from '@angular/common';
import { Router } from '@angular/router';
import { Subscription, firstValueFrom } from 'rxjs';
import { launchDefeatRain, launchVictoryConfetti } from '../../utils/end-game-effects';
import { Pokemon } from '../../models/pokemon.model';
import { PokemonAuctionRoom } from '../../models/room.model';
import { SupabaseService } from '../../services/supabase.service';
import { PokemonService } from '../../services/pokemon.service';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import { EndGameActionsComponent } from '../../components/end-game-actions/end-game-actions.component';
import { PokemonStatsGridComponent } from '../../components/pokemon-stats-grid/pokemon-stats-grid.component';
import { PokemonTypeIconComponent } from '../../components/pokemon-type-icon/pokemon-type-icon.component';
import { ICONS } from '../../constants/icons';
import { TYPE_COLORS } from '../../constants/type-chart';
import { computeDuoCoverageScore, computeFinalScore, computeStatsScore } from '../../utils/draft-utils';
import { auctionFormatLabel, getMaximumAuctionBid } from '../../utils/auction-utils';
import { isStaleRoomState } from '../../utils/multiplayer-room-state';

interface ResultToast {
  message: string;
  revealedBids: string;
  pokemon: Pokemon | null;
  winnerAvatar: string | null;
  winnerName: string | null;
}

interface PaymentFx {
  id: number;
  role: 'player1' | 'player2';
  amount: number;
}

/** Délai entre deux tentatives de clôture d'une enchère dont le timer est à zéro. */
const FINALIZE_RETRY_MS = 1500;

@Component({
  selector: 'app-pokemon-auction',
  standalone: true,
  imports: [FormsModule, NgClass, AppHeaderComponent, CancelModalComponent, EndGameActionsComponent, PokemonStatsGridComponent, PokemonTypeIconComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './pokemon-auction.component.html',
})
export class PokemonAuctionComponent implements OnInit, OnDestroy {
  readonly roomId = input.required<string>();
  protected readonly ICONS = ICONS;
  protected readonly TYPE_COLORS = TYPE_COLORS;

  private readonly supabase = inject(SupabaseService);
  private readonly pokemonService = inject(PokemonService);
  private readonly router = inject(Router);
  private roomSub?: Subscription;
  private timer?: ReturnType<typeof setInterval>;
  private poll?: ReturnType<typeof setInterval>;
  private resultToastTimeout?: ReturnType<typeof setTimeout>;
  private resultSaving = false;
  private finalizeInFlight = false;
  private lastFinalizeAttempt = 0;
  private serverClockOffset = 0;
  private paymentFxId = 0;
  private endEffectFired = false;
  private stopDefeatRain: (() => void) | null = null;

  readonly room = signal<PokemonAuctionRoom | null>(null);
  readonly allPokemon = signal<Pokemon[]>([]);
  readonly now = signal(Date.now());
  readonly loading = signal(true);
  readonly actionPending = signal(false);
  readonly error = signal('');
  readonly resultToast = signal<ResultToast | null>(null);
  readonly showCancel = signal(false);
  readonly isCancelling = signal(false);
  readonly iWantReplay = signal(false);
  readonly opponentName = signal('Adversaire');
  readonly opponentAvatar = signal<string | null>(null);
  readonly myAvatar = signal<string | null>(null);
  readonly paymentFx = signal<PaymentFx[]>([]);
  bidAmount = 10;

  readonly isPlayer1 = computed(() => this.room()?.player1_id === this.supabase.currentUserSignal()?.id);
  readonly myRole = computed(() => this.isPlayer1() ? 'player1' : 'player2');
  readonly opponentRole = computed(() => this.isPlayer1() ? 'player2' : 'player1');
  readonly currentPokemon = computed(() => this.byId(this.room()?.current_pokemon_id));
  readonly myTeam = computed(() => this.teamFor(this.myRole()));
  readonly opponentTeam = computed(() => this.teamFor(this.opponentRole()));
  readonly myBalance = computed(() => this.isPlayer1() ? this.room()?.p1_balance ?? 0 : this.room()?.p2_balance ?? 0);
  readonly opponentBalance = computed(() => this.isPlayer1() ? this.room()?.p2_balance ?? 0 : this.room()?.p1_balance ?? 0);
  readonly passTokensEnabled = computed(() => this.room()?.settings?.randomAwardOnNoBid === false);
  readonly myPassesLeft = computed(() => this.isPlayer1() ? this.room()?.p1_passes_left ?? 0 : this.room()?.p2_passes_left ?? 0);
  readonly opponentPassesLeft = computed(() => this.isPlayer1() ? this.room()?.p2_passes_left ?? 0 : this.room()?.p1_passes_left ?? 0);
  /** Sans passe restant, un joueur incomplet doit enchérir : le bouton « Passer » est grisé. */
  readonly passLocked = computed(() => this.passTokensEnabled() && this.myTeam().length < 6 && this.myPassesLeft() <= 0);
  readonly maxBid = computed(() => getMaximumAuctionBid(this.myBalance(), this.myTeam().length));
  readonly minimumBid = computed(() => Math.max(10, (this.room()?.current_bid ?? 0) + 10));
  readonly formatLabel = computed(() => auctionFormatLabel(this.room()?.settings?.auctionFormat ?? 'live'));
  readonly timeLeft = computed(() => {
    const start = new Date(this.room()?.auction_start_at ?? 0).getTime();
    const end = new Date(this.room()?.auction_end_at ?? 0).getTime();
    return Math.max(0, Math.ceil((end - Math.max(this.now(), start)) / 1000));
  });
  readonly timerProgress = computed(() => {
    const start = new Date(this.room()?.auction_start_at ?? 0).getTime();
    const end = new Date(this.room()?.auction_end_at ?? 0).getTime();
    const remaining = Math.max(0, end - Math.max(this.now(), start));
    return Math.min(100, (remaining / 15_000) * 100);
  });
  readonly timerColor = computed(() => this.timeLeft() <= 5 ? 'text-red-400' : this.timeLeft() <= 10 ? 'text-yellow-400' : 'text-green-400');
  readonly timerBarColor = computed(() => this.timeLeft() <= 5 ? 'bg-red-500' : this.timeLeft() <= 10 ? 'bg-yellow-500' : 'bg-green-500');
  readonly hasStarted = computed(() => this.now() >= new Date(this.room()?.auction_start_at ?? 0).getTime());
  readonly myTurn = computed(() => this.room()?.current_turn === this.myRole());
  readonly myBidSubmitted = computed(() => this.isPlayer1() ? !!this.room()?.p1_bid_submitted : !!this.room()?.p2_bid_submitted);
  readonly opponentBidSubmitted = computed(() => this.isPlayer1() ? !!this.room()?.p2_bid_submitted : !!this.room()?.p1_bid_submitted);
  readonly canAct = computed(() => {
    const room = this.room();
    if (!room || room.status !== 'playing' || !room.current_pokemon_id || !this.hasStarted() || this.timeLeft() <= 0 || this.actionPending()) return false;
    if (room.settings?.auctionFormat === 'sealed') return !this.myBidSubmitted();
    if (room.settings?.auctionFormat === 'turn_based') return this.myTurn();
    return room.current_bidder !== this.myRole();
  });

  readonly myScores = computed(() => this.scores(this.myTeam(), this.opponentTeam()));
  readonly opponentScores = computed(() => this.scores(this.opponentTeam(), this.myTeam()));
  readonly myResultScores = computed(() => {
    const room = this.room(); const fallback = this.myScores();
    return this.isPlayer1()
      ? { stats: room?.p1_stats_score ?? fallback.stats, coverage: room?.p1_coverage_score ?? fallback.coverage, final: room?.p1_final_score ?? fallback.final }
      : { stats: room?.p2_stats_score ?? fallback.stats, coverage: room?.p2_coverage_score ?? fallback.coverage, final: room?.p2_final_score ?? fallback.final };
  });
  readonly opponentResultScores = computed(() => {
    const room = this.room(); const fallback = this.opponentScores();
    return this.isPlayer1()
      ? { stats: room?.p2_stats_score ?? fallback.stats, coverage: room?.p2_coverage_score ?? fallback.coverage, final: room?.p2_final_score ?? fallback.final }
      : { stats: room?.p1_stats_score ?? fallback.stats, coverage: room?.p1_coverage_score ?? fallback.coverage, final: room?.p1_final_score ?? fallback.final };
  });
  readonly result = computed(() => {
    const winner = this.room()?.winner;
    if (winner) return winner === 'draw' ? 'draw' : winner === this.myRole() ? 'win' : 'lose';
    const mine = this.myScores().final; const theirs = this.opponentScores().final;
    return mine === theirs ? 'draw' : mine > theirs ? 'win' : 'lose';
  });

  async ngOnInit(): Promise<void> {
    await firstValueFrom(this.supabase.authReady$);
    try {
      const [pokemon, initial] = await Promise.all([
        firstValueFrom(this.pokemonService.loadAll()),
        this.supabase.getPokemonAuctionRoom(this.roomId()),
      ]);
      this.allPokemon.set(pokemon);
      this.serverClockOffset = await this.supabase.getServerClockOffset().catch(() => 0);
      this.now.set(this.serverNow());
      await this.loadOpponent(initial);
      this.onRoom(initial);
      this.roomSub = this.supabase.subscribeToPokemonAuctionRoom(this.roomId()).subscribe(room => this.onRoom(room));
      this.timer = setInterval(() => this.tick(), 250);
      this.poll = setInterval(() => void this.refresh(), 2000);
      this.supabase.trackPresence('in_game', 'pokemon_auction');
    } catch { void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } }); }
    this.loading.set(false);
  }

  ngOnDestroy(): void {
    this.stopDefeatRain?.();
    this.roomSub?.unsubscribe();
    if (this.timer) clearInterval(this.timer);
    if (this.poll) clearInterval(this.poll);
    if (this.resultToastTimeout) clearTimeout(this.resultToastTimeout);
    this.supabase.untrackPresence();
  }

  protected adjustBid(delta: number): void {
    const next = delta === Number.POSITIVE_INFINITY ? this.maxBid() : this.bidAmount + delta;
    this.bidAmount = Math.min(this.maxBid(), Math.max(this.minimumBid(), Math.round(next / 10) * 10));
  }

  protected normalizeBid(): void { this.adjustBid(0); }
  protected setMaximumBid(): void { this.bidAmount = this.maxBid(); }

  protected async submitBid(): Promise<void> {
    const room = this.room(); if (!room || !this.canAct()) return;
    this.actionPending.set(true); this.error.set('');
    try {
      if (room.settings?.auctionFormat === 'sealed') await this.supabase.submitPokemonAuctionSealedBid(this.roomId(), this.bidAmount);
      else await this.supabase.placePokemonAuctionBid(this.roomId(), this.bidAmount);
      await this.refresh();
    } catch (error) { this.error.set(this.actionError(error)); }
    finally { this.actionPending.set(false); }
  }

  protected async pass(): Promise<void> {
    const room = this.room(); if (!room || !this.canAct() || this.passLocked()) return;
    this.actionPending.set(true); this.error.set('');
    try {
      if (room.settings?.auctionFormat === 'sealed') await this.supabase.submitPokemonAuctionSealedBid(this.roomId(), 0);
      else await this.supabase.passPokemonAuctionTurn(this.roomId());
      await this.refresh();
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      this.error.set(message.includes('no_pass_left') ? 'Tu n’as plus de passe : tu dois enchérir.' : 'Action refusée. La manche a peut-être déjà changé.');
    }
    finally { this.actionPending.set(false); }
  }

  protected lastResultToast(): ResultToast | null {
    const result = this.room()?.last_result; if (!result) return null;
    const pokemon = this.byId(result.pokemonId);
    const pokemonName = pokemon
      ? `${pokemon.name.charAt(0).toUpperCase()}${pokemon.name.slice(1)}`
      : `Pokémon #${result.pokemonId}`;
    const revealedBids = this.room()?.settings?.auctionFormat === 'sealed'
      ? `Offres révélées : ${result.p1Bid ?? 0} ₽ / ${result.p2Bid ?? 0} ₽.${result.p1Bid && result.p1Bid === result.p2Bid ? ' Égalité : tirage au sort.' : ''}`
      : '';
    const toast = (message: string, winnerAvatar: string | null = null, winnerName: string | null = null): ResultToast =>
      ({ message, revealedBids, pokemon, winnerAvatar, winnerName });
    if (result.outcome === 'tied') return toast(`Égalité pour ${pokemonName}.`);
    if (result.outcome === 'unsold') return toast(`Aucune offre pour ${pokemonName}.`);
    const mine = result.winner === this.myRole();
    const subject = mine ? 'Tu' : this.opponentName();
    const verb = mine ? 'remportes' : 'remporte';
    const avatar = mine ? this.myAvatar() : this.opponentAvatar();
    const name = mine ? 'Toi' : this.opponentName();
    if (result.outcome === 'free' && result.forced) return toast(`Plus de passe : ${mine ? 'tu récupères' : `${this.opponentName()} récupère`} ${pokemonName} gratuitement.`, avatar, name);
    if (result.outcome === 'free') return toast(`${subject} ${verb} ${pokemonName} gratuitement.`, avatar, name);
    if (result.outcome === 'blocked') return toast(`${subject} ${mine ? 'bloques' : 'bloque'} ${pokemonName} pour ${result.price} ₽.`, avatar, name);
    return toast(`${subject} ${verb} ${pokemonName} pour ${result.price} ₽.`, avatar, name);
  }

  protected typeColor(type: string): string { return TYPE_COLORS[type] ?? 'bg-gray-500'; }

  protected async requestReplay(): Promise<void> {
    if (this.iWantReplay()) return;
    this.iWantReplay.set(true);
    try { await this.supabase.requestPokemonAuctionReplay(this.roomId()); await this.refresh(); }
    catch { this.iWantReplay.set(false); }
  }

  protected goHome(): void { void this.router.navigate(['/home']); }

  protected async cancel(): Promise<void> {
    this.isCancelling.set(true);
    await this.supabase.cancelPokemonAuctionRoom(this.roomId()).catch(() => undefined);
    void this.router.navigate(['/home']);
  }

  private async refresh(): Promise<void> {
    try { this.onRoom(await this.supabase.getPokemonAuctionRoom(this.roomId())); } catch { /* polling de secours */ }
  }

  /** Heure serveur estimée : les timers ne dépendent pas de l'horloge de l'appareil. */
  private serverNow(): number { return Date.now() + this.serverClockOffset; }

  private tick(): void {
    const now = this.serverNow();
    this.now.set(now);
    const room = this.room();
    // Réessaie tant que la manche reste ouverte : une offre de dernière seconde prolonge le timer côté serveur.
    if (room?.status === 'playing' && room.current_pokemon_id && this.timeLeft() === 0 && !this.finalizeInFlight && now - this.lastFinalizeAttempt >= FINALIZE_RETRY_MS) {
      this.finalizeInFlight = true;
      this.lastFinalizeAttempt = now;
      void this.supabase.finalizePokemonAuction(this.roomId())
        .then(() => this.refresh())
        .catch(() => undefined)
        .finally(() => { this.finalizeInFlight = false; });
    }
  }

  private onRoom(room: PokemonAuctionRoom): void {
    const previous = this.room();
    if (isStaleRoomState(previous, room)) return;
    const newGame = !!previous && (room.round < previous.round || (previous.status === 'finished' && room.status === 'playing'));
    this.room.set(room);
    if (newGame) this.resetGameUi();
    else if (previous && room.status === 'playing') this.showPayments(previous, room);
    if (room.status === 'finished') this.clearResultToast();
    else if (previous && room.last_result && room.last_result.round !== previous.last_result?.round) this.showResultToast();
    if (room.status === 'finished' && (room.p1_team.length < 6 || room.p2_team.length < 6)) {
      void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
      return;
    }
    if (room.round !== previous?.round) {
      this.lastFinalizeAttempt = 0;
      this.bidAmount = Math.min(this.maxBid(), this.minimumBid());
    }
    if (room.status === 'finished') void this.saveResultIfNeeded(room);
    if (room.status === 'finished' && room.winner && room.winner !== 'draw') this.launchEndEffect(room.winner === this.myRole());
  }

  /** Efface les pop-ups et animations héritées de la partie précédente. */
  private resetGameUi(): void {
    this.clearResultToast();
    this.paymentFx.set([]);
    this.iWantReplay.set(false);
    this.endEffectFired = false;
    this.error.set('');
  }

  /** Fait s'envoler le montant payé depuis le solde du joueur qui vient de payer. */
  private showPayments(previous: PokemonAuctionRoom, room: PokemonAuctionRoom): void {
    const payments: PaymentFx[] = [];
    if (room.p1_balance < previous.p1_balance) payments.push({ id: ++this.paymentFxId, role: 'player1', amount: previous.p1_balance - room.p1_balance });
    if (room.p2_balance < previous.p2_balance) payments.push({ id: ++this.paymentFxId, role: 'player2', amount: previous.p2_balance - room.p2_balance });
    if (!payments.length) return;
    this.paymentFx.update(list => [...list, ...payments]);
    const ids = new Set(payments.map(fx => fx.id));
    setTimeout(() => this.paymentFx.update(list => list.filter(fx => !ids.has(fx.id))), 1400);
  }

  protected paymentsFor(role: 'player1' | 'player2'): PaymentFx[] { return this.paymentFx().filter(fx => fx.role === role); }

  /** Lance les confettis en cas de victoire, la pluie grise en cas de défaite. */
  private launchEndEffect(victory: boolean): void {
    if (this.endEffectFired) return;
    this.endEffectFired = true;
    if (victory) launchVictoryConfetti();
    else this.stopDefeatRain = launchDefeatRain();
  }

  private clearResultToast(): void {
    if (this.resultToastTimeout) clearTimeout(this.resultToastTimeout);
    this.resultToastTimeout = undefined;
    this.resultToast.set(null);
  }

  private showResultToast(): void {
    if (this.resultToastTimeout) clearTimeout(this.resultToastTimeout);
    this.resultToast.set(this.lastResultToast());
    this.resultToastTimeout = setTimeout(() => {
      this.resultToast.set(null);
      this.resultToastTimeout = undefined;
    }, 4500);
  }

  private async saveResultIfNeeded(room: PokemonAuctionRoom): Promise<void> {
    if (room.winner || this.resultSaving || this.myTeam().length !== 6 || this.opponentTeam().length !== 6) return;
    this.resultSaving = true;
    try { await this.supabase.savePokemonAuctionResult(this.roomId()); await this.refresh(); }
    finally { this.resultSaving = false; }
  }

  private scores(team: Pokemon[], opponent: Pokemon[]): { stats: number; coverage: number; final: number } {
    if (!team.length || !opponent.length) return { stats: 0, coverage: 0, final: 0 };
    const totals = this.allPokemon().map(p => Object.values(p.stats).reduce((a, b) => a + b, 0));
    const stats = computeStatsScore(team, { min: Math.min(...totals), max: Math.max(...totals) });
    const coverage = computeDuoCoverageScore(team, opponent);
    return { stats, coverage, final: computeFinalScore(stats, coverage) };
  }

  private teamFor(role: 'player1' | 'player2'): Pokemon[] {
    const ids = role === 'player1' ? this.room()?.p1_team ?? [] : this.room()?.p2_team ?? [];
    return ids.map(id => this.byId(id)).filter((p): p is Pokemon => !!p);
  }

  private byId(id: number | null | undefined): Pokemon | null { return this.allPokemon().find(p => p.id === id) ?? null; }

  private async loadOpponent(room: PokemonAuctionRoom): Promise<void> {
    const myId = this.supabase.getCurrentUser()?.id;
    const id = room.player1_id === myId ? room.player2_id : room.player1_id;
    const fallback = { username: 'Adversaire', avatar_url: undefined };
    const [opponent, me] = await Promise.all([
      id ? this.supabase.getProfile(id).catch(() => fallback) : Promise.resolve(null),
      myId ? this.supabase.getProfile(myId).catch(() => null) : Promise.resolve(null),
    ]);
    if (opponent) { this.opponentName.set(opponent.username); this.opponentAvatar.set(opponent.avatar_url ?? null); }
    this.myAvatar.set(me?.avatar_url ?? null);
  }

  private actionError(error: unknown): string {
    const message = error instanceof Error ? error.message : '';
    if (message.includes('invalid_bid')) return 'Cette offre dépasse ton budget disponible ou ta réserve obligatoire.';
    if (message.includes('blocking_would_exhaust_pool')) return 'Ce Pokémon ne peut plus être bloqué : il faut garantir la fin de la partie.';
    if (message.includes('bid_not_allowed') || message.includes('sealed_bid_not_allowed')) return 'Offre refusée : le temps de cette enchère est écoulé.';
    return 'Offre refusée. Le prix ou la manche a peut-être déjà changé.';
  }
}
