import { Injectable, OnDestroy, signal, inject, NgZone } from '@angular/core';
import { BehaviorSubject, Observable, Subject } from 'rxjs';
import { filter, map, skipUntil } from 'rxjs/operators';
import { createClient, SupabaseClient, User } from '@supabase/supabase-js';
import { environment } from '../../environments/environment';
import { DraftDuoRoom, FriendRequest, FriendStatus, FriendWithStatus, Friendship, GameInvite, GameMode, GameSettings, Profile, Room, RoomPatch, StatDuelRoom, StatPick, WhoGameSettings, WhoPokemonRoom } from '../models/room.model';

@Injectable({ providedIn: 'root' })
export class SupabaseService implements OnDestroy {
    private supabase: SupabaseClient;
    private userSubject = new BehaviorSubject<User | null>(null);
    private authSubscription: { unsubscribe: () => void } | null = null;
    private readonly isInitializedSubject = new BehaviorSubject<boolean>(false);
    private readonly passwordRecoverySubject = new BehaviorSubject<boolean>(false);
    private broadcastSubject = new Subject<{ event: string; payload: any }>();
    private readonly ngZone = inject(NgZone);

    broadcastEvents$ = this.broadcastSubject.asObservable();
    private activeRoomChannel: any = null;

    currentUser$: Observable<User | null> = this.userSubject.asObservable();
    readonly authReady$: Observable<User | null>;
    readonly passwordRecoveryReady$ = this.passwordRecoverySubject.asObservable();
    readonly currentUserSignal = signal<User | null>(null);

    constructor() {
        this.supabase = createClient(environment.supabaseUrl, environment.supabaseAnonKey);

        this.authReady$ = this.userSubject.pipe(skipUntil(this.isInitializedSubject.pipe(filter((v) => v))));

        // Initialise avec la session courante
        this.supabase.auth.getSession().then(({ data }) => {
            const user = data.session?.user ?? null;
            this.userSubject.next(user);
            this.currentUserSignal.set(user);
            this.isInitializedSubject.next(true);
        });

        // Écoute les changements d'état d'authentification
        const {
            data: { subscription },
        } = this.supabase.auth.onAuthStateChange((event, session) => {
            const user = session?.user ?? null;
            this.userSubject.next(user);
            this.currentUserSignal.set(user);
            if (event === 'PASSWORD_RECOVERY') this.passwordRecoverySubject.next(true);
            if (event === 'SIGNED_OUT') this.passwordRecoverySubject.next(false);

            // Crée le profil à la première connexion (cas confirmation email activée)
            if (event === 'SIGNED_IN' && user) {
                this.ensureProfile(user.id, user.user_metadata?.['username']);
            }
        });
        this.authSubscription = subscription;
    }

    /** Désinscrit l'abonnement d'authentification. */
    ngOnDestroy(): void {
        this.authSubscription?.unsubscribe();
    }

    // ─── Auth ────────────────────────────────────────────────────────────────────

    /**
     * Crée un nouveau compte utilisateur avec email, mot de passe et pseudo,
     * puis insère le profil correspondant. Lance une erreur si la confirmation
     * email est requise.
     */
    async signUp(email: string, password: string, username: string): Promise<void> {
        const { data, error } = await this.supabase.auth.signUp({
            email,
            password,
            options: { data: { username, display_name: username } },
        });
        if (error) throw error;

        const user = data.user;
        if (!user) throw new Error("Aucun utilisateur retourné après l'inscription");

        if (!data.session) {
            // Confirmation email requise — le profil sera créé par ensureProfile après confirmation
            throw new Error('Un email de confirmation a été envoyé. Clique sur le lien dans ta boîte mail pour activer ton compte.');
        }

        const { error: profileError } = await this.supabase
            .from('profiles')
            .upsert({ id: user.id, username }, { onConflict: 'id', ignoreDuplicates: true });

        if (profileError) {
            if (profileError.code === '23505') throw new Error('Ce nom d\'utilisateur est déjà utilisé.');
            throw new Error(profileError.message);
        }
    }

    /**
     * Crée le profil utilisateur s'il n'existe pas encore en base.
     * Utilisé après la confirmation email.
     */
    async ensureProfile(userId: string, username?: string): Promise<void> {
        const { data } = await this.supabase.from('profiles').select('id').eq('id', userId).maybeSingle();

        if (!data && username) {
            await this.supabase.from('profiles').insert({ id: userId, username: username.trim() });
        }
    }

    /** Connecte l'utilisateur avec son email et son mot de passe. */
    async signIn(email: string, password: string): Promise<void> {
        const { error } = await this.supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
    }

    /** Déconnecte l'utilisateur courant. */
    async signOut(): Promise<void> {
        if (this.presenceChannel) {
            this.supabase.removeChannel(this.presenceChannel);
            this.presenceChannel = null;
        }
        const { error } = await this.supabase.auth.signOut();
        if (error) throw error;
    }

