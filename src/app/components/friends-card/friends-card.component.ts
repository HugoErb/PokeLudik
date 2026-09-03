import { Component, OnInit, OnDestroy, Output, EventEmitter, CUSTOM_ELEMENTS_SCHEMA, HostListener, inject, signal, computed } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { SupabaseService } from '../../services/supabase.service';
import { FriendStatus, FriendWithStatus, FriendRequest, GameMode } from '../../models/room.model';
import { ICONS } from '../../constants/icons';

@Component({
	selector: 'app-friends-card',
	standalone: true,
	imports: [FormsModule],
	schemas: [CUSTOM_ELEMENTS_SCHEMA],
	templateUrl: './friends-card.component.html',
	styles: [
		':host { display: block; }',
		`@keyframes tabFadeIn { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: translateY(0); } }
		.tab-content { animation: tabFadeIn 0.18s ease-out both; }`,
	],
})
export class FriendsCardComponent implements OnInit, OnDestroy {
	protected readonly ICONS = ICONS;
	private readonly supabaseService = inject(SupabaseService);

	@Output() inviteRequested = new EventEmitter<{ friendId: string; username: string; gameMode: GameMode }>();

	activeTab = signal<'friends' | 'requests' | 'add'>('friends');
	friends = signal<FriendWithStatus[]>([]);
	pendingRequests = signal<FriendRequest[]>([]);
	isLoadingFriends = signal(true);
	confirmDeleteFriend = signal<FriendWithStatus | null>(null);
	openMenuFriend = signal<FriendWithStatus | null>(null);
	menuPosition = signal<{ top: number; right: number } | null>(null);

	hasPendingRequests = computed(() => this.pendingRequests().length > 0);

	tabIndicatorLeft = computed(() => {
		const map: Record<string, string> = {
			friends: '4px',
			requests: 'calc(8px + (100% - 16px) / 3)',
			add: 'calc(12px + (100% - 16px) * 2 / 3)',
		};
		return map[this.activeTab()];
	});

	addFriendInput = '';
	addFriendError = '';
	addFriendSuccess = '';
	isAddingFriend = false;

	private presenceSub?: Subscription;
	private friendshipsSub?: Subscription;

	/** Lifecycle Angular : initialise le composant. */
	async ngOnInit(): Promise<void> {
		await this.reload();
		this.friendshipsSub = this.supabaseService.subscribeToFriendships().subscribe(() => {
			void this.reload(false);
		});
	}

	/** Lifecycle Angular : nettoie les abonnements et timers du composant. */
	ngOnDestroy(): void {
		this.presenceSub?.unsubscribe();
		this.friendshipsSub?.unsubscribe();
	}

	/** Recharge les amis et demandes d'amitie. */
	private async reload(showSpinner = true): Promise<void> {
		if (showSpinner) this.isLoadingFriends.set(true);
		const [friends, requests] = await Promise.all([
			this.supabaseService.getFriendsWithStatus(),
			this.supabaseService.getPendingRequests(),
		]);
		this.friends.set(friends);
		this.pendingRequests.set(requests);
		if (showSpinner) this.isLoadingFriends.set(false);

		this.presenceSub?.unsubscribe();
		const friendIds = friends.map((f) => f.friendId);
		if (friendIds.length > 0) {
			this.presenceSub = this.supabaseService.subscribeToFriendsPresence(friendIds).subscribe((statusMap) => {
				this.friends.update((list) =>
					list
						.map((f) => ({ ...f, status: statusMap.get(f.friendId) ?? 'offline' }))
						.sort((a, b) => {
							const order: Record<FriendStatus, number> = { online: 0, in_game: 1, offline: 2 };
							return order[a.status] - order[b.status];
						}),
				);
			});
		}
	}

