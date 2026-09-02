import { TestBed } from '@angular/core/testing';

import { GameService } from './game.service';
import { SupabaseService } from './supabase.service';
import { PokemonService } from './pokemon.service';
import { Room } from '../models/room.model';

describe('GameService', () => {
  const user = { id: 'player-2' };
  let service: GameService;
  let supabaseService: jasmine.SpyObj<SupabaseService>;

  function room(overrides: Partial<Room>): Room {
    return {
      id: 'room-1',
      player1_id: 'player-1',
      player2_id: 'player-2',
      pokemon_p1: 25,
      pokemon_p2: 4,
      p1_ready: false,
      p2_ready: false,
      current_turn: 'player-1',
      status: 'playing',
      winner_id: null,
      created_at: '2026-05-07T00:00:00.000Z',
      settings: null,
      last_guess: null,
      ...overrides,
    };
  }

  beforeEach(() => {
    supabaseService = jasmine.createSpyObj<SupabaseService>('SupabaseService', [
      'getCurrentUser',
      'getRoomById',
      'updateRoom',
      'submitGuessPokemonGuess',
      'broadcastGuess',
      'broadcastPlayerLeft',
    ]);
    supabaseService.getCurrentUser.and.returnValue(user as any);
    supabaseService.updateRoom.and.resolveTo();
    supabaseService.submitGuessPokemonGuess.and.resolveTo(true);
    supabaseService.broadcastGuess.and.resolveTo();
    supabaseService.broadcastPlayerLeft.and.resolveTo();
    (supabaseService as any).currentUserSignal = jasmine.createSpy('currentUserSignal').and.returnValue(user);
    (supabaseService as any).broadcastEvents$ = { subscribe: () => ({ unsubscribe: () => undefined }) };

    TestBed.configureTestingModule({
      providers: [
        GameService,
        { provide: SupabaseService, useValue: supabaseService },
        { provide: PokemonService, useValue: {} },
      ],
    });

    service = TestBed.inject(GameService);
  });

  it('relit la room avant de refuser un guess pour eviter un tour local obsolete', async () => {
    service.currentRoom.set(room({ current_turn: 'player-1' }));
    supabaseService.getRoomById.and.resolveTo(room({ current_turn: 'player-2' }));

    const result = await service.guess('room-1', 25);

    expect(result).toBe('correct');
    expect(supabaseService.submitGuessPokemonGuess).toHaveBeenCalledWith('room-1', 25);
  });

  it("laisse le serveur valider un mauvais guess et diffuse seulement l'animation", async () => {
    service.currentRoom.set(room({ current_turn: 'player-2' }));
    supabaseService.getRoomById.and.resolveTo(room({ current_turn: 'player-2' }));
    supabaseService.submitGuessPokemonGuess.and.resolveTo(false);

    const result = await service.guess('room-1', 4);

    expect(result).toBe('incorrect');
    expect(supabaseService.submitGuessPokemonGuess).toHaveBeenCalledWith('room-1', 4);
    expect(supabaseService.broadcastGuess).toHaveBeenCalledWith(4, 'player-2');
    expect(supabaseService.updateRoom).not.toHaveBeenCalled();
  });

  it("met a jour la room quand l'adversaire rejoint une invitation", () => {
    service.currentRoom.set(room({
      player2_id: null,
      status: 'waiting',
    }));

    service.currentRoom.set(room({
      player2_id: 'player-2',
      status: 'waiting',
    }));

    expect(service.currentRoom()?.player2_id).toBe('player-2');
  });

  it("signale l'abandon avant de terminer la room", async () => {
    service.currentRoom.set(room({ status: 'playing', winner_id: 'player-1' }));

    await service.cancelRoom('room-1');

    expect(supabaseService.broadcastPlayerLeft).toHaveBeenCalled();
    expect(supabaseService.updateRoom).toHaveBeenCalledWith('room-1', jasmine.objectContaining({
      status: 'finished',
      winner_id: null,
      p1_ready: false,
      p2_ready: false,
    }));
    expect(service.currentRoom()).toBeNull();
  });
});