    /** Envoie un email de réinitialisation du mot de passe à l'adresse fournie. */
    async resetPasswordForEmail(email: string): Promise<void> {
        const { error } = await this.supabase.auth.resetPasswordForEmail(email, {
            redirectTo: `${window.location.origin}/reset-password`,
        });
        if (error) throw error;
    }

    /** Met à jour le mot de passe de l'utilisateur connecté. */
    async updatePassword(newPassword: string): Promise<void> {
        const { error } = await this.supabase.auth.updateUser({ password: newPassword });
        if (error) throw error;
        this.passwordRecoverySubject.next(false);
    }

    /**
     * Vérifie si le mot de passe fourni est correct pour l'utilisateur courant
     * en tentant une reconnexion silencieuse.
     */
    async verifyPassword(password: string): Promise<boolean> {
        const user = this.userSubject.getValue();
        if (!user?.email) return false;

        // On tente une reconnexion silencieuse pour vérifier le mot de passe actuel
        const { error } = await this.supabase.auth.signInWithPassword({
            email: user.email,
            password: password,
        });

        return !error;
    }

    // ─── Profil ──────────────────────────────────────────────────────────────────

    /** Récupère le profil complet d'un utilisateur depuis la base de données. */
    async getProfile(userId: string): Promise<Profile> {
        const { data, error } = await this.supabase.from('profiles').select('*').eq('id', userId).single();

        if (error) throw error;
        return data as Profile;
    }

    /** Met à jour partiellement le profil d'un utilisateur. */
    async updateProfile(userId: string, patch: Partial<Profile>): Promise<void> {
        const { error } = await this.supabase.from('profiles').update(patch).eq('id', userId);

        if (error) throw error;
    }

    /**
     * Met à jour le pseudo de l'utilisateur dans Supabase Auth
     * et dans la table des profils publics.
     */
    async updateUsername(userId: string, newUsername: string): Promise<void> {
        const trimmed = newUsername.trim();
        // 1. Mettre à jour les métadonnées de l'utilisateur (Auth)
        const { error: authError } = await this.supabase.auth.updateUser({
            data: {
                username: trimmed,
                display_name: trimmed,
            },
        });
        if (authError) throw authError;

        // 2. Mettre à jour la table des profils (Public)
        const { error: profileError } = await this.supabase.from('profiles').update({ username: trimmed }).eq('id', userId);
        if (profileError) {
            if (profileError.code === '23505') throw new Error('Ce nom d\'utilisateur est déjà utilisé.');
            throw profileError;
        }
    }

    // ─── Rooms ───────────────────────────────────────────────────────────────────

    /** Crée une nouvelle room de jeu (Guess my Pokémon) et retourne son identifiant. */
    async createRoom(): Promise<string> {
        const user = this.userSubject.getValue();
        if (!user) throw new Error('Utilisateur non connecté');

        const { data, error } = await this.supabase.from('guess_pokemon_rooms').insert({ player1_id: user.id, status: 'waiting' }).select('id').single();

        if (error) throw error;
        return (data as { id: string }).id;
    }

    /** Récupère une room (Guess my Pokémon) par son identifiant. */
    async getRoomById(roomId: string): Promise<Room> {
        const { data, error } = await this.supabase.from('guess_pokemon_rooms').select('*').eq('id', roomId).single();

        if (error) throw error;
        return data as Room;
    }

    /**
     * Ajoute l'utilisateur courant à une room existante en tant que joueur 2.
     * Lance une erreur si la room est pleine, non joignable ou appartient au joueur.
     */
    async joinRoom(roomId: string): Promise<void> {
        const user = this.userSubject.getValue();
        if (!user) throw new Error('Utilisateur non connecté');

        const room = await this.getRoomById(roomId);

        if (!room) throw new Error('Room introuvable');
        if (room.player2_id) throw new Error('Room déjà complète');
        if (room.status !== 'waiting') throw new Error('Room non joignable');
        if (room.player1_id === user.id) throw new Error('Le créateur ne peut pas rejoindre sa propre room');

        const { error } = await this.supabase.rpc('join_guess_pokemon_room', { p_room_id: roomId });

        if (error) throw error;
    }

    /** Lance la partie en passant la room au statut 'selecting'. */
    async launchGame(roomId: string, settings: GameSettings): Promise<void> {
        const { error } = await this.supabase.rpc('update_guess_pokemon_room', { p_room_id: roomId, p_patch: { status: 'selecting', settings } });

        if (error) throw error;
    }

