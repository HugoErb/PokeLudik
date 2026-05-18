import { DraftDuoRoom, StatDuelRoom, WhoPokemonRoom } from '../models/room.model';

type MultiplayerRoom = StatDuelRoom | DraftDuoRoom | WhoPokemonRoom;

export function shouldEnterMultiplayerGame(room: MultiplayerRoom): boolean {
  return room.status === 'playing';
}

