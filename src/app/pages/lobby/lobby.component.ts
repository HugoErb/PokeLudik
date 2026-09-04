import { Component, OnInit, OnDestroy, computed, effect, inject, input, signal, untracked, CUSTOM_ELEMENTS_SCHEMA, Injector } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { firstValueFrom, filter, take, Subscription } from 'rxjs';
import { toObservable } from '@angular/core/rxjs-interop';

import { environment } from '../../../environments/environment';
import { GameService } from '../../services/game.service';
import { PokemonService } from '../../services/pokemon.service';
import { SupabaseService } from '../../services/supabase.service';
import { Pokemon } from '../../models/pokemon.model';
import { DraftDuoRoom, GameMode, PokemonAuctionRoom, Profile, Room, StatDuelRoom, WhoPokemonRoom } from '../../models/room.model';
import { DEFAULT_MODE_SETTINGS, ModeSettings, normalizeModeSettings, resolvePendingSettingsAfterSave, toAuctionSettings, toGuessSettings, toWhoSettings } from '../../models/game-settings.model';
import { PokemonCardComponent } from '../../components/pokemon-card/pokemon-card.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import { HelpModalComponent } from '../../components/help-modal/help-modal.component';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { GameSettingsPanelComponent } from '../../components/game-settings-panel/game-settings-panel.component';
import { ICONS } from '../../constants/icons';
import { modalAnimation } from '../../constants/animations';
import { buildWhoPokemonPool, pickWhoPokemonSequence } from '../../utils/who-that-pokemon-utils';
import { resolveLobbyGameMode, shouldEnterMultiplayerGame } from '../../utils/multiplayer-room-state';

type DuelIntroPlayer = { username: string; avatar_url?: string };

@Component({
	selector: 'app-lobby',
	imports: [FormsModule, PokemonCardComponent, CancelModalComponent, HelpModalComponent, AppHeaderComponent, GameSettingsPanelComponent],
	schemas: [CUSTOM_ELEMENTS_SCHEMA],
	animations: [modalAnimation],
	templateUrl: './lobby.component.html',
	styles: [],
})
export class LobbyComponent implements OnInit, OnDestroy {
	protected readonly ICONS = ICONS;
	roomId = input.required<string>();

	private readonly gameService = inject(GameService);
	private readonly pokemonService = inject(PokemonService);
	private readonly supabaseService = inject(SupabaseService);
	private readonly router = inject(Router);
	private readonly route = inject(ActivatedRoute);
	private readonly injector = inject(Injector);

