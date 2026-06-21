import { DraftDuoRoom } from '../models/room.model';
import { resolveLobbyGameMode, shouldEnterMultiplayerGame } from './multiplayer-room-state';

function room(status: DraftDuoRoom['status']): DraftDuoRoom {
  return {
    id: 'room-1',
    player1_id: 'player-1',
    player2_id: 'player-2',
    status,
    p1_team: [],
    p2_team: [],
    winner: null,
    p1_ready: false,
    p2_ready: false,
    settings: null,
    created_at: '2026-05-18T00:00:00.000Z',
  };
}

describe('multiplayer room state', () => {
  it('entre en partie uniquement quand la room est en playing', () => {
    expect(shouldEnterMultiplayerGame(room('waiting'))).toBeFalse();
    expect(shouldEnterMultiplayerGame(room('playing'))).toBeTrue();
    expect(shouldEnterMultiplayerGame(room('finished'))).toBeFalse();
  });

  it('résout le mode du lobby depuis le paramètre de route', () => {
    expect(resolveLobbyGameMode('stat_duel')).toBe('stat_duel');
    expect(resolveLobbyGameMode('draft_duo')).toBe('draft_duo');
    expect(resolveLobbyGameMode('who_that_pokemon')).toBe('who_that_pokemon');
    expect(resolveLobbyGameMode(null)).toBe('guess_my_pokemon');
    expect(resolveLobbyGameMode('inconnu')).toBe('guess_my_pokemon');
  });
});
