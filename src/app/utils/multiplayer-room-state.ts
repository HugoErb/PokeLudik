import { DraftDuoRoom, GameMode, PokemonAuctionRoom, SizeUpRoom, StatDuelRoom, WhoPokemonRoom } from '../models/room.model';

type MultiplayerRoom = StatDuelRoom | DraftDuoRoom | WhoPokemonRoom | PokemonAuctionRoom | SizeUpRoom;

export function shouldEnterMultiplayerGame(room: MultiplayerRoom): boolean {
  return room.status === 'playing';
}

export function resolveLobbyGameMode(mode: string | null | undefined): GameMode {
  if (mode === 'stat_duel' || mode === 'draft_duo' || mode === 'who_that_pokemon' || mode === 'pokemon_auction' || mode === 'size_up') return mode;
  return 'guess_my_pokemon';
}

type VersionedRoom = { id: string; version?: number };

/** Vrai si `next` est un état plus ancien que `current` (réponse de polling arrivée en retard). */
export function isStaleRoomState(current: VersionedRoom | null, next: VersionedRoom): boolean {
  return !!current && current.id === next.id && current.version != null && next.version != null && next.version < current.version;
}