		constructor() {
			effect(() => {
				const s = this.gameService.settings();
				untracked(() => {
					if (this.gameMode !== 'guess_my_pokemon') return;
					this.gameSettings = normalizeModeSettings('guess_my_pokemon', s);
					if (this.allPokemons.length > 0) this.onSearch();
				});
			});

		effect(() => {
			const r = this.room();
			if (r?.status === 'finished' && (this.gameMode === 'guess_my_pokemon' || ('winner' in r && r.winner === null))) {
				untracked(() => {
					void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
				});
				return;
			}
			if (!this.isLoading && r === null) {
				untracked(() => {
					void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } });
				});
			}
		});

		effect(() => {
			const opponentId = this.opponentId();
			untracked(() => void this.loadOpponentProfile(opponentId));
		});
	}

	// États
	gameMode: GameMode = resolveLobbyGameMode(this.route.snapshot.queryParamMap.get('mode'));
	private readonly statDuelRoom = signal<StatDuelRoom | null>(null);
	private readonly draftDuoRoom = signal<DraftDuoRoom | null>(null);
	private readonly whoPokemonRoom = signal<WhoPokemonRoom | null>(null);
	private readonly pokemonAuctionRoom = signal<PokemonAuctionRoom | null>(null);
	room = computed<Room | StatDuelRoom | DraftDuoRoom | WhoPokemonRoom | PokemonAuctionRoom | null>(() => {
		const statRoom = this.statDuelRoom();
		const draftRoom = this.draftDuoRoom();
		const whoRoom = this.whoPokemonRoom();
		const auctionRoom = this.pokemonAuctionRoom();
		const guessRoom = this.gameService.currentRoom();
		if (this.gameMode === 'stat_duel') return statRoom;
		if (this.gameMode === 'draft_duo') return draftRoom;
		if (this.gameMode === 'who_that_pokemon') return whoRoom;
		if (this.gameMode === 'pokemon_auction') return auctionRoom;
		return guessRoom;
	});
	isPlayer1 = computed(() => {
		if (this.gameMode === 'guess_my_pokemon') return this.gameService.isPlayer1();
		const r = this.room();
		const user = this.supabaseService.currentUserSignal();
		return !!r && !!user && r.player1_id === user.id;
	});
	opponentReady = computed(() => {
		const r = this.room();
		if (!r) return false;
		return this.isPlayer1() ? r.p2_ready : r.p1_ready;
	});
	hasOpponent = computed(() => {
		const r = this.room();
		return !!r?.player2_id || (this.gameMode === 'guess_my_pokemon' && r?.status === 'ready');
	});
	opponentId = computed(() => {
		const r = this.room();
		const user = this.supabaseService.currentUserSignal();
		if (!r || !user) return null;
		return r.player1_id === user.id ? r.player2_id ?? null : r.player1_id;
	});
	opponentProfile = signal<Pick<Profile, 'id' | 'username' | 'avatar_url'> | null>(null);
	private loadingOpponentProfileId: string | null = null;

	// Sélection Pokémon
	allPokemons: Pokemon[] = [];
	filteredPokemons: Pokemon[] = [];
	visiblePokemons: Pokemon[] = [];
	selectedPokemon: Pokemon | null = null;
	searchQuery = '';
	isReady = false;
	isSettingReady = false;
	selectError = '';
	private displayedCount = 100;
	private readonly PAGE_SIZE = 100;
	private readonly INTRO_CACHE_PREFIXES = ['duel-intro-data-', 'stat-duel-intro-data-'];

	// Détails du Pokémon
	selectedPokemonDetails: Pokemon | null = null;

	// État de chargement
	isLoading = true;

	// Lien d'invitation
	inviteLink = '';
	copied = false;

	// Configuration de partie
	gameSettings: ModeSettings = { ...DEFAULT_MODE_SETTINGS.guess_my_pokemon };
	isLaunching = false;
	launchError = '';

	// UI état
	showHelpModal = signal(false);

	// Annulation / mode dev
	isCancelling = false;
	showCancelModal = signal(false);
	simulateError = '';
	isSimulating = false;
	isSimulatingReady = false;
	readonly devMode = environment.devMode;

	private pokemonsSub?: Subscription;
	private inviteResponseSub?: Subscription;
	private multiRoomSub?: Subscription;
	private pollInterval: ReturnType<typeof setInterval> | null = null;
	private pendingLocalSettings: ModeSettings | null = null;

	private readonly MODE_CONFIG: Record<GameMode, { title: string; subtitle?: string; icon: string; iconClass: string; iconSizeClass?: string; helpMode?: 'stat-duel' | 'auction'; playRoute: string }> = {
		guess_my_pokemon: { title: 'Guess my Pokémon', icon: ICONS.guess, iconClass: 'text-red-400', playRoute: '/game' },
		stat_duel: { title: 'Duel de Base Stats', subtitle: 'Deux joueurs en ligne', icon: ICONS.statDuel, iconClass: 'text-yellow-400', helpMode: 'stat-duel', playRoute: '/stat-duel' },
		draft_duo: { title: 'Team Builder', subtitle: 'Deux joueurs en ligne', icon: ICONS.draft, iconClass: 'text-purple-200', iconSizeClass: 'text-4xl', playRoute: '/draft-duo' },
		who_that_pokemon: { title: "Who's That Pokémon ?", subtitle: 'Deux joueurs en ligne', icon: ICONS.whoPokemon, iconClass: 'text-cyan-300', playRoute: '/who-that-pokemon' },
		pokemon_auction: { title: 'Enchères Pokémon', subtitle: 'Deux joueurs en ligne', icon: ICONS.auction, iconClass: 'text-orange-300', helpMode: 'auction', playRoute: '/pokemon-auction' },
	};

	/** Retourne la configuration d'affichage du mode courant. */
	get modeConfig(): { title: string; subtitle?: string; icon: string; iconClass: string; iconSizeClass?: string; helpMode?: 'stat-duel' | 'auction'; playRoute: string } {
		return this.MODE_CONFIG[this.gameMode];
	}

	/** Retourne le sous-titre du mode courant. */
	get modeSubtitle(): string {
		if (this.gameMode === 'guess_my_pokemon') return '';
		return this.modeConfig.subtitle ?? 'Lobby';
	}

	/** Retourne true si le lobby est en mode Guess my Pokemon. */
	isGuessMode(): boolean {
		return this.gameMode === 'guess_my_pokemon';
	}

	/** Lifecycle Angular — initialise le lobby. */
	ngOnInit(): void {
		void this.init();
	}

	/**
	 * Initialise le lobby : attend l'authentification, rejoint la room,
	 * construit le lien d'invitation, charge les Pokémon et observe le statut de la room.
	 */
	private async init(): Promise<void> {
		// 1. Attendre que l'auth soit prête
		await firstValueFrom(this.supabaseService.authReady$);
		this.gameMode = this.resolveMode();

		if (this.gameMode === 'stat_duel') {
			await this.initStatDuelLobby();
			return;
		}

		if (this.gameMode === 'draft_duo') {
			await this.initDraftDuoLobby();
			return;
		}

		if (this.gameMode === 'who_that_pokemon') {
			await this.initWhoPokemonLobby();
			return;
		}

		if (this.gameMode === 'pokemon_auction') {
			await this.initPokemonAuctionLobby();
			return;
		}

		// 2. Watcher Realtime mis en place AVANT joinAndWatch pour éviter la race condition :
		//    si la room passe à 'playing' pendant joinAndWatch, la navigation est garantie.
		toObservable(this.room, { injector: this.injector })
			.pipe(
				filter((r) => r?.status === 'playing'),
				take(1),
			)
			.subscribe(() => {
				void this.navigateToPlay();
			});

		// 3. Lancer joinAndWatch (Realtime)
		try {
			await this.gameService.joinAndWatch(this.roomId());
		} catch {
			void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } });
			return;
		}

		if (!this.room()) {
			void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } });
			return;
		}

		this.isLoading = false;

		// 4. Construire le lien d'invitation
		this.inviteLink = `${globalThis.location.origin}/invite/${this.roomId()}`;

		// 5. Marquer l'utilisateur comme "en jeu" dans le système de présence
		this.supabaseService.trackPresence('in_game');

		// 6. Écouter le refus si on a invité un ami directement
		const inviteId = this.route.snapshot.queryParamMap.get('inviteId');
		const friendName = this.route.snapshot.queryParamMap.get('friendName') ?? 'Ton ami';
		if (inviteId) {
			this.inviteResponseSub = this.supabaseService.subscribeToGameInviteResponse(inviteId).subscribe((invite) => {
				if (invite.status === 'declined') {
					void this.router.navigate(['/home'], { queryParams: { declined: friendName } });
				}
			});
		}

		// 5. Charger tous les Pokémon
		this.pokemonsSub = this.pokemonService.loadAll().subscribe((pokemons) => {
			this.allPokemons = pokemons;
			this.onSearch(); // applique les restrictions dès le chargement
		});
	}

	/** Lifecycle Angular — arrête le watch de la room et les abonnements. */
	ngOnDestroy(): void {
		this.gameService.stopWatching();
		this.pokemonsSub?.unsubscribe();
		this.inviteResponseSub?.unsubscribe();
		this.multiRoomSub?.unsubscribe();
		if (this.pollInterval) clearInterval(this.pollInterval);
	}

	// ─── Actions ─────────────────────────────────────────────────────────────────

	/** Sélectionne un Pokémon et l'enregistre en base si le joueur n'est pas encore prêt. */
	async selectPokemon(pokemon: Pokemon): Promise<void> {
		if (this.isReady) return;
		this.selectedPokemon = pokemon;
		this.selectError = '';
		try {
			await this.gameService.selectPokemon(this.roomId(), pokemon.id);
		} catch {
			this.selectError = 'Erreur lors de la sélection. Réessaie.';
			this.selectedPokemon = null;
		}
	}

	/** Sélectionne un Pokémon aléatoire parmi ceux autorisés par les paramètres de génération et de catégorie. */
	pickRandom(): void {
		if (this.isReady) return;
		const settings = this.gameService.settings();
		let pool = this.allPokemons;
		if (settings.generations.length > 0) pool = pool.filter((p) => settings.generations.includes(p.generation));
		if (settings.categories.length > 0) pool = pool.filter((p) => settings.categories.includes(p.category));
		if (pool.length === 0) return;
		const random = pool[Math.floor(Math.random() * pool.length)];
		void this.selectPokemon(random);
	}

	/** Filtre la liste de Pokémon selon la recherche textuelle, les générations et catégories autorisées. */
	onSearch(): void {
		const q = this.searchQuery.toLowerCase();
		const settings = this.gameService.settings();
		this.filteredPokemons = this.allPokemons.filter((p) => {
			if (q && !p.name.toLowerCase().includes(q)) return false;
			if (settings.generations.length > 0 && !settings.generations.includes(p.generation)) return false;
			if (settings.categories.length > 0 && !settings.categories.includes(p.category)) return false;
			return true;
		});
		this.displayedCount = this.PAGE_SIZE;
		this.visiblePokemons = this.filteredPokemons.slice(0, this.displayedCount);
	}

	/** Charge une nouvelle page de Pokémon lors du défilement vers le bas de la grille. */
	onGridScroll(event: Event): void {
		const el = event.target as HTMLElement;
		if (el.scrollHeight - el.scrollTop - el.clientHeight < 300 && this.displayedCount < this.filteredPokemons.length) {
			this.displayedCount += this.PAGE_SIZE;
			this.visiblePokemons = this.filteredPokemons.slice(0, this.displayedCount);
		}
	}

	/**
	 * Marque le joueur comme prêt et navigue vers la page de jeu
	 * si la partie démarre immédiatement.
	 */
	async setReady(): Promise<void> {
		if (!this.selectedPokemon || this.isSettingReady || this.isReady) return;
		this.isSettingReady = true;
		try {
			await this.gameService.setReady(this.roomId());
			this.isReady = true;
			// Navigation directe si la partie démarre (ne pas attendre le Realtime)
			if (this.room()?.status === 'playing') {
				void this.navigateToPlay();
			}
		} finally {
			this.isSettingReady = false;
		}
	}

	/** Annule la room et navigue vers l'accueil. */
	async cancelRoom(): Promise<void> {
		if (this.isCancelling) return;
		this.isCancelling = true;
		if (this.gameMode === 'guess_my_pokemon') {
			await this.gameService.cancelRoom(this.roomId()).catch(() => {
				// ignore les erreurs d'annulation
			});
		} else if (this.gameMode === 'stat_duel') {
			await this.cancelStatDuelRoom();
		} else if (this.gameMode === 'draft_duo') {
			await this.cancelDraftDuoRoom();
		} else if (this.gameMode === 'pokemon_auction') {
			await this.supabaseService.cancelPokemonAuctionRoom(this.roomId()).catch(() => undefined);
		} else {
			await this.cancelWhoPokemonRoom();
		}
		await this.router.navigate(['/home']);
	}

	/** DEV : Simule un adversaire sans compte réel dans la room. */
	async simulateOpponent(): Promise<void> {
		if (this.isSimulating) return;
		this.isSimulating = true;
		this.simulateError = '';
		try {
			if (this.gameMode === 'stat_duel') {
				await this.supabaseService.updateStatDuelRoom(this.roomId(), { player2_id: null });
				const room = await this.supabaseService.getStatDuelRoom(this.roomId());
				this.statDuelRoom.set(room);
			} else if (this.gameMode === 'draft_duo') {
				await this.supabaseService.updateDraftDuoRoom(this.roomId(), { player2_id: null });
				const room = await this.supabaseService.getDraftDuoRoom(this.roomId());
				this.draftDuoRoom.set(room);
			} else {
				await this.gameService.simulateOpponent(this.roomId());
			}
		} catch (err) {
			this.simulateError = `Erreur simulation: ${err instanceof Error ? err.message : JSON.stringify(err)}`;
		} finally {
			this.isSimulating = false;
		}
	}

	/** Lance la phase de sélection de Pokémon avec les paramètres configurés. */
	async launchGame(): Promise<void> {
		if (this.isLaunching) return;
		this.isLaunching = true;
		this.launchError = '';
		try {
			if (this.gameMode === 'stat_duel') {
				let allPokemon = await firstValueFrom(this.pokemonService.loadAll());
				if (this.gameSettings.generations.length > 0) allPokemon = allPokemon.filter(p => this.gameSettings.generations.includes(p.generation));
				if (this.gameSettings.categories.length > 0) allPokemon = allPokemon.filter(p => this.gameSettings.categories.includes(p.category));
				if (new Set(allPokemon.map(p => p.id)).size < 6) {
					throw new Error('Le pool doit contenir au moins 6 Pokemon distincts');
				}
				const pokemonIds = this.shuffle(allPokemon).slice(0, 6).map(p => p.id);
				const roundStartAt = new Date(Date.now() + 3000).toISOString();
				await this.supabaseService.updateStatDuelRoom(this.roomId(), {
					status: 'playing',
					settings: toGuessSettings(this.gameSettings),
					pokemon_ids: pokemonIds,
					round_start_at: roundStartAt,
					p1_picks: [],
					p2_picks: [],
					winner: null,
					p1_ready: false,
					p2_ready: false,
				});
				await this.preloadDuelIntroForRoom();
				void this.router.navigate([this.modeConfig.playRoute, this.roomId()]);
			} else if (this.gameMode === 'draft_duo') {
				let allPokemon = await firstValueFrom(this.pokemonService.loadAll());
				if (this.gameSettings.generations.length > 0) allPokemon = allPokemon.filter(p => this.gameSettings.generations.includes(p.generation));
				if (this.gameSettings.categories.length > 0) allPokemon = allPokemon.filter(p => this.gameSettings.categories.includes(p.category));
				if (new Set(allPokemon.map(p => p.id)).size < 6) {
					throw new Error('Le pool doit contenir au moins 6 Pokemon distincts');
				}
				await this.supabaseService.updateDraftDuoRoom(this.roomId(), {
					status: 'playing',
					settings: toGuessSettings(this.gameSettings),
					p1_team: [],
					p2_team: [],
					winner: null,
					p1_ready: false,
					p2_ready: false,
				});
				void this.router.navigate([this.modeConfig.playRoute, this.roomId()]);
			} else if (this.gameMode === 'pokemon_auction') {
				let allPokemon = await firstValueFrom(this.pokemonService.loadAll());
				if (this.gameSettings.generations.length) allPokemon = allPokemon.filter(p => this.gameSettings.generations.includes(p.generation));
				if (this.gameSettings.categories.length) allPokemon = allPokemon.filter(p => this.gameSettings.categories.includes(p.category));
				if (new Set(allPokemon.map(p => p.id)).size < 12) throw new Error('Le pool doit contenir au moins 12 Pokemon distincts');
				await this.supabaseService.launchPokemonAuctionRoom(this.roomId(), toAuctionSettings(this.gameSettings));
				void this.router.navigate([this.modeConfig.playRoute, this.roomId()]);
			} else if (this.gameMode === 'who_that_pokemon') {
				let pokemons = this.allPokemons;
				if (pokemons.length === 0) {
					pokemons = await firstValueFrom(this.pokemonService.loadAll());
					this.allPokemons = pokemons;
				}
				const settings = toWhoSettings(this.gameSettings);
				const target = pickWhoPokemonSequence(buildWhoPokemonPool(pokemons, settings), 1)[0];
				if (!target) throw new Error('Aucun Pokémon disponible');
				await this.supabaseService.updateWhoPokemonRoom(this.roomId(), {
					status: 'playing',
					settings,
					round: 1,
					target_pokemon_id: target.id,
					used_pokemon_ids: [target.id],
					p1_score: 0,
					p2_score: 0,
					p1_lives: 0,
					p2_lives: 0,
					winner: null,
					p1_ready: false,
					p2_ready: false,
				});
				void this.router.navigate([this.modeConfig.playRoute, this.roomId()]);
			} else {
				await this.gameService.launchGame(this.roomId(), toGuessSettings(this.gameSettings));
			}
		} catch (error) {
			this.launchError = error instanceof Error && error.message.includes('au moins')
				? `Ces filtres doivent laisser au moins ${this.gameMode === 'pokemon_auction' ? 12 : 6} Pokémon distincts.`
				: 'Erreur lors du lancement. Réessaie.';
		} finally {
			this.isLaunching = false;
		}
	}

	updateGameSettings(settings: ModeSettings): void {
		if (!this.isPlayer1()) return;
		if (this.isConfigLocked()) return;
		this.gameSettings = settings;
		this.pendingLocalSettings = settings;
		void this.saveSettings(settings).then((saved) => {
			this.pendingLocalSettings = resolvePendingSettingsAfterSave(this.pendingLocalSettings, settings, saved);
		});
	}

	/** Retourne true si la configuration ne peut plus être modifiée (partie déjà lancée). */
    isConfigLocked(): boolean {
        return this.room()?.status === 'selecting' || this.room()?.status === 'playing';
    }

	/** Sauvegarde les paramètres de la partie en base de données. */
	private async saveSettings(settings: ModeSettings): Promise<boolean> {
		try {
			if (this.gameMode === 'guess_my_pokemon') {
				await this.gameService.updateSettings(this.roomId(), toGuessSettings(settings));
			} else if (this.gameMode === 'who_that_pokemon') {
				await this.supabaseService.updateWhoPokemonRoom(this.roomId(), { settings: toWhoSettings(settings) });
			} else if (this.gameMode === 'stat_duel') {
				await this.supabaseService.updateStatDuelRoom(this.roomId(), { settings: toGuessSettings(settings) });
			} else if (this.gameMode === 'draft_duo') {
				await this.supabaseService.updateDraftDuoRoom(this.roomId(), { settings: toGuessSettings(settings) });
			} else if (this.gameMode === 'pokemon_auction') {
				await this.supabaseService.setPokemonAuctionSettings(this.roomId(), toAuctionSettings(settings));
			}
			return true;
		} catch {
			return false;
			// ignore les erreurs de sauvegarde des paramètres
		}
	}

	private syncRemoteSettings(mode: GameMode, settings: Partial<ModeSettings> | null | undefined): void {
		const remoteSettings = normalizeModeSettings(mode, settings);
		if (this.pendingLocalSettings && this.isPlayer1() && !this.isConfigLocked()) {
			if (this.sameSettings(remoteSettings, this.pendingLocalSettings)) {
				this.pendingLocalSettings = null;
			} else {
				return;
			}
		}
		this.gameSettings = remoteSettings;
	}

	private sameSettings(a: ModeSettings | null | undefined, b: ModeSettings | null | undefined): boolean {
		return JSON.stringify(a) === JSON.stringify(b);
	}

	/** Charge l'identité du joueur situé de l'autre côté de la room. */
	private async loadOpponentProfile(opponentId: string | null): Promise<void> {
		if (!opponentId) {
			this.opponentProfile.set(null);
			this.loadingOpponentProfileId = null;
			return;
		}
		if (this.opponentProfile()?.id === opponentId || this.loadingOpponentProfileId === opponentId) return;

		this.loadingOpponentProfileId = opponentId;
		try {
			const profile = await this.supabaseService.getProfile(opponentId);
			if (this.opponentId() === opponentId) {
				this.opponentProfile.set({ id: profile.id, username: profile.username, avatar_url: profile.avatar_url });
			}
		} catch {
			if (this.opponentId() === opponentId) {
				this.opponentProfile.set({ id: opponentId, username: 'Adversaire', avatar_url: undefined });
			}
		} finally {
			if (this.loadingOpponentProfileId === opponentId) this.loadingOpponentProfileId = null;
		}
	}

	/**
	 * DEV : Simule l'adversaire en choisissant un Pokémon aléatoire et en passant prêt,
	 * puis navigue directement vers la page de jeu.
	 */
	async simulateOpponentReady(): Promise<void> {
		if (this.isSimulatingReady) return;
		this.isSimulatingReady = true;
		try {
			let pokemons = this.allPokemons;
			if (pokemons.length === 0) {
				pokemons = await firstValueFrom(this.pokemonService.loadAll());
			}

			// RESTRICTION: Filtrer par génération si nécessaire
			const restrictedGens = this.gameService.settings().generations;
			if (restrictedGens.length > 0) {
				pokemons = pokemons.filter((p) => restrictedGens.includes(p.generation));
			}

			if (pokemons.length === 0) return;
			const randomPokemon = pokemons[Math.floor(Math.random() * pokemons.length)];
			await this.gameService.simulateOpponentReady(this.roomId(), randomPokemon.id);
			// Navigation directe : simulateOpponentReady passe toujours à 'playing'
			void this.navigateToPlay();
		} finally {
			this.isSimulatingReady = false;
		}
	}

	/** Copie le lien d'invitation dans le presse-papiers (avec fallback pour HTTP). */
	async copyInviteLink(): Promise<void> {
		try {
			await navigator.clipboard.writeText(this.inviteLink);
		} catch {
			// Fallback pour HTTP
			const el = document.createElement('input');
			el.value = this.inviteLink;
			document.body.appendChild(el);
			el.select();
			document.execCommand('copy');
			document.body.removeChild(el);
		}
		this.copied = true;
		setTimeout(() => (this.copied = false), 2000);
	}

	// ─── Modal Pokédex ───────────────────────────────────────────────────────────

	/** Ouvre la modal de détails d'un Pokémon. */
	openPokemonDetails(pokemon: Pokemon): void {
		this.selectedPokemonDetails = pokemon;
	}

	/** Ferme la modal de détails d'un Pokémon. */
	closePokemonDetails(): void {
		this.selectedPokemonDetails = null;
	}

	/** Sélectionne le Pokémon depuis la modal de détails et ferme celle-ci. */
	selectFromDetails(pokemon: Pokemon): void {
		void this.selectPokemon(pokemon);
		this.closePokemonDetails();
	}

	// ─── Modal d'annulation ──────────────────────────────────────────────────────

	/** Affiche la modal de confirmation d'annulation. */
	promptCancel(): void {
		this.showCancelModal.set(true);
	}

	/** Ferme la modal de confirmation d'annulation. */
	closeCancelModal(): void {
		this.showCancelModal.set(false);
	}

	/** Confirme l'annulation et quitte le lobby. */
	confirmCancel(): void {
		this.closeCancelModal();
		this.cancelRoom();
	}

	/** Resout le mode de jeu depuis les parametres de route. */
	private resolveMode(): GameMode {
		return resolveLobbyGameMode(this.route.snapshot.queryParamMap.get('mode'));
	}

	/** Initialise le lobby Duel de Base Stats. */
	private async initStatDuelLobby(): Promise<void> {
		try {
			let room = await this.supabaseService.getStatDuelRoom(this.roomId());
			this.syncRemoteSettings('stat_duel', room.settings);
			const user = this.supabaseService.getCurrentUser();
			if (user && !room.player2_id && room.player1_id !== user.id) {
				await this.supabaseService.joinStatDuelRoom(this.roomId());
				room = await this.supabaseService.getStatDuelRoom(this.roomId());
			}
			this.statDuelRoom.set(room);
			this.isLoading = false;
			this.inviteLink = `${globalThis.location.origin}/invite/${this.roomId()}?mode=stat_duel`;
			this.supabaseService.trackPresence('in_game');
			this.subscribeInviteDecline();
			if (room.status === 'finished') {
				void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
			} else if (shouldEnterMultiplayerGame(room)) void this.navigateToPlay();
			this.multiRoomSub = this.supabaseService.subscribeToStatDuelRoom(this.roomId()).subscribe((updated) => {
				this.statDuelRoom.set(updated);
				this.syncRemoteSettings('stat_duel', updated.settings);
				if (updated.status === 'finished') {
					void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
					return;
				}
				if (shouldEnterMultiplayerGame(updated)) void this.navigateToPlay();
			});
			this.startMultiPoll();
		} catch {
			void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } });
		}
	}

	/** Initialise le lobby Draft Duo. */
	private async initDraftDuoLobby(): Promise<void> {
		try {
			let room = await this.supabaseService.getDraftDuoRoom(this.roomId());
			this.syncRemoteSettings('draft_duo', room.settings);
			const user = this.supabaseService.getCurrentUser();
			if (user && !room.player2_id && room.player1_id !== user.id) {
				await this.supabaseService.joinDraftDuoRoom(this.roomId());
				room = await this.supabaseService.getDraftDuoRoom(this.roomId());
			}
			this.draftDuoRoom.set(room);
			this.isLoading = false;
			this.inviteLink = `${globalThis.location.origin}/invite/${this.roomId()}?mode=draft_duo`;
			this.supabaseService.trackPresence('in_game');
			this.subscribeInviteDecline();
			if (room.status === 'finished') {
				void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
			} else if (shouldEnterMultiplayerGame(room)) void this.navigateToPlay();
			this.multiRoomSub = this.supabaseService.subscribeToDraftDuoRoom(this.roomId()).subscribe((updated) => {
				this.draftDuoRoom.set(updated);
				this.syncRemoteSettings('draft_duo', updated.settings);
				if (updated.status === 'finished') {
					void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
					return;
				}
				if (shouldEnterMultiplayerGame(updated)) void this.navigateToPlay();
			});
			this.startMultiPoll();
		} catch {
			void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } });
		}
	}

	/** Initialise le lobby Enchères Pokémon. */
	private async initPokemonAuctionLobby(): Promise<void> {
		try {
			let room = await this.supabaseService.getPokemonAuctionRoom(this.roomId());
			this.syncRemoteSettings('pokemon_auction', room.settings);
			const user = this.supabaseService.getCurrentUser();
			if (user && !room.player2_id && room.player1_id !== user.id) {
				await this.supabaseService.joinPokemonAuctionRoom(this.roomId());
				room = await this.supabaseService.getPokemonAuctionRoom(this.roomId());
			}
			this.pokemonAuctionRoom.set(room);
			this.isLoading = false;
			this.inviteLink = `${globalThis.location.origin}/invite/${this.roomId()}?mode=pokemon_auction`;
			this.supabaseService.trackPresence('in_game');
			this.subscribeInviteDecline();
			if (room.status === 'finished') void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
			else if (shouldEnterMultiplayerGame(room)) void this.navigateToPlay();
			this.multiRoomSub = this.supabaseService.subscribeToPokemonAuctionRoom(this.roomId()).subscribe(updated => {
				this.pokemonAuctionRoom.set(updated);
				this.syncRemoteSettings('pokemon_auction', updated.settings);
				if (updated.status === 'finished') void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
				else if (shouldEnterMultiplayerGame(updated)) void this.navigateToPlay();
			});
			this.startMultiPoll();
		} catch { void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } }); }
	}

	/** Initialise le lobby Who's That Pokemon. */
	private async initWhoPokemonLobby(): Promise<void> {
		try {
			let room = await this.supabaseService.getWhoPokemonRoom(this.roomId());
			this.syncRemoteSettings('who_that_pokemon', room.settings);
			const user = this.supabaseService.getCurrentUser();
			if (user && !room.player2_id && room.player1_id !== user.id) {
				await this.supabaseService.joinWhoPokemonRoom(this.roomId());
				room = await this.supabaseService.getWhoPokemonRoom(this.roomId());
			}
			this.whoPokemonRoom.set(room);
			this.isLoading = false;
			this.inviteLink = `${globalThis.location.origin}/invite/${this.roomId()}?mode=who_that_pokemon`;
			this.supabaseService.trackPresence('in_game');
			this.subscribeInviteDecline();
			if (room.status === 'finished') {
				void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
			} else if (shouldEnterMultiplayerGame(room)) void this.navigateToPlay();
			this.multiRoomSub = this.supabaseService.subscribeToWhoPokemonRoom(this.roomId()).subscribe((updated) => {
				this.whoPokemonRoom.set(updated);
				this.syncRemoteSettings('who_that_pokemon', updated.settings);
				if (updated.status === 'finished') {
					void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
					return;
				}
				if (shouldEnterMultiplayerGame(updated)) void this.navigateToPlay();
			});
			this.startMultiPoll();
			this.pokemonsSub = this.pokemonService.loadAll().subscribe((pokemons) => {
				this.allPokemons = pokemons;
			});
		} catch {
			void this.router.navigate(['/home'], { queryParams: { roomNotFound: true } });
		}
	}

	/** S'abonne au refus d'invitation associe au lobby. */
	private subscribeInviteDecline(): void {
		const inviteId = this.route.snapshot.queryParamMap.get('inviteId');
		const friendName = this.route.snapshot.queryParamMap.get('friendName') ?? 'Ton ami';
		if (inviteId) {
			this.inviteResponseSub = this.supabaseService.subscribeToGameInviteResponse(inviteId).subscribe((invite) => {
				if (invite.status === 'declined') {
					void this.router.navigate(['/home'], { queryParams: { declined: friendName } });
				}
			});
		}
	}

	/** Demarre le polling des rooms multijoueur. */
	private startMultiPoll(): void {
		this.pollInterval = setInterval(async () => {
			try {
				if (this.gameMode === 'stat_duel') {
					const room = await this.supabaseService.getStatDuelRoom(this.roomId());
					this.statDuelRoom.set(room);
					this.syncRemoteSettings('stat_duel', room.settings);
					if (room.status === 'finished') {
						void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
						return;
					}
					if (shouldEnterMultiplayerGame(room)) void this.navigateToPlay();
				} else if (this.gameMode === 'draft_duo') {
					const room = await this.supabaseService.getDraftDuoRoom(this.roomId());
					this.draftDuoRoom.set(room);
					this.syncRemoteSettings('draft_duo', room.settings);
					if (room.status === 'finished') {
						void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
						return;
					}
					if (shouldEnterMultiplayerGame(room)) void this.navigateToPlay();
				} else if (this.gameMode === 'who_that_pokemon') {
					const room = await this.supabaseService.getWhoPokemonRoom(this.roomId());
					this.whoPokemonRoom.set(room);
					this.syncRemoteSettings('who_that_pokemon', room.settings);
					if (room.status === 'finished') {
						void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
						return;
					}
					if (shouldEnterMultiplayerGame(room)) void this.navigateToPlay();
				} else if (this.gameMode === 'pokemon_auction') {
					const room = await this.supabaseService.getPokemonAuctionRoom(this.roomId());
					this.pokemonAuctionRoom.set(room);
					this.syncRemoteSettings('pokemon_auction', room.settings);
					if (room.status === 'finished') { void this.router.navigate(['/home'], { queryParams: { gameEnded: true } }); return; }
					if (shouldEnterMultiplayerGame(room)) void this.navigateToPlay();
				}
			} catch {
				// ignore les erreurs de polling
			}
		}, 2000);
	}

	/** Termine une room Duel de Base Stats apres confirmation d'abandon. */
	private async cancelStatDuelRoom(): Promise<void> {
		await this.supabaseService.broadcastPlayerLeft().catch(() => undefined);
		await this.supabaseService.updateStatDuelRoom(this.roomId(), {
			status: 'finished',
			winner: null,
			p1_ready: false,
			p2_ready: false,
		}).catch(() => undefined);
	}

	/** Termine une room Draft Duo apres confirmation d'abandon. */
	private async cancelDraftDuoRoom(): Promise<void> {
		await this.supabaseService.broadcastPlayerLeft().catch(() => undefined);
		await this.supabaseService.updateDraftDuoRoom(this.roomId(), {
			status: 'finished',
			winner: null,
			p1_ready: false,
			p2_ready: false,
		}).catch(() => undefined);
	}

	/** Termine une room Who's That Pokemon apres confirmation d'abandon. */
	private async cancelWhoPokemonRoom(): Promise<void> {
		await this.supabaseService.broadcastPlayerLeft().catch(() => undefined);
		await this.supabaseService.updateWhoPokemonRoom(this.roomId(), {
			status: 'finished',
			winner: null,
		}).catch(() => undefined);
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

	/** Navigue vers la page de jeu du mode courant. */
	private async navigateToPlay(): Promise<void> {
		const duelIntroPlayers = await this.preloadDuelIntroForRoom();
		void this.router.navigate([this.modeConfig.playRoute, this.roomId()], {
			state: duelIntroPlayers ? { duelIntroPlayers } : undefined,
		});
	}

	/** Precharge l'intro de duel pour la room courante. */
	private async preloadDuelIntroForRoom(): Promise<DuelIntroPlayer[] | null> {
		const room = this.room();
		if (!room || this.gameMode === 'draft_duo' || this.gameMode === 'pokemon_auction') return null;

		const key = this.gameMode === 'stat_duel'
			? `stat-duel-intro-data-${this.roomId()}`
			: `duel-intro-data-${this.roomId()}`;

		const fetchProfile = (id: string | null, fallback: string) =>
			id
				? this.supabaseService.getProfile(id).catch(() => ({ username: fallback, avatar_url: undefined }))
				: Promise.resolve({ username: fallback, avatar_url: undefined });

		const [p1, p2] = await Promise.all([
			fetchProfile(room.player1_id, 'Joueur 1'),
			fetchProfile(room.player2_id ?? null, 'Bot'),
		]);

		const players = [
			{ username: p1.username, avatar_url: p1.avatar_url },
			{ username: p2.username, avatar_url: p2.avatar_url },
		];

		this.cacheDuelIntroData(key, players);
		await this.preloadIntroImages(players);
		return players;
	}

	/** Met en cache l'intro sans stocker les avatars base64 volumineux. */
	private cacheDuelIntroData(key: string, players: DuelIntroPlayer[]): void {
		const cachedPlayers = players.map(player => ({
			username: player.username,
			avatar_url: player.avatar_url?.startsWith('data:') ? undefined : player.avatar_url,
		}));

		try {
			sessionStorage.setItem(key, JSON.stringify(cachedPlayers));
		} catch (error) {
			if (!(error instanceof DOMException) || error.name !== 'QuotaExceededError') return;

			this.clearDuelIntroCache();
			try {
				sessionStorage.setItem(key, JSON.stringify(cachedPlayers));
			} catch {
				// Le cache d'intro est optionnel : la page de jeu rechargera les profils.
			}
		}
	}

	/** Supprime les anciens caches d'intro pour liberer le sessionStorage. */
	private clearDuelIntroCache(): void {
		for (let i = sessionStorage.length - 1; i >= 0; i--) {
			const key = sessionStorage.key(i);
			if (key && this.INTRO_CACHE_PREFIXES.some(prefix => key.startsWith(prefix))) {
				sessionStorage.removeItem(key);
			}
		}
	}

	/** Precharge les avatars de l'intro de duel. */
	private preloadIntroImages(players: DuelIntroPlayer[]): Promise<void[]> {
		return Promise.all(
			players
				.filter(p => p.avatar_url)
				.map(p => new Promise<void>(resolve => {
					const img = new Image();
					img.onload = img.onerror = () => resolve();
					img.src = p.avatar_url!;
				}))
		);
	}
}
