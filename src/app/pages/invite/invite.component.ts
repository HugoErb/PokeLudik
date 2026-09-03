import { Component, input, OnInit, OnDestroy, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { SupabaseService } from '../../services/supabase.service';
import { ICONS } from '../../constants/icons';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';

@Component({
	selector: 'app-invite',
	imports: [AppHeaderComponent],
	schemas: [CUSTOM_ELEMENTS_SCHEMA],
	templateUrl: './invite.component.html',
})
export class InviteComponent implements OnInit, OnDestroy {
	protected readonly ICONS = ICONS;
	readonly roomId = input.required<string>();

	state: 'loading' | 'valid' | 'error' | 'full' = 'loading';
	errorMessage = '';
	headerTitle = 'Guess my Pokémon';
	headerIcon: string = ICONS.guess;
	headerIconClass = 'text-red-400';

	constructor(
		private readonly supabaseService: SupabaseService,
		private readonly router: Router,
		private readonly route: ActivatedRoute,
	) {}

	/** Lifecycle Angular : initialise le composant. */
	ngOnInit(): void {
		this.supabaseService.trackPresence('online');
		const mode = this.route.snapshot.queryParamMap.get('mode');
		if (mode === 'stat_duel') {
			this.headerTitle = 'Duel de Base Stats'; this.headerIcon = ICONS.statDuel; this.headerIconClass = 'text-cyan-300';
		} else if (mode === 'draft_duo') {
			this.headerTitle = 'Team Builder Duo'; this.headerIcon = ICONS.draft; this.headerIconClass = 'text-purple-300';
		} else if (mode === 'who_that_pokemon') {
			this.headerTitle = 'Qui est ce Pokémon ?'; this.headerIcon = ICONS.whoPokemon; this.headerIconClass = 'text-amber-300';
		} else if (mode === 'pokemon_auction') {
			this.headerTitle = 'Enchères Pokémon'; this.headerIcon = ICONS.auction; this.headerIconClass = 'text-orange-300';
		}
		if (mode === 'stat_duel') {
			this.loadStatDuelRoom();
		} else if (mode === 'draft_duo') {
			this.loadDraftDuoRoom();
		} else if (mode === 'who_that_pokemon') {
			this.loadWhoPokemonRoom();
		} else if (mode === 'pokemon_auction') {
			this.loadPokemonAuctionRoom();
		} else {
			this.loadRoom();
		}
	}

	/** Lifecycle Angular : nettoie les abonnements et timers du composant. */
	ngOnDestroy(): void {
		this.supabaseService.untrackPresence();
	}

	/** Charge une room Duel de Base Stats depuis l'invitation. */
	private async loadStatDuelRoom(): Promise<void> {
		try {
			const room = await this.supabaseService.getStatDuelRoom(this.roomId());

			if (room?.status !== 'waiting') {
				this.state = 'error';
				this.errorMessage = "Cette invitation n'est plus valide.";
				return;
			}

			if (room.player2_id) {
				this.state = 'full';
				this.errorMessage = 'Cette partie est déjà complète.';
				return;
			}

			const currentUser = await firstValueFrom(this.supabaseService.authReady$);
			if (currentUser?.id === room.player1_id) {
				this.router.navigate(['/lobby', this.roomId()], { queryParams: { mode: 'stat_duel' } });
				return;
			}

			try {
				await this.supabaseService.joinStatDuelRoom(this.roomId());
				await this.router.navigate(['/lobby', this.roomId()], { queryParams: { mode: 'stat_duel' } });
			} catch {
				this.state = 'error';
				this.errorMessage = 'Impossible de rejoindre la partie.';
			}
		} catch {
			this.state = 'error';
			this.errorMessage = "Cette invitation n'est plus valide.";
		}
	}

	/** Charge une room Draft Duo depuis l'invitation. */
	private async loadDraftDuoRoom(): Promise<void> {
		try {
			const room = await this.supabaseService.getDraftDuoRoom(this.roomId());

			if (room?.status !== 'waiting') {
				this.state = 'error';
				this.errorMessage = "Cette invitation n'est plus valide.";
				return;
			}

			if (room.player2_id) {
				this.state = 'full';
				this.errorMessage = 'Cette partie est déjà complète.';
				return;
			}

			const currentUser = await firstValueFrom(this.supabaseService.authReady$);
			if (currentUser?.id === room.player1_id) {
				this.router.navigate(['/lobby', this.roomId()], { queryParams: { mode: 'draft_duo' } });
				return;
			}

			try {
				await this.supabaseService.joinDraftDuoRoom(this.roomId());
				await this.router.navigate(['/lobby', this.roomId()], { queryParams: { mode: 'draft_duo' } });
			} catch {
				this.state = 'error';
				this.errorMessage = 'Impossible de rejoindre la partie.';
			}
		} catch {
			this.state = 'error';
			this.errorMessage = "Cette invitation n'est plus valide.";
		}
	}

	private async loadWhoPokemonRoom(): Promise<void> {
		try {
			const room = await this.supabaseService.getWhoPokemonRoom(this.roomId());

			if (room?.status !== 'waiting') {
				this.state = 'error';
				this.errorMessage = "Cette invitation n'est plus valide.";
				return;
			}

			if (room.player2_id) {
				this.state = 'full';
				this.errorMessage = 'Cette partie est déjà complète.';
				return;
			}

			const currentUser = await firstValueFrom(this.supabaseService.authReady$);
			if (currentUser?.id === room.player1_id) {
				this.router.navigate(['/lobby', this.roomId()], { queryParams: { mode: 'who_that_pokemon' } });
				return;
			}

			try {
				await this.supabaseService.joinWhoPokemonRoom(this.roomId());
				await this.router.navigate(['/lobby', this.roomId()], { queryParams: { mode: 'who_that_pokemon' } });
			} catch {
				this.state = 'error';
				this.errorMessage = 'Impossible de rejoindre la partie.';
			}
		} catch {
			this.state = 'error';
			this.errorMessage = "Cette invitation n'est plus valide.";
		}
	}

	private async loadPokemonAuctionRoom(): Promise<void> {
		try {
			const currentUser = await firstValueFrom(this.supabaseService.authReady$);
			let room;
			try {
				room = await this.supabaseService.getPokemonAuctionRoom(this.roomId());
			} catch {
				await this.supabaseService.joinPokemonAuctionRoom(this.roomId());
				await this.router.navigate(['/lobby', this.roomId()], { queryParams: { mode: 'pokemon_auction' } });
				return;
			}
			if (room.status !== 'waiting') { this.state = 'error'; this.errorMessage = "Cette invitation n'est plus valide."; return; }
			if (room.player2_id) { this.state = 'full'; this.errorMessage = 'Cette partie est déjà complète.'; return; }
			if (currentUser?.id !== room.player1_id) await this.supabaseService.joinPokemonAuctionRoom(this.roomId());
			await this.router.navigate(['/lobby', this.roomId()], { queryParams: { mode: 'pokemon_auction' } });
		} catch {
			this.state = 'error'; this.errorMessage = "Cette invitation n'est plus valide.";
		}
	}

	/** Charge une room Guess my Pokemon depuis l'invitation. */
	private async loadRoom(): Promise<void> {
		try {
			const room = await this.supabaseService.getRoomById(this.roomId());

			if (room?.status !== 'waiting' && room?.status !== 'ready') {
				this.state = 'error';
				this.errorMessage = "Cette invitation n'est plus valide.";
				return;
			}

			if (room.player2_id) {
				this.state = 'full';
				this.errorMessage = 'Cette partie est déjà complète.';
				return;
			}

			const currentUser = await firstValueFrom(this.supabaseService.authReady$);
			if (currentUser?.id === room.player1_id) {
				this.router.navigate(['/lobby', this.roomId()]);
				return;
			}

			try {
				await this.supabaseService.joinRoom(this.roomId());
				await this.router.navigate(['/lobby', this.roomId()]);
				return;
			} catch {
				this.state = 'error';
				this.errorMessage = 'Impossible de rejoindre la partie.';
				return;
			}
		} catch {
			this.state = 'error';
			this.errorMessage = "Cette invitation n'est plus valide.";
		}
	}

	/** Refuse l'invitation et revient a l'accueil. */
	decline(): void {
		this.router.navigate(['/home']);
	}
}