	/** Envoie une demande d'ami. */
	async sendFriendRequest(): Promise<void> {
		const username = this.addFriendInput.trim();
		if (!username) return;
		this.isAddingFriend = true;
		this.addFriendError = '';
		this.addFriendSuccess = '';
		try {
			await this.supabaseService.sendFriendRequest(username);
			this.addFriendSuccess = `Demande envoyée à ${username} !`;
			this.addFriendInput = '';
		} catch (err: any) {
			this.addFriendError = err.message ?? 'Erreur lors de l\'envoi';
		} finally {
			this.isAddingFriend = false;
		}
	}

	/** Accepte une demande d'ami. */
	async acceptRequest(friendshipId: string): Promise<void> {
		await this.supabaseService.acceptFriendRequest(friendshipId);
	}

	/** Refuse une demande d'ami. */
	async declineRequest(friendshipId: string): Promise<void> {
		await this.supabaseService.declineFriendRequest(friendshipId);
	}

	/** Emet une demande d'invitation de jeu pour un ami. */
	inviteFriend(friend: FriendWithStatus, gameMode: GameMode): void {
		if (friend.status !== 'online') return;
		this.inviteRequested.emit({ friendId: friend.friendId, username: friend.username, gameMode });
	}

	/** Ouvre la confirmation de suppression d'ami. */
	askRemoveFriend(friend: FriendWithStatus): void {
		this.confirmDeleteFriend.set(friend);
	}

	/** Annule la suppression d'ami. */
	cancelRemove(): void {
		this.confirmDeleteFriend.set(null);
	}

	/** Confirme la suppression de l'ami selectionne. */
	async confirmRemove(): Promise<void> {
		const friend = this.confirmDeleteFriend();
		if (!friend) return;
		this.confirmDeleteFriend.set(null);
		await this.supabaseService.removeFriend(friend.id);
		await this.reload();
	}

	/** Ferme le menu contextuel lors d'un clic document. */
	@HostListener('document:click')
	onDocumentClick(): void {
		this.openMenuFriend.set(null);
		this.menuPosition.set(null);
	}

	/** Ouvre ou ferme le menu d'un ami. */
	toggleMenu(friend: FriendWithStatus, event: Event): void {
		event.stopPropagation();
		if (this.openMenuFriend()?.id === friend.id) {
			this.openMenuFriend.set(null);
			this.menuPosition.set(null);
		} else {
			const btn = event.currentTarget as HTMLElement;
			const rect = btn.getBoundingClientRect();
			const viewportMargin = 12;
			const menuGap = 8;
			const estimatedMenuHeight = 238;
			const opensUpward = rect.bottom + menuGap + estimatedMenuHeight > window.innerHeight;
			const top = opensUpward
				? Math.max(viewportMargin, rect.top - menuGap - estimatedMenuHeight)
				: Math.min(rect.bottom + menuGap, window.innerHeight - estimatedMenuHeight - viewportMargin);
			const right = Math.max(viewportMargin, window.innerWidth - rect.right);
			this.menuPosition.set({ top, right });
			this.openMenuFriend.set(friend);
		}
	}

	/** Ferme le menu d'ami ouvert. */
	closeMenu(): void {
		this.openMenuFriend.set(null);
		this.menuPosition.set(null);
	}

	/** Active l'onglet selectionne. */
	setTab(tab: 'friends' | 'requests' | 'add'): void {
		this.activeTab.set(tab);
		this.addFriendError = '';
		this.addFriendSuccess = '';
	}

	/** Retourne le libelle d'un statut d'ami. */
	statusLabel(status: FriendStatus): string {
		if (status === 'online') return 'En ligne';
		if (status === 'in_game') return 'En jeu';
		return 'Hors ligne';
	}

	/** Retourne la classe CSS du point de statut d'ami. */
	statusDotClass(status: FriendStatus): string {
		if (status === 'online') return 'bg-green-500';
		if (status === 'in_game') return 'bg-yellow-500';
		return 'bg-gray-500';
	}

	/** Retourne la classe CSS du texte de statut d'ami. */
	statusTextClass(status: FriendStatus): string {
		if (status === 'online') return 'text-green-400';
		if (status === 'in_game') return 'text-yellow-400';
		return 'text-slate-500';
	}
}