    /**
     * S'abonne aux mises à jour Realtime d'une room (Guess my Pokémon) via PostgreSQL Changes et Broadcast.
     * Émet les nouvelles valeurs de la room à chaque modification.
     */
    subscribeToRoom(roomId: string): Observable<Room> {
        return new Observable<Room>((observer) => {
            const user = this.getCurrentUser();
            const channel = this.supabase
                .channel(`room-${roomId}`, { config: { presence: { key: user?.id ?? crypto.randomUUID() } } })
                .on(
                    'postgres_changes',
                    {
                        event: '*',
                        schema: 'public',
                        table: 'guess_pokemon_rooms',
                        filter: `id=eq.${roomId}`,
                    },
                    (payload) => {
                        observer.next(payload.new as Room);
                    },
                )
                .on('broadcast', { event: '*' }, ({ event, payload }) => {
                    this.broadcastSubject.next({ event, payload });
                })
                .subscribe((status) => {
                    if (status === 'CHANNEL_ERROR') {
                        observer.error(new Error(`Erreur canal room-${roomId}`));
                    }
                    if (status === 'SUBSCRIBED' && user) {
                        void channel.track({ user_id: user.id });
                    }
                });

            this.activeRoomChannel = channel;

            // Cleanup : retirer le canal à la désinscription
            return () => {
                this.supabase.removeChannel(channel);
                this.activeRoomChannel = null;
            };
        });
    }

    /**
     * Met à jour les données d'une room (Guess my Pokémon) en base.
     * Lance une erreur si la mise à jour est refusée ou n'affecte aucune ligne.
     */
    async updateRoom(roomId: string, patch: RoomPatch): Promise<void> {
        const { error } = await this.supabase.rpc('update_guess_pokemon_room', { p_room_id: roomId, p_patch: patch });

        if (error) throw error;
    }

    async submitGuessPokemonGuess(roomId: string, pokemonId: number): Promise<boolean> {
        const { data, error } = await this.supabase.rpc('submit_guess_pokemon_guess', {
            p_room_id: roomId,
            p_pokemon_id: pokemonId,
        });
        if (error) throw error;
        return data === true;
    }

    /** Supprime une room (Guess my Pokémon) de la base de données. */
    async deleteRoom(roomId: string): Promise<void> {
        const { error } = await this.supabase.from('guess_pokemon_rooms').delete().eq('id', roomId);

        if (error) throw error;
    }

    // ─── Stat Duel Rooms ─────────────────────────────────────────────────────────

    /** Crée une nouvelle room Duel de Base Stats et retourne son identifiant. */
    async createStatDuelRoom(): Promise<string> {
        const user = this.userSubject.getValue();
        if (!user) throw new Error('Utilisateur non connecté');

        const { data, error } = await this.supabase
            .from('stat_duel_rooms')
            .insert({ player1_id: user.id, status: 'waiting' })
            .select('id')
            .single();

        if (error) throw error;
        return (data as { id: string }).id;
    }

    /** Récupère une room Duel de Base Stats par son identifiant. */
    async getStatDuelRoom(roomId: string): Promise<StatDuelRoom> {
        const { data, error } = await this.supabase
            .from('stat_duel_rooms')
            .select('*')
            .eq('id', roomId)
            .single();

        if (error) throw error;
        return data as StatDuelRoom;
    }

    /** Ajoute l'utilisateur courant en tant que joueur 2 d'une room Duel de Base Stats. */
    async joinStatDuelRoom(roomId: string): Promise<void> {
        const user = this.userSubject.getValue();
        if (!user) throw new Error('Utilisateur non connecté');

        const room = await this.getStatDuelRoom(roomId);
        if (room.player1_id === user.id) throw new Error('Le créateur ne peut pas rejoindre sa propre room');
        if (room.player2_id) throw new Error('Room déjà complète');
        if (room.status !== 'waiting') throw new Error('Room non joignable');

        const { error } = await this.supabase.rpc('join_stat_duel_room', { p_room_id: roomId });

        if (error) throw error;
    }

    /** Met à jour les données d'une room Duel de Base Stats. */
    async updateStatDuelRoom(roomId: string, patch: Partial<StatDuelRoom>): Promise<void> {
        const { error } = await this.supabase.rpc('update_stat_duel_room', { p_room_id: roomId, p_patch: patch });

        if (error) throw error;
    }

    /** Ajoute un pick de stat dans p1_picks ou p2_picks via concaténation JSON. */
    async appendStatPick(roomId: string, column: 'p1_picks' | 'p2_picks', pick: StatPick): Promise<void> {
        const { error } = await this.supabase.rpc('append_stat_pick', { p_room_id: roomId, p_column: column, p_pick: pick });

        if (error) throw error;
    }

