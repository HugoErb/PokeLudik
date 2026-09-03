import { Component, computed, CUSTOM_ELEMENTS_SCHEMA, inject, input, OnDestroy, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { NgClass } from '@angular/common';
import { Router } from '@angular/router';
import { Subscription, firstValueFrom } from 'rxjs';
import { Pokemon } from '../../models/pokemon.model';
import { PokemonAuctionRoom } from '../../models/room.model';
import { SupabaseService } from '../../services/supabase.service';
import { PokemonService } from '../../services/pokemon.service';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import { EndGameActionsComponent } from '../../components/end-game-actions/end-game-actions.component';
import { PokemonStatsGridComponent } from '../../components/pokemon-stats-grid/pokemon-stats-grid.component';
import { ICONS } from '../../constants/icons';
import { TYPE_COLORS, TYPE_ICONS } from '../../constants/type-chart';
import { computeDuoCoverageScore, computeStatsScore } from '../../utils/draft-utils';
import { auctionFormatLabel, getMaximumAuctionBid } from '../../utils/auction-utils';

@Component({
  selector: 'app-pokemon-auction',
  standalone: true,
  imports: [FormsModule, NgClass, AppHeaderComponent, CancelModalComponent, EndGameActionsComponent, PokemonStatsGridComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './pokemon-auction.component.html',
})
export class PokemonAuctionComponent implements OnInit, OnDestroy {
  readonly roomId = input.required<string>();
  protected readonly ICONS = ICONS;
  protected readonly TYPE_COLORS = TYPE_COLORS;
  protected readonly TYPE_ICONS = TYPE_ICONS;

  private readonly supabase = inject(SupabaseService);
  private readonly pokemonService = inject(PokemonService);
  private readonly router = inject(Router);
  private roomSub?: Subscription;
  private timer?: ReturnType<typeof setInterval>;
  private poll?: ReturnType<typeof setInterval>;
  private resultSaving = false;
  private finalizedRound = 0;

  readonly room = signal<PokemonAuctionRoom | null>(null);
  readonly allPokemon = signal<Pokemon[]>([]);
  readonly now = signal(Date.now());
  readonly loading = signal(true);
  readonly actionPending = signal(false);
  readonly error = signal('');
  readonly showCancel = signal(false);
  readonly isCancelling = signal(false);
  readonly iWantReplay = signal(false);
  readonly opponentName = signal('Adversaire');
  bidAmount = 10;

  readonly isPlayer1 = computed(() => this.room()?.player1_id === this.supabase.currentUserSignal()?.id);
  readonly myRole = computed(() => this.isPlayer1() ? 'player1' : 'player2');
  readonly opponentRole = computed(() => this.isPlayer1() ? 'player2' : 'player1');
  readonly currentPokemon = computed(() => this.byId(this.room()?.current_pokemon_id));
  readonly myTeam = computed(() => this.teamFor(this.myRole()));
  readonly opponentTeam = computed(() => this.teamFor(this.opponentRole()));
  readonly myBalance = computed(() => this.isPlayer1() ? this.room()?.p1_balance ?? 0 : this.room()?.p2_balance ?? 0);
  readonly opponentBalance = computed(() => this.isPlayer1() ? this.room()?.p2_balance ?? 0 : this.room()?.p1_balance ?? 0);
  readonly maxBid = computed(() => getMaximumAuctionBid(this.myBalance(), this.myTeam().length));
  readonly minimumBid = computed(() => Math.max(10, (this.room()?.current_bid ?? 0) + 10));
  readonly formatLabel = computed(() => auctionFormatLabel(this.room()?.settings?.auctionFormat ?? 'live'));
  readonly timeLeft = computed(() => {
    const start = new Date(this.room()?.auction_start_at ?? 0).getTime();
    const end = new Date(this.room()?.auction_end_at ?? 0).getTime();
    return Math.max(0, Math.ceil((end - Math.max(this.now(), start)) / 1000));
  });
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
    this.allPokemon.set(await firstValueFrom(this.pokemonService.loadAll()));
    try {
      const initial = await this.supabase.getPokemonAuctionRoom(this.roomId());
      await this.loadOpponent(initial);
      this.onRoom(initial);
      this.roomSub = this.supabase.subscribeToPokemonAuctionRoom(this.roomId()).subscribe(room => this.onRoom(room));
      this.timer = setInterval(() => this.tick(), 250);
      this.poll = setInterval(() => void this.refresh(), 2000);
      this.supabase.trackPresence('in_game');
    } catch { void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } }); }
    this.loading.set(false);
  }

  ngOnDestroy(): void {
    this.roomSub?.unsubscribe();
    if (this.timer) clearInterval(this.timer);
    if (this.poll) clearInterval(this.poll);
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
    const room = this.room(); if (!room || !this.canAct()) return;
    this.actionPending.set(true); this.error.set('');
    try {
      if (room.settings?.auctionFormat === 'sealed') await this.supabase.submitPokemonAuctionSealedBid(this.roomId(), 0);
      else await this.supabase.passPokemonAuctionTurn(this.roomId());
      await this.refresh();
    } catch { this.error.set('Action refusée. La manche a peut-être déjà changé.'); }
    finally { this.actionPending.set(false); }
  }

  protected lastResultText(): string {
    const result = this.room()?.last_result; if (!result) return '';
    const revealedBids = this.room()?.settings?.auctionFormat === 'sealed'
      ? ` Offres révélées : ${result.p1Bid ?? 0} ₽ / ${result.p2Bid ?? 0} ₽.`
      : '';
    if (result.outcome === 'tied') return `Égalité : ce Pokémon reviendra plus tard.${revealedBids}`;
    const who = result.winner === this.myRole() ? 'Tu remportes' : `${this.opponentName()} remporte`;
    if (result.outcome === 'free') return `${who} le Pokémon gratuitement.${revealedBids}`;
    if (result.outcome === 'blocked') return `${who} le blocage pour ${result.price} ₽.${revealedBids}`;
    return `${who} le Pokémon pour ${result.price} ₽.${revealedBids}`;
  }

  protected typeColor(type: string): string { return TYPE_COLORS[type] ?? 'bg-gray-500'; }
  protected typeIcon(type: string): string { return TYPE_ICONS[type] ?? 'mdi:circle-outline'; }
  protected getPokemon(id: number): Pokemon | null { return this.byId(id); }

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

  private tick(): void {
    this.now.set(Date.now());
    const room = this.room();
    if (room?.status === 'playing' && room.current_pokemon_id && this.timeLeft() === 0 && this.finalizedRound !== room.round) {
      this.finalizedRound = room.round;
      void this.supabase.finalizePokemonAuction(this.roomId()).then(() => this.refresh()).catch(() => { this.finalizedRound = 0; });
    }
  }

  private onRoom(room: PokemonAuctionRoom): void {
    const previousRound = this.room()?.round;
    const previousStatus = this.room()?.status;
    this.room.set(room);
    if (room.status === 'finished' && (room.p1_team.length < 6 || room.p2_team.length < 6)) {
      void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
      return;
    }
    if (room.round !== previousRound) {
      this.finalizedRound = 0;
      this.bidAmount = Math.min(this.maxBid(), this.minimumBid());
    }
    if (previousStatus === 'finished' && room.status === 'playing') this.iWantReplay.set(false);
    if (room.status === 'finished') void this.saveResultIfNeeded(room);
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
    return { stats, coverage, final: Math.round(((stats + coverage) / 2) * 10) / 10 };
  }

  private teamFor(role: 'player1' | 'player2'): Pokemon[] {
    const ids = role === 'player1' ? this.room()?.p1_team ?? [] : this.room()?.p2_team ?? [];
    return ids.map(id => this.byId(id)).filter((p): p is Pokemon => !!p);
  }

  private byId(id: number | null | undefined): Pokemon | null { return this.allPokemon().find(p => p.id === id) ?? null; }

  private async loadOpponent(room: PokemonAuctionRoom): Promise<void> {
    const id = room.player1_id === this.supabase.getCurrentUser()?.id ? room.player2_id : room.player1_id;
    if (id) this.opponentName.set((await this.supabase.getProfile(id).catch(() => ({ username: 'Adversaire' }))).username);
  }

  private actionError(error: unknown): string {
    const message = error instanceof Error ? error.message : '';
    if (message.includes('invalid_bid')) return 'Cette offre dépasse ton budget disponible ou ta réserve obligatoire.';
    if (message.includes('blocking_would_exhaust_pool')) return 'Ce Pokémon ne peut plus être bloqué : il faut garantir la fin de la partie.';
    return 'Offre refusée. Le prix ou la manche a peut-être déjà changé.';
  }
}
