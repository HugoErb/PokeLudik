import { computed, inject, Injectable, isDevMode, OnDestroy, signal } from '@angular/core';
import { firstValueFrom, Subscription } from 'rxjs';
import { DEFAULT_SETTINGS, GameSettings, Room, RoomPatch } from '../models/room.model';
import { SupabaseService } from './supabase.service';
import { PokemonService } from './pokemon.service';
import { Pokemon } from '../models/pokemon.model';
import { environment } from '../../environments/environment';

@Injectable({ providedIn: 'root' })
export class GameService implements OnDestroy {
    private readonly supabaseService = inject(SupabaseService);
    private readonly pokemonService = inject(PokemonService);
    private pollInterval: any;
    private replayLaunchInProgress = false;

    /** Signal Angular : room en cours de jeu, null si aucune. */
    currentRoom = signal<Room | null>(null, {
        equal: (a, b) => {
            if (a === b) return true;
            if (!a || !b) return false;
            return (
                a.status === b.status &&
                a.player2_id === b.player2_id &&
                a.current_turn === b.current_turn &&
                a.winner_id === b.winner_id &&
                a.p1_ready === b.p1_ready &&
                a.p2_ready === b.p2_ready &&
                a.pokemon_p1 === b.pokemon_p1 &&
                a.pokemon_p2 === b.pokemon_p2 &&
                JSON.stringify(a.settings) === JSON.stringify(b.settings)
            );
        }
    });

    /** Retourne true si l'application est en mode développement. */
    isDev(): boolean {
        return environment.devMode && isDevMode();
    }

    /** Événements diffusés en direct (broadcast) */
    broadcastEvents$ = this.supabaseService.broadcastEvents$;

    private roomSubscription: Subscription | null = null;

    // ─── Watch de la room ────────────────────────────────────────────────────────

    /**
     * Rejoint une room et s'abonne aux mises à jour Realtime.
     * Charge également l'état initial de la room et démarre un polling de secours.
     */
    async joinAndWatch(roomId: string): Promise<void> {
        this.stopWatching();
        this.roomSubscription = this.supabaseService.subscribeToRoom(roomId).subscribe({
            next: (updatedRoom) => {
                this.currentRoom.set(updatedRoom);
                void this.launchReplayIfReady(roomId, updatedRoom);
            },
            error: () => {
                // Si on perd la connexion, on tente quand même de rafraîchir une fois manuellement
                void this.refreshRoom(roomId);
            },
        });
        // 2. Charger l'état initial ensuite
        const room = await this.supabaseService.getRoomById(roomId);
        this.currentRoom.set(room);
        void this.launchReplayIfReady(roomId, room);

        this.pollInterval && clearInterval(this.pollInterval);
        this.pollInterval = setInterval(() => {
            void this.refreshRoom(roomId);
        }, 2000);
    }

    /** Arrête l'abonnement Realtime de la room courante et le polling de secours. */
    stopWatching(): void {
        if (this.roomSubscription) {
            this.roomSubscription.unsubscribe();
            this.roomSubscription = null;
        }
        clearInterval(this.pollInterval);
        this.pollInterval = undefined;
    }

    /** Annule la room, arrête le watch et réinitialise l'état local. */
    async cancelRoom(roomId: string): Promise<void> {
        await this.supabaseService.broadcastPlayerLeft().catch(() => undefined);
        await this.supabaseService.updateRoom(roomId, {
            status: 'finished',
            winner_id: null,
            p1_ready: false,
            p2_ready: false,
            last_guess: null,
        });
        this.stopWatching();
        this.currentRoom.set(null);
    }

    /**
     * DEV : Simule l'adversaire en choisissant un Pokémon et en passant
     * au statut 'playing' avec le premier tour résolu.
     */
    async simulateOpponentReady(roomId: string, pokemonId: number): Promise<void> {
        const room = this.currentRoom();
        if (!room) throw new Error('Aucune room active');

        const refreshedForTurn = await this.supabaseService.getRoomById(roomId);
        await this.updateAndRefresh(roomId, {
            pokemon_p2: pokemonId,
            p2_ready: true,
            status: 'playing',
            current_turn: this.resolveFirstTurn(refreshedForTurn),
        });
    }

    /** DEV : Simule un adversaire sans compte réel dans la room. */
    async simulateOpponent(roomId: string): Promise<void> {
        const user = this.supabaseService.getCurrentUser();
        if (!user) throw new Error('Utilisateur non connecté');

        await this.updateAndRefresh(roomId, {
            player2_id: null,
            status: 'ready',
        });
    }

    /** Lifecycle Angular — arrête le watch de la room. */
    ngOnDestroy(): void {
        this.stopWatching();
    }