    /** S'abonne aux mises à jour Realtime d'une room Duel de Base Stats. */
    subscribeToStatDuelRoom(roomId: string): Observable<StatDuelRoom> {
        return new Observable<StatDuelRoom>((observer) => {
            const user = this.getCurrentUser();
            const channel = this.supabase
                .channel(`stat-duel-${roomId}`, { config: { presence: { key: user?.id ?? crypto.randomUUID() } } })
                .on(
                    'postgres_changes',
                    {
                        event: '*',
                        schema: 'public',
                        table: 'stat_duel_rooms',
                        filter: `id=eq.${roomId}`,
                    },
                    (payload) => {
                        observer.next(payload.new as StatDuelRoom);
                    },
                )
                .on('broadcast', { event: '*' }, ({ event, payload }) => {
                    this.broadcastSubject.next({ event, payload });
                })
                .subscribe((status) => {
                    if (status === 'CHANNEL_ERROR') {
                        observer.error(new Error(`Erreur canal stat-duel-${roomId}`));
                    }
                    if (status === 'SUBSCRIBED' && user) {
                        void channel.track({ user_id: user.id });
                    }
                });

            this.activeRoomChannel = channel;

            return () => {
                this.supabase.removeChannel(channel);
                this.activeRoomChannel = null;
            };
        });
    }

    // ─── Draft Duo ───────────────────────────────────────────────────────────────

    /** Crée une room Draft Duo et retourne son identifiant. */
    async createDraftDuoRoom(): Promise<string> {
        const user = this.userSubject.getValue();
        if (!user) throw new Error('Utilisateur non connecté');

        const { data, error } = await this.supabase
            .from('draft_duo_rooms')
            .insert({ player1_id: user.id })
            .select('id')
            .single();

        if (error) throw error;
        return (data as { id: string }).id;
    }

    /** Récupère une room Draft Duo par son identifiant. */
    async getDraftDuoRoom(roomId: string): Promise<DraftDuoRoom> {
        const { data, error } = await this.supabase
            .from('draft_duo_rooms')
            .select('*')
            .eq('id', roomId)
            .single();

        if (error) throw error;
        return data as DraftDuoRoom;
    }

    /** Ajoute l'utilisateur courant en tant que joueur 2 d'une room Draft Duo. */
    async joinDraftDuoRoom(roomId: string): Promise<void> {
        const user = this.userSubject.getValue();
        if (!user) throw new Error('Utilisateur non connecté');

        const room = await this.getDraftDuoRoom(roomId);
        if (room.player1_id === user.id) throw new Error('Le créateur ne peut pas rejoindre sa propre room');
        if (room.player2_id) throw new Error('Room déjà complète');
        if (room.status !== 'waiting') throw new Error('Room non joignable');

        const { error } = await this.supabase.rpc('join_draft_duo_room', { p_room_id: roomId });

        if (error) throw error;
    }

    /** Met à jour les données d'une room Draft Duo. */
    async updateDraftDuoRoom(roomId: string, patch: Partial<DraftDuoRoom>): Promise<void> {
        const { error } = await this.supabase.rpc('update_draft_duo_room', { p_room_id: roomId, p_patch: patch });

        if (error) throw error;
    }

    /** S'abonne aux mises à jour Realtime d'une room Draft Duo. */
    subscribeToDraftDuoRoom(roomId: string): Observable<DraftDuoRoom> {
        return new Observable<DraftDuoRoom>((observer) => {
            const user = this.getCurrentUser();
            const channel = this.supabase
                .channel(`draft-duo-${roomId}`, { config: { presence: { key: user?.id ?? crypto.randomUUID() } } })
                .on(
                    'postgres_changes',
                    { event: '*', schema: 'public', table: 'draft_duo_rooms', filter: `id=eq.${roomId}` },
                    (payload) => { observer.next(payload.new as DraftDuoRoom); },
                )
                .on('broadcast', { event: '*' }, ({ event, payload }) => {
                    this.broadcastSubject.next({ event, payload });
                })
                .subscribe((status) => {
                    if (status === 'CHANNEL_ERROR') {
                        observer.error(new Error(`Erreur canal draft-duo-${roomId}`));
                    }
                    if (status === 'SUBSCRIBED' && user) {
                        void channel.track({ user_id: user.id });
                    }
                });

            this.activeRoomChannel = channel;

            return () => {
                this.supabase.removeChannel(channel);
                this.activeRoomChannel = null;
            };
        });
    }

    /** Envoie une invitation à rejoindre une room existante (sans créer de nouvelle room). */
    async createWhoPokemonRoom(settings?: WhoGameSettings): Promise<string> {
        const user = this.userSubject.getValue();
        if (!user) throw new Error('Utilisateur non connecté');

        const { data, error } = await this.supabase
            .from('who_that_pokemon_rooms')
            .insert({ player1_id: user.id, settings: settings ?? null })
            .select('id')
            .single();

        if (error) throw error;
        return (data as { id: string }).id;
    }

