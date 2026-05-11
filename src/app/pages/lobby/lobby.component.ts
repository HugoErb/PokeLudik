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
import { DEFAULT_SETTINGS, DraftDuoRoom, FirstPlayer, GameMode, GameSettings, Room, StatDuelRoom } from '../../models/room.model';
import { PokemonCardComponent } from '../../components/pokemon-card/pokemon-card.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import { HelpModalComponent } from '../../components/help-modal/help-modal.component';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';
import { ICONS } from '../../constants/icons';
import { modalAnimation } from '../../constants/animations';

type DuelIntroPlayer = { username: string; avatar_url?: string };

@Component({
	selector: 'app-lobby',
	imports: [FormsModule, PokemonCardComponent, CancelModalComponent, HelpModalComponent, AppHeaderComponent],
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
				this.gameSettings = { ...s };
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
	}

	// États
	gameMode: GameMode = 'guess_my_pokemon';
	private readonly statDuelRoom = signal<StatDuelRoom | null>(null);
	private readonly draftDuoRoom = signal<DraftDuoRoom | null>(null);
	room = computed<Room | StatDuelRoom | DraftDuoRoom | null>(() => {
		const statRoom = this.statDuelRoom();
		const draftRoom = this.draftDuoRoom();
		const guessRoom = this.gameService.currentRoom();
		if (this.gameMode === 'stat_duel') return statRoom;
		if (this.gameMode === 'draft_duo') return draftRoom;
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

	// Configuration de partie (Player 1 uniquement, phase 'waiting'/'ready')
	gameSettings: GameSettings = { ...DEFAULT_SETTINGS };
	isLaunching = false;
	launchError = '';

	// UI état
	showSettings = signal(false);
	showHelpModal = signal(false);

	/** Retourne le nombre de parametres actifs. */
	get activeSettingsCount(): number {
		const s = this.gameSettings;
		let count = 0;
		if (s.generations.length > 0) count++;
		if (s.categories.length > 0) count++;
		if (s.noPokedex) count++;
		if (s.noSearch) count++;
		if (s.randomPokemon) count++;
		if (s.firstPlayer !== 'random') count++;
		return count;
	}

	// Annulation / mode dev
	isCancelling = false;
	showCancelModal = signal(false);
	simulateError = '';
	isSimulating = false;
	isSimulatingReady = false;
	readonly devMode = environment.devMode;
	readonly firstPlayerOptions: { value: FirstPlayer; label: string }[] = [
		{ value: 'random', label: 'Aléatoire' },
		{ value: 'player1', label: 'Vous' },
		{ value: 'player2', label: 'Adversaire' },
	];

	readonly ALL_GENERATIONS = [1, 2, 3, 4, 5, 6, 7, 8, 9];
	readonly ALL_CATEGORIES: string[] = [
		'classique', 'starter', 'légendaire', 'fabuleux', 'fossile',
		'ultra-chimère', 'pseudo-légendaire', 'bébé', 'paradoxe',
	];
	readonly CATEGORY_LABELS: Record<string, string> = {
		'classique': 'Classique',
		'starter': 'Starter',
		'légendaire': 'Légendaire',
		'fabuleux': 'Fabuleux',
		'fossile': 'Fossile',
		'ultra-chimère': 'Ultra-Chimère',
		'pseudo-légendaire': 'Pseudo-Lég.',
		'bébé': 'Bébé',
		'paradoxe': 'Paradoxe',
	};

	private pokemonsSub?: Subscription;
	private inviteResponseSub?: Subscription;
	private multiRoomSub?: Subscription;
	private pollInterval: ReturnType<typeof setInterval> | null = null;

	private readonly MODE_CONFIG: Record<GameMode, { title: string; subtitle?: string; icon: string; iconClass: string; helpMode?: 'stat-duel'; playRoute: string }> = {
		guess_my_pokemon: { title: 'Guess my Pokémon', icon: ICONS.guess, iconClass: 'text-red-400', playRoute: '/game' },
		stat_duel: { title: 'Duel de Base Stats', subtitle: 'Deux joueurs en ligne', icon: ICONS.statDuel, iconClass: 'text-yellow-400', helpMode: 'stat-duel', playRoute: '/stat-duel' },
		draft_duo: { title: 'Team Builder', subtitle: 'Deux joueurs en ligne', icon: ICONS.draft, iconClass: 'text-purple-200', playRoute: '/draft-duo' },
	};

	/** Retourne la configuration d'affichage du mode courant. */
	get modeConfig(): { title: string; subtitle?: string; icon: string; iconClass: string; helpMode?: 'stat-duel'; playRoute: string } {
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
	cancelRoom(): void {
		if (this.isCancelling) return;
		this.isCancelling = true;
		if (this.gameMode === 'guess_my_pokemon') {
			void this.gameService.cancelRoom(this.roomId()).catch(() => {
				// ignore les erreurs d'annulation
			});
		} else if (this.gameMode === 'stat_duel') {
			void this.cancelStatDuelRoom();
		} else {
			void this.cancelDraftDuoRoom();
		}
		void this.router.navigate(['/home']);
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
				const allPokemon = await firstValueFrom(this.pokemonService.loadAll());
				const pokemonIds = this.shuffle(allPokemon).slice(0, 6).map(p => p.id);
				const roundStartAt = new Date(Date.now() + 3000).toISOString();
				await this.supabaseService.updateStatDuelRoom(this.roomId(), {
					status: 'playing',
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
				await this.supabaseService.updateDraftDuoRoom(this.roomId(), {
					status: 'playing',
					p1_team: [],
					p2_team: [],
					winner: null,
					p1_ready: false,
					p2_ready: false,
				});
				void this.router.navigate([this.modeConfig.playRoute, this.roomId()]);
			} else {
				await this.gameService.launchGame(this.roomId(), this.gameSettings);
			}
		} catch {
			this.launchError = 'Erreur lors du lancement. Réessaie.';
		} finally {
			this.isLaunching = false;
		}
	}

	/** Active ou désactive la restriction par génération (tout ou la génération 1 par défaut). */
	toggleGenMode(): void {
		if (this.isConfigLocked()) return;
		const wasActive = this.gameSettings.generations.length > 0;
		this.gameSettings = { ...this.gameSettings, generations: wasActive ? [] : [1] };
		void this.saveSettings();
	}

	/** Ajoute ou retire une génération de la liste des générations restreintes. */
	toggleGeneration(gen: number): void {
		if (this.isConfigLocked()) return;
		const gens = this.gameSettings.generations;
		const filtered = gens.filter((g) => g !== gen);
		const newGens = gens.includes(gen) ? (filtered.length === 0 ? [gen] : filtered) : [...gens, gen];
		this.gameSettings = { ...this.gameSettings, generations: newGens };
		void this.saveSettings();
	}

	/** Sélectionne toutes les générations. */
	selectAllGenerations(): void {
		if (this.isConfigLocked()) return;
		this.gameSettings = { ...this.gameSettings, generations: [...this.ALL_GENERATIONS] };
		void this.saveSettings();
	}

	/** Désélectionne toutes les générations (une seule reste sélectionnée). */
	clearAllGenerations(): void {
		if (this.isConfigLocked()) return;
		this.gameSettings = { ...this.gameSettings, generations: [1] };
		void this.saveSettings();
	}

	/** Active ou désactive la restriction par catégorie. */
	toggleCategoryMode(): void {
		if (this.isConfigLocked()) return;
		const wasActive = this.gameSettings.categories.length > 0;
		this.gameSettings = { ...this.gameSettings, categories: wasActive ? [] : ['classique'] };
		void this.saveSettings();
	}

	/** Ajoute ou retire une catégorie de la liste des catégories restreintes. */
	toggleCategory(cat: string): void {
		if (this.isConfigLocked()) return;
		const cats = this.gameSettings.categories;
		const filtered = cats.filter((c) => c !== cat);
		const newCats = cats.includes(cat) ? (filtered.length === 0 ? [cat] : filtered) : [...cats, cat];
		this.gameSettings = { ...this.gameSettings, categories: newCats };
		void this.saveSettings();
	}

	/** Sélectionne toutes les catégories. */
	selectAllCategories(): void {
		if (this.isConfigLocked()) return;
		this.gameSettings = { ...this.gameSettings, categories: [...this.ALL_CATEGORIES] };
		void this.saveSettings();
	}

	/** Désélectionne toutes les catégories (une seule reste sélectionnée). */
	clearAllCategories(): void {
		if (this.isConfigLocked()) return;
		this.gameSettings = { ...this.gameSettings, categories: ['classique'] };
		void this.saveSettings();
	}

	/** Active ou désactive le mode Pokédex caché (sprites masqués). */
	toggleNoPokedex(): void {
		if (this.isConfigLocked()) return;
		this.gameSettings = { ...this.gameSettings, noPokedex: !this.gameSettings.noPokedex };
		void this.saveSettings();
	}

	/** Active ou désactive la restriction de recherche dans le Pokédex. */
	toggleNoSearch(): void {
		if (this.isConfigLocked()) return;
		this.gameSettings = { ...this.gameSettings, noSearch: !this.gameSettings.noSearch };
		void this.saveSettings();
	}

	/** Active ou désactive le mode Pokémon aléatoire. */
	toggleRandomPokemon(): void {
		if (this.isConfigLocked()) return;
		this.gameSettings = { ...this.gameSettings, randomPokemon: !this.gameSettings.randomPokemon };
		void this.saveSettings();
	}

	/** Définit quel joueur commence la partie. */
	setFirstPlayer(value: FirstPlayer): void {
		if (this.isConfigLocked()) return;
		this.gameSettings = { ...this.gameSettings, firstPlayer: value };
		void this.saveSettings();
	}

	/** Retourne true si la configuration ne peut plus être modifiée (partie déjà lancée). */
    isConfigLocked(): boolean {
        return this.room()?.status === 'selecting' || this.room()?.status === 'playing';
    }

	/** Sauvegarde les paramètres de la partie en base de données. */
	private async saveSettings(): Promise<void> {
		try {
			await this.gameService.updateSettings(this.roomId(), this.gameSettings);
		} catch {
			// ignore les erreurs de sauvegarde des paramètres
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
		const mode = this.route.snapshot.queryParamMap.get('mode');
		if (mode === 'stat_duel' || mode === 'draft_duo') return mode;
		return 'guess_my_pokemon';
	}

	/** Initialise le lobby Duel de Base Stats. */
	private async initStatDuelLobby(): Promise<void> {
		try {
			let room = await this.supabaseService.getStatDuelRoom(this.roomId());
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
			if (room.status === 'finished' && room.winner === null) {
				void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
			} else if (room.status !== 'waiting') void this.navigateToPlay();
			this.multiRoomSub = this.supabaseService.subscribeToStatDuelRoom(this.roomId()).subscribe((updated) => {
				this.statDuelRoom.set(updated);
				if (updated.status === 'finished' && updated.winner === null) {
					void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
					return;
				}
				if (updated.status !== 'waiting') void this.navigateToPlay();
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
			if (room.status === 'finished' && room.winner === null) {
				void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
			} else if (room.status !== 'waiting') void this.navigateToPlay();
			this.multiRoomSub = this.supabaseService.subscribeToDraftDuoRoom(this.roomId()).subscribe((updated) => {
				this.draftDuoRoom.set(updated);
				if (updated.status === 'finished' && updated.winner === null) {
					void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
					return;
				}
				if (updated.status !== 'waiting') void this.navigateToPlay();
			});
			this.startMultiPoll();
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
					if (room.status === 'finished' && room.winner === null) {
						void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
						return;
					}
					if (room.status !== 'waiting') void this.navigateToPlay();
				} else if (this.gameMode === 'draft_duo') {
					const room = await this.supabaseService.getDraftDuoRoom(this.roomId());
					this.draftDuoRoom.set(room);
					if (room.status === 'finished' && room.winner === null) {
						void this.router.navigate(['/home'], { queryParams: { gameEnded: true } });
						return;
					}
					if (room.status !== 'waiting') void this.navigateToPlay();
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
		if (!room || this.gameMode === 'draft_duo') return null;

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