    // ─── Actions de jeu ──────────────────────────────────────────────────────────

    /** Passe la room en phase de sélection, ou assigne directement des Pokémon aléatoires si le mode est activé. */
    async launchGame(roomId: string, settings: GameSettings): Promise<void> {
        const user = this.supabaseService.getCurrentUser();
        if (!user) throw new Error('Utilisateur non connecté');

        const currentRoom = await this.supabaseService.getRoomById(roomId);
        if (currentRoom.player1_id !== user.id) throw new Error('Seul le créateur peut lancer la partie');

        if (settings.randomPokemon) {
            let pokemons = await firstValueFrom(this.pokemonService.loadAll());
            if (settings.generations.length > 0) {
                pokemons = pokemons.filter((p) => settings.generations.includes(p.generation));
            }
            if (settings.categories.length > 0) {
                pokemons = pokemons.filter((p) => settings.categories.includes(p.category));
            }
            if (pokemons.length < 2) throw new Error('Pas assez de Pokémon disponibles pour ces filtres');
            const [p1, p2] = this.pickTwoDifferent(pokemons);
            await this.updateAndRefresh(roomId, {
                settings,
                pokemon_p1: p1.id,
                pokemon_p2: p2.id,
                p1_ready: true,
                p2_ready: true,
                status: 'playing',
                current_turn: this.resolveFirstTurn({ ...currentRoom, settings }),
            });
        } else {
            await this.updateAndRefresh(roomId, { status: 'selecting', settings });
        }
    }

    /** Met à jour les paramètres de la partie et rafraîchit le signal local. */
    async updateSettings(roomId: string, settings: GameSettings): Promise<void> {
        await this.supabaseService.updateRoom(roomId, { settings });
        const refreshed = await this.supabaseService.getRoomById(roomId);
        this.currentRoom.set(refreshed);
    }

    /** Enregistre le Pokémon choisi par le joueur courant (p1 ou p2 selon son rôle). */
    async selectPokemon(roomId: string, pokemonId: number): Promise<void> {
        const user = this.supabaseService.getCurrentUser();
        if (!user) throw new Error('Utilisateur non connecté');

        const room = this.currentRoom();
        if (!room) throw new Error('Aucune room active');

        const isPlayer1 = user.id === room.player1_id;
        const isPlayer2 = user.id === room.player2_id;
        if (!isPlayer1 && !isPlayer2) throw new Error('Utilisateur hors de la room');
        if (room.status !== 'selecting') throw new Error('La sélection est fermée');

        const patch: RoomPatch = isPlayer1 ? { pokemon_p1: pokemonId } : { pokemon_p2: pokemonId };

        await this.supabaseService.updateRoom(roomId, patch);
    }

    /**
     * Marque le joueur courant comme prêt.
     * Si les deux joueurs sont prêts, lance la partie et détermine le premier tour.
     */
    async setReady(roomId: string): Promise<void> {
        const user = this.supabaseService.getCurrentUser();
        if (!user) throw new Error('Utilisateur non connecté');

        const room = this.currentRoom();
        if (!room) throw new Error('Aucune room active');

        const isPlayer1 = user.id === room.player1_id;
        const isPlayer2 = user.id === room.player2_id;
        if (!isPlayer1 && !isPlayer2) throw new Error('Utilisateur hors de la room');
        if (room.status !== 'selecting') throw new Error('La partie n’est pas en phase de sélection');

        const patch: RoomPatch = isPlayer1 ? { p1_ready: true } : { p2_ready: true };

        await this.supabaseService.updateRoom(roomId, patch);

        const refreshed = await this.supabaseService.getRoomById(roomId);

        if (refreshed.p1_ready && refreshed.p2_ready && refreshed.status === 'selecting') {
            await this.supabaseService.updateRoom(roomId, {
                status: 'playing',
                current_turn: this.resolveFirstTurn(refreshed),
            });
            const finalRoom = await this.supabaseService.getRoomById(roomId);
            this.currentRoom.set(finalRoom);
            return;
        }

        this.currentRoom.set(refreshed);
    }