    async getWhoPokemonRoom(roomId: string): Promise<WhoPokemonRoom> {
        const { data, error } = await this.supabase
            .from('who_that_pokemon_rooms')
            .select('*')
            .eq('id', roomId)
            .single();

        if (error) throw error;
        return data as WhoPokemonRoom;
    }

    async joinWhoPokemonRoom(roomId: string): Promise<void> {
        const user = this.userSubject.getValue();
        if (!user) throw new Error('Utilisateur non connecté');

        const room = await this.getWhoPokemonRoom(roomId);
        if (room.player1_id === user.id) throw new Error('Le créateur ne peut pas rejoindre sa propre room');
        if (room.player2_id) throw new Error('Room déjà complète');
        if (room.status !== 'waiting') throw new Error('Room non joignable');

        const { error } = await this.supabase.rpc('join_who_that_pokemon_room', { p_room_id: roomId });
        if (error) throw error;
    }

    async updateWhoPokemonRoom(roomId: string, patch: Partial<WhoPokemonRoom>): Promise<void> {
        const { error } = await this.supabase.rpc('update_who_that_pokemon_room', { p_room_id: roomId, p_patch: patch });
        if (error) throw error;
    }

    async submitWhoPokemonGuess(roomId: string, round: number, pokemonId: number): Promise<void> {
        const { error } = await this.supabase.rpc('submit_who_that_pokemon_guess', {
            p_room_id: roomId,
            p_round: round,
            p_pokemon_id: pokemonId,
        });
        if (error) throw error;
    }

    subscribeToWhoPokemonRoom(roomId: string): Observable<WhoPokemonRoom> {
        return new Observable<WhoPokemonRoom>((observer) => {
            const user = this.getCurrentUser();
            const channel = this.supabase
                .channel(`who-that-pokemon-${roomId}`, { config: { presence: { key: user?.id ?? crypto.randomUUID() } } })
                .on(
                    'postgres_changes',
                    { event: '*', schema: 'public', table: 'who_that_pokemon_rooms', filter: `id=eq.${roomId}` },
                    (payload) => { observer.next(payload.new as WhoPokemonRoom); },
                )
                .on('broadcast', { event: '*' }, ({ event, payload }) => {
                    this.broadcastSubject.next({ event, payload });
                })
                .subscribe((status) => {
                    if (status === 'CHANNEL_ERROR') observer.error(new Error(`Erreur canal who-that-pokemon-${roomId}`));
                    if (status === 'SUBSCRIBED' && user) void channel.track({ user_id: user.id });
                });

            this.activeRoomChannel = channel;
            return () => {
                this.supabase.removeChannel(channel);
                this.activeRoomChannel = null;
            };
        });
    }

    async sendDirectGameInvite(recipientId: string, roomId: string, gameMode: GameMode): Promise<string> {
        const me = this.getCurrentUser();
        if (!me) throw new Error('Non connecté');

        const { data, error } = await this.supabase
            .from('game_invites')
            .insert({ sender_id: me.id, recipient_id: recipientId, room_id: roomId, game_mode: gameMode })
            .select('id')
            .single();

        if (error) throw error;
        return (data as { id: string }).id;
    }

    // ─── Utilitaire interne ──────────────────────────────────────────────────────

    /**
     * Diffuse le guess d'un joueur via le canal Broadcast de la room active.
     * En mode DEV, pousse également localement pour éviter la race condition.
     */
    async broadcastGuess(pokemonId: number, senderId: string | null): Promise<void> {
        if (this.activeRoomChannel) {
            const eventData = {
                type: 'broadcast',
                event: 'opponent_guess',
                payload: { pokemonId, senderId },
            };

            // En mode DEV, pousser localement en premier pour garantir que opponentLastGuess
            // est défini avant que l'effect DB ne déclenche la modale (channel.send est async)
            if (environment.devMode) {
                this.broadcastSubject.next({ event: eventData.event, payload: eventData.payload });
            }

            await this.activeRoomChannel.send(eventData);
        }
    }

    /** Diffuse l'événement de départ d'un joueur via le canal Broadcast de la room active. */
    async broadcastPlayerLeft(): Promise<void> {
        if (this.activeRoomChannel) {
            await this.activeRoomChannel.send({
                type: 'broadcast',
                event: 'player_left',
                payload: {},
            });
        }
    }

    /** Retourne l'utilisateur courant ou null s'il n'est pas connecté. */
    getCurrentUser(): User | null {
        return this.userSubject.getValue();
    }

    // ─── Présence ────────────────────────────────────────────────────────────────

    private presenceChannel: any = null;
    private readonly presenceStateSubject = new BehaviorSubject<Record<string, any[]>>({});
    private presenceUpdateState: (() => void) | null = null;
    private currentPresenceStatus: 'online' | 'in_game' | null = null;