    /**
     * Soumet un guess de Pokémon par le joueur courant.
     * Retourne `'correct'` si le Pokémon est trouvé (fin de partie),
     * ou `'incorrect'` si le tour passe à l'adversaire.
     */
    async guess(roomId: string, pokemonId: number): Promise<'correct' | 'incorrect'> {
        const user = this.supabaseService.getCurrentUser();
        if (!user) throw new Error('Utilisateur non connecté');

        const localRoom = this.currentRoom();
        if (!localRoom) throw new Error('Aucune room active');

        const room = await this.supabaseService.getRoomById(roomId);
        this.currentRoom.set(room);
        if (room.status !== 'playing') throw new Error('La partie n’est pas en cours');
        if (room.current_turn !== user.id) throw new Error('Ce n’est pas ton tour');

        const isPlayer1 = user.id === room.player1_id;
        const isPlayer2 = user.id === room.player2_id;
        if (!isPlayer1 && !isPlayer2) throw new Error('Utilisateur hors de la room');

        // Le Pokémon adverse : player1 cherche pokemon_p2 et vice-versa
        const adversaryPokemonId = isPlayer1 ? room.pokemon_p2 : room.pokemon_p1;
        let adversaryId = isPlayer1 ? room.player2_id : room.player1_id;

        // En mode dev, adversaryId peut être null (adversaire simulé sans compte) — autorisé explicitement.
        // Hors dev, un adversaryId null indique une room corrompue (guard ci-dessous).

        if (adversaryPokemonId === null) throw new Error("L'adversaire n'a pas encore choisi de Pokémon");

        const isCorrect = await this.supabaseService.submitGuessPokemonGuess(roomId, pokemonId);
        if (isCorrect) {
            await this.refreshRoom(roomId);
            return 'correct';
        } else {
            if (!adversaryId && !this.isDev()) throw new Error('Adversaire introuvable');
            void this.supabaseService.broadcastGuess(pokemonId, user.id);
            await this.refreshRoom(roomId);
            return 'incorrect';
        }
    }

    /**
     * DEV : Simule un guess de l'adversaire.
     */
    async simulateOpponentGuess(roomId: string, pokemonId: number): Promise<'correct' | 'incorrect'> {
        const room = this.currentRoom();
        if (!room) throw new Error('Aucune room active');

        const isPlayer1 = this.isPlayer1();
        const targetPokemonId = isPlayer1 ? room.pokemon_p1 : room.pokemon_p2;

        if (pokemonId === targetPokemonId) {
            await this.updateAndRefresh(roomId, {
                winner_id: isPlayer1 ? room.player2_id : room.player1_id,
                status: 'finished',
                p1_ready: false,
                p2_ready: false,
                last_guess: null,
            });
            return 'correct';
        } else {
            void this.supabaseService.broadcastGuess(pokemonId, null);
            await this.updateAndRefresh(roomId, {
                current_turn: room.player1_id,
                last_guess: pokemonId,
            });
            return 'incorrect';
        }
    }

    /**
     * Demande une revanche.
     * Si les deux joueurs acceptent, la partie repasse en mode sélection.
     */
    async requestReplay(roomId: string): Promise<void> {
        const user = this.supabaseService.getCurrentUser();
        if (!user) throw new Error('Utilisateur non connecté');

        const room = this.currentRoom();
        if (!room) throw new Error('Aucune room active');

        const isPlayer1 = this.isPlayer1();
        const patch: RoomPatch = isPlayer1 ? { p1_ready: true } : { p2_ready: true };

        await this.supabaseService.updateRoom(roomId, patch);

        const refreshed = await this.supabaseService.getRoomById(roomId);

        this.currentRoom.set(refreshed);
        await this.launchReplayIfReady(roomId, refreshed);
    }

    /**
     * DEV : Simule l'acceptation d'une revanche par l'adversaire.
     */
    async simulateOpponentReplay(roomId: string): Promise<void> {
        const room = this.currentRoom();
        if (!room) throw new Error('Aucune room active');

        const isPlayer1 = this.isPlayer1();
        // On veut simuler l'action de l'AUTRE joueur
        const patch: RoomPatch = isPlayer1 ? { p2_ready: true } : { p1_ready: true };

        const opponentAlreadyRequested = isPlayer1 ? room.p1_ready : room.p2_ready;

        if (opponentAlreadyRequested) {
            Object.assign(patch, {
                status: 'selecting',
                pokemon_p1: null,
                pokemon_p2: null,
                p1_ready: false,
                p2_ready: false,
                winner_id: null,
                current_turn: null,
            } satisfies RoomPatch);
        }

        await this.updateAndRefresh(roomId, patch);
    }

    /** Rafraîchit manuellement l'état de la room. */
    async refreshRoom(roomId: string): Promise<void> {
        try {
            const room = await this.supabaseService.getRoomById(roomId);
            this.currentRoom.set(room);
            void this.launchReplayIfReady(roomId, room);
            void this.launchSelectingIfBothReady(roomId, room);
        } catch {
            // ignore les erreurs de rafraîchissement
        }
    }