    /** Rejoint le canal de présence global et diffuse le statut de l'utilisateur. */
    trackPresence(status: 'online' | 'in_game'): void {
        const user = this.getCurrentUser();
        if (!user) return;

        if (this.presenceChannel) {
            if (this.currentPresenceStatus === status) {
                this.presenceChannel.track({ user_id: user.id, status })
                    .then(() => this.presenceUpdateState?.())
                    .catch(() => undefined);
                return;
            }

            // Force un leave/join pour que les autres clients reçoivent le changement immédiatement.
            this.presenceChannel.untrack()
                .catch(() => undefined)
                .finally(() => {
                    this.presenceChannel.track({ user_id: user.id, status })
                        .then(() => {
                            this.currentPresenceStatus = status;
                            this.presenceUpdateState?.();
                        })
                        .catch(() => undefined);
                });
            return;
        }

        const channel = this.supabase.channel('presence-home', {
            config: { presence: { key: user.id } },
        });

        const updateState = () => this.ngZone.run(() => this.presenceStateSubject.next({ ...channel.presenceState() }));
        this.presenceUpdateState = updateState;

        channel
            .on('presence', { event: 'sync' }, updateState)
            .on('presence', { event: 'join' }, updateState)
            .on('presence', { event: 'leave' }, updateState)
            .subscribe(async (s: string) => {
                if (s === 'SUBSCRIBED') {
                    await channel.track({ user_id: user.id, status });
                    this.currentPresenceStatus = status;
                }
            });

        this.presenceChannel = channel;
    }

    /** Retire la présence de l'utilisateur du canal sans le fermer (préserve l'abonnement pour la prochaine navigation). */
    untrackPresence(): void {
        if (this.presenceChannel) {
            this.presenceChannel.untrack().catch(() => undefined);
        }
        this.currentPresenceStatus = null;
        this.ngZone.run(() => this.presenceStateSubject.next({}));
    }

    /** Retourne un Observable du statut de présence de chaque ami. */
    subscribeToFriendsPresence(friendIds: string[]): Observable<Map<string, FriendStatus>> {
        return this.presenceStateSubject.pipe(
            map((state) => {
                const result = new Map<string, FriendStatus>();
                for (const id of friendIds) result.set(id, 'offline');
                for (const [key, presences] of Object.entries(state)) {
                    if (friendIds.includes(key) && presences.length > 0) {
                        const p = presences[0] as { status: 'online' | 'in_game' };
                        result.set(key, p.status ?? 'offline');
                    }
                }
                return result;
            }),
        );
    }

    // ─── Amis ────────────────────────────────────────────────────────────────────

    /** Envoie une demande d'ami à l'utilisateur portant le pseudo donné. */
    async sendFriendRequest(username: string): Promise<void> {
        const me = this.getCurrentUser();
        if (!me) throw new Error('Non connecté');

        const { data: profile, error: profileError } = await this.supabase
            .from('profiles')
            .select('id')
            .ilike('username', username.trim())
            .maybeSingle();

        if (profileError || !profile) throw new Error('Utilisateur introuvable');
        if (profile.id === me.id) throw new Error('Tu ne peux pas t\'ajouter toi-même');

        const { data: existing } = await this.supabase
            .from('friendships')
            .select('id')
            .or(`and(requester_id.eq.${me.id},recipient_id.eq.${profile.id}),and(requester_id.eq.${profile.id},recipient_id.eq.${me.id})`)
            .maybeSingle();

        if (existing) throw new Error('Déjà ami ou demande déjà envoyée');

        const { error } = await this.supabase
            .from('friendships')
            .insert({ requester_id: me.id, recipient_id: profile.id });

        if (error) throw error;
    }

    /** Récupère la liste des amis acceptés avec leurs profils. */
    async getFriendsWithStatus(): Promise<FriendWithStatus[]> {
        const me = this.getCurrentUser();
        if (!me) return [];

        const { data: friendships } = await this.supabase
            .from('friendships')
            .select('*')
            .eq('status', 'accepted')
            .or(`requester_id.eq.${me.id},recipient_id.eq.${me.id}`);

        if (!friendships?.length) return [];

        const friendIds = friendships.map((f: Friendship) => (f.requester_id === me.id ? f.recipient_id : f.requester_id));
        const { data: profiles } = await this.supabase.from('profiles').select('id, username, avatar_url').in('id', friendIds);
        const profileMap = new Map((profiles ?? []).map((p: any) => [p.id, p]));

        return friendships.map((f: Friendship) => {
            const friendId = f.requester_id === me.id ? f.recipient_id : f.requester_id;
            const profile = profileMap.get(friendId);
            return { id: f.id, friendId, username: profile?.username ?? 'Inconnu', avatarUrl: profile?.avatar_url, status: 'offline' as FriendStatus };
        });
    }

    /** Récupère les demandes d'amitié en attente adressées à l'utilisateur courant. */
    async getPendingRequests(): Promise<FriendRequest[]> {
        const me = this.getCurrentUser();
        if (!me) return [];

        const { data: friendships } = await this.supabase
            .from('friendships')
            .select('*')
            .eq('status', 'pending')
            .eq('recipient_id', me.id);

        if (!friendships?.length) return [];

        const requesterIds = friendships.map((f: Friendship) => f.requester_id);
        const { data: profiles } = await this.supabase.from('profiles').select('id, username, avatar_url').in('id', requesterIds);
        const profileMap = new Map((profiles ?? []).map((p: any) => [p.id, p]));

        return friendships.map((f: Friendship) => {
            const profile = profileMap.get(f.requester_id);
            return { id: f.id, requesterId: f.requester_id, username: profile?.username ?? 'Inconnu', avatarUrl: profile?.avatar_url };
        });
    }

    /** Accepte une demande d'amitié. */
    async acceptFriendRequest(friendshipId: string): Promise<void> {
        const { error } = await this.supabase.from('friendships').update({ status: 'accepted' }).eq('id', friendshipId);
        if (error) throw error;
    }

    /** Refuse (supprime) une demande d'amitié. */
    async declineFriendRequest(friendshipId: string): Promise<void> {
        const { error } = await this.supabase.from('friendships').delete().eq('id', friendshipId);
        if (error) throw error;
    }

    /** Supprime une relation d'amitie. */
    async removeFriend(friendshipId: string): Promise<void> {
        const { error } = await this.supabase.from('friendships').delete().eq('id', friendshipId);
        if (error) throw error;
    }

    /** S'abonne aux changements de la table friendships pour l'utilisateur courant. */
    subscribeToFriendships(): Observable<void> {
        return new Observable((observer) => {
            const userId = this.getCurrentUser()?.id;
            if (!userId) return;

            const channel = this.supabase
                .channel(`friendships-${userId}`)
                .on('postgres_changes', { event: '*', schema: 'public', table: 'friendships' }, (payload: any) => {
                    const record = payload.new ?? payload.old;
                    if (record?.requester_id === userId || record?.recipient_id === userId) {
                        observer.next();
                    }
                })
                .subscribe();

            return () => { this.supabase.removeChannel(channel); };
        });
    }

    // ─── Invitations de jeu ──────────────────────────────────────────────────────

    /** Crée une room et une invitation de jeu pour un ami dans le mode choisi. */
    async sendGameInvite(recipientId: string, gameMode: GameMode = 'guess_my_pokemon'): Promise<{ roomId: string; inviteId: string }> {
        const me = this.getCurrentUser();
        if (!me) throw new Error('Non connecté');

        let roomId: string;
        try {
            if (gameMode === 'stat_duel') {
                roomId = await this.createStatDuelRoom();
            } else if (gameMode === 'draft_duo') {
                roomId = await this.createDraftDuoRoom();
            } else if (gameMode === 'who_that_pokemon') {
                roomId = await this.createWhoPokemonRoom();
            } else {
                roomId = await this.createRoom();
            }
        } catch (err) {
            console.error('[sendGameInvite] échec création room:', err);
            throw err;
        }

        const { data, error } = await this.supabase
            .from('game_invites')
            .insert({ sender_id: me.id, recipient_id: recipientId, room_id: roomId, game_mode: gameMode })
            .select('id')
            .single();

        if (error) {
            console.error('[sendGameInvite] échec insert game_invites:', error);
            throw error;
        }
        return { roomId, inviteId: (data as { id: string }).id };
    }

    /** Accepte une invitation de jeu et rejoint la room correspondant au mode. */
    async acceptGameInvite(inviteId: string, roomId: string, gameMode: GameMode = 'guess_my_pokemon'): Promise<void> {
        const me = this.getCurrentUser();
        if (!me) throw new Error('Non connecté');

        const { data: invite, error: inviteError } = await this.supabase
            .from('game_invites')
            .select('id, recipient_id, room_id, game_mode, status')
            .eq('id', inviteId)
            .single();

        if (inviteError) throw inviteError;
        const currentInvite = invite as Pick<GameInvite, 'id' | 'recipient_id' | 'room_id' | 'game_mode' | 'status'>;
        if (currentInvite.recipient_id !== me.id) throw new Error('Invitation non autorisée');
        if (currentInvite.room_id !== roomId || currentInvite.game_mode !== gameMode) throw new Error('Invitation incohérente');
        if (currentInvite.status !== 'pending') throw new Error('Invitation déjà traitée');

        if (gameMode === 'stat_duel') {
            await this.joinStatDuelRoom(roomId);
        } else if (gameMode === 'draft_duo') {
            await this.joinDraftDuoRoom(roomId);
        } else if (gameMode === 'who_that_pokemon') {
            await this.joinWhoPokemonRoom(roomId);
        } else {
            await this.joinRoom(roomId);
        }

        const { error } = await this.supabase.from('game_invites').update({ status: 'accepted' }).eq('id', inviteId);
        if (error) throw error;
    }