    /**
     * Filet de sécurité contre la race condition de setReady() :
     * si le polling détecte les deux joueurs prêts en phase 'selecting' mais que personne
     * n'a encore déclenché la partie, Player 1 prend en charge le lancement.
     */
    private launchSelectingInProgress = false;
    private async launchSelectingIfBothReady(roomId: string, room: Room): Promise<void> {
        const user = this.supabaseService.getCurrentUser();
        if (!user || user.id !== room.player1_id) return;
        if (this.launchSelectingInProgress || room.status !== 'selecting' || !room.p1_ready || !room.p2_ready) return;

        this.launchSelectingInProgress = true;
        try {
            await this.supabaseService.updateRoom(roomId, {
                status: 'playing',
                current_turn: this.resolveFirstTurn(room),
            });
            const finalRoom = await this.supabaseService.getRoomById(roomId);
            this.currentRoom.set(finalRoom);
        } catch {
            // ignore — l'autre joueur a peut-être déjà lancé entre temps
        } finally {
            this.launchSelectingInProgress = false;
        }
    }

    /**
     * Détermine l'identifiant du joueur qui commence la partie
     * selon le paramètre `firstPlayer` des settings.
     */
    private resolveFirstTurn(room: Room): string {
        const fp = room.settings?.firstPlayer ?? 'player1';
        // player2_id peut être null en mode dev (adversaire simulé sans compte réel) : fallback sur player1
        if (fp === 'player2') return room.player2_id ?? room.player1_id;
        if (fp === 'random') return Math.random() < 0.5 ? room.player1_id : (room.player2_id ?? room.player1_id);
        return room.player1_id; // 'player1' ou fallback
    }

    // ─── Helpers internes ─────────────────────────────────────────────────────────

    /** Tire deux Pokémon distincts au hasard dans la liste fournie. */
    private pickTwoDifferent(pokemons: Pokemon[]): [Pokemon, Pokemon] {
        const idx1 = Math.floor(Math.random() * pokemons.length);
        let idx2 = Math.floor(Math.random() * (pokemons.length - 1));
        if (idx2 >= idx1) idx2++;
        return [pokemons[idx1], pokemons[idx2]];
    }

    /**
     * Met à jour la room en base ET rafraîchit immédiatement le signal local.
     * Cela garantit que le watcher réagit même si le Realtime Supabase est lent ou absent.
     */
    private async updateAndRefresh(roomId: string, patch: RoomPatch): Promise<void> {
        await this.supabaseService.updateRoom(roomId, patch);
        const refreshed = await this.supabaseService.getRoomById(roomId);
        this.currentRoom.set(refreshed);
    }

    private async launchReplayIfReady(roomId: string, room: Room): Promise<void> {
        const user = this.supabaseService.getCurrentUser();
        if (!user || user.id !== room.player1_id) return;
        if (this.replayLaunchInProgress || room.status !== 'finished' || !room.p1_ready || !room.p2_ready) return;

        this.replayLaunchInProgress = true;
        try {
            const settings = room.settings ?? DEFAULT_SETTINGS;
            if (settings.randomPokemon) {
                let pokemons = await firstValueFrom(this.pokemonService.loadAll());
                if (settings.generations.length > 0) {
                    pokemons = pokemons.filter((p) => settings.generations.includes(p.generation));
                }
                if (settings.categories.length > 0) {
                    pokemons = pokemons.filter((p) => settings.categories.includes(p.category));
                }
                const [p1, p2] = this.pickTwoDifferent(pokemons);
                await this.supabaseService.updateRoom(roomId, {
                    status: 'playing',
                    pokemon_p1: p1.id,
                    pokemon_p2: p2.id,
                    p1_ready: false,
                    p2_ready: false,
                    winner_id: null,
                    current_turn: this.resolveFirstTurn({ ...room, settings }),
                    last_guess: null,
                });
            } else {
                await this.supabaseService.updateRoom(roomId, {
                    status: 'selecting',
                    pokemon_p1: null,
                    pokemon_p2: null,
                    p1_ready: false,
                    p2_ready: false,
                    winner_id: null,
                    current_turn: null,
                    last_guess: null,
                });
            }

            const finalRoom = await this.supabaseService.getRoomById(roomId);
            this.currentRoom.set(finalRoom);
        } finally {
            this.replayLaunchInProgress = false;
        }
    }

    // ─── Helpers d'état ──────────────────────────────────────────────────────────

    readonly isMyTurn = computed(() => {
        const room = this.currentRoom();
        const user = this.supabaseService.currentUserSignal();
        if (!room || !user) return false;
        return room.current_turn === user.id;
    });

    readonly isPlayer1 = computed(() => {
        const room = this.currentRoom();
        const user = this.supabaseService.currentUserSignal();
        if (!room || !user) return false;
        return room.player1_id === user.id;
    });

    readonly settings = computed(() => {
        const room = this.currentRoom();
        return room?.settings ?? DEFAULT_SETTINGS;
    }, { equal: (a, b) => JSON.stringify(a) === JSON.stringify(b) });
}