    /** Refuse une invitation de jeu. */
    async declineGameInvite(inviteId: string): Promise<void> {
        const { error } = await this.supabase.from('game_invites').update({ status: 'declined' }).eq('id', inviteId);
        if (error) throw error;
    }

    /** Recharge les invitations en attente reçues pendant que l'accueil était fermé. */
    async getPendingGameInvites(): Promise<GameInvite[]> {
        const userId = this.getCurrentUser()?.id;
        if (!userId) return [];

        const { data, error } = await this.supabase
            .from('game_invites')
            .select('*')
            .eq('recipient_id', userId)
            .eq('status', 'pending')
            .order('created_at', { ascending: false });
        if (error) throw error;

        const invites = (data ?? []) as GameInvite[];
        const senderIds = [...new Set(invites.map(invite => invite.sender_id))];
        if (senderIds.length === 0) return invites;

        const { data: profiles } = await this.supabase
            .from('profiles')
            .select('id, username')
            .in('id', senderIds);
        const usernames = new Map((profiles ?? []).map((profile: any) => [profile.id, profile.username]));
        return invites.map(invite => ({
            ...invite,
            sender_profile: usernames.has(invite.sender_id) ? { username: usernames.get(invite.sender_id)! } : undefined,
        }));
    }

    /** S'abonne aux nouvelles invitations de jeu reçues par l'utilisateur courant. */
    subscribeToIncomingGameInvites(): Observable<GameInvite> {
        return new Observable((observer) => {
            const userId = this.getCurrentUser()?.id;
            if (!userId) return;

            const channel = this.supabase
                .channel(`incoming-invites-${userId}`)
                .on(
                    'postgres_changes',
                    { event: 'INSERT', schema: 'public', table: 'game_invites', filter: `recipient_id=eq.${userId}` },
                    async (payload: any) => {
                        const invite = payload.new as GameInvite;
                        const { data: profile } = await this.supabase.from('profiles').select('username').eq('id', invite.sender_id).single();
                        observer.next({ ...invite, sender_profile: profile ? { username: (profile as any).username } : undefined });
                    },
                )
                .subscribe();

            return () => { this.supabase.removeChannel(channel); };
        });
    }

    /** S'abonne aux mises à jour d'une invitation de jeu spécifique (accept/decline). */
    subscribeToGameInviteResponse(inviteId: string): Observable<GameInvite> {
        return new Observable((observer) => {
            const channel = this.supabase
                .channel(`invite-response-${inviteId}`)
                .on(
                    'postgres_changes',
                    { event: 'UPDATE', schema: 'public', table: 'game_invites', filter: `id=eq.${inviteId}` },
                    (payload: any) => { observer.next(payload.new as GameInvite); },
                )
                .subscribe();

            return () => {
                this.supabase.removeChannel(channel);
            };
        });
    }

    // ─── Dresseurs battus ────────────────────────────────────────────────────────

    /** Récupère les index des dresseurs battus par l'utilisateur. */
    async getDefeatedTrainers(userId: string): Promise<number[]> {
        const { data, error } = await this.supabase
            .from('defeated_trainers')
            .select('trainer_index')
            .eq('user_id', userId);

        if (error) throw error;
        return (data as { trainer_index: number }[]).map(d => d.trainer_index);
    }

    /** Enregistre la victoire contre un dresseur. */
    async recordTrainerDefeat(userId: string, trainerIndex: number): Promise<void> {
        const { error } = await this.supabase
            .from('defeated_trainers')
            .upsert({ user_id: userId, trainer_index: trainerIndex }, { onConflict: 'user_id,trainer_index' });

        if (error) throw error;
    }

    /** Supprime toute la progression des dresseurs d'un utilisateur. */
    async resetTrainerProgress(userId: string): Promise<void> {
        const { count: existingCount, error: countError } = await this.supabase
            .from('defeated_trainers')
            .select('*', { count: 'exact', head: true })
            .eq('user_id', userId);

        if (countError) throw countError;

        const { data, error } = await this.supabase
            .from('defeated_trainers')
            .delete()
            .eq('user_id', userId)
            .select('trainer_index');

        if (error) throw error;

        if ((existingCount ?? 0) > 0 && (data?.length ?? 0) === 0) {
            throw new Error('Suppression refusée par Supabase. Vérifie les policies RLS de defeated_trainers.');
        }
    }
}
