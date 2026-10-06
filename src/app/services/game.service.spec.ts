import { TestBed } from '@angular/core/testing';
import { NEVER } from 'rxjs';

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
      'cancelGuessPokemonRoom',
      'replayGuessPokemonRoom',
      'submitGuessPokemonGuess',
      'broadcastGuess',
      'broadcastPlayerLeft',
    ]);
    supabaseService.getCurrentUser.and.returnValue(user as any);
    supabaseService.updateRoom.and.resolveTo();
    supabaseService.cancelGuessPokemonRoom.and.resolveTo();
    supabaseService.replayGuessPokemonRoom.and.resolveTo();
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
    expect(supabaseService.cancelGuessPokemonRoom).toHaveBeenCalledOnceWith('room-1');
    expect(service.currentRoom()).toBeNull();
  });

  it('termine une victoire du bot sans attribuer la victoire au joueur', async () => {
    const player1 = { id: 'player-1' };
    supabaseService.getCurrentUser.and.returnValue(player1 as any);
    (supabaseService.currentUserSignal as jasmine.Spy).and.returnValue(player1);
    service.currentRoom.set(room({ player2_id: null, current_turn: null }));
    supabaseService.getRoomById.and.resolveTo(room({ player2_id: null, status: 'finished', winner_id: null }));

    const result = await service.simulateOpponentGuess('room-1', 25);

    expect(result).toBe('correct');
    expect(supabaseService.cancelGuessPokemonRoom).toHaveBeenCalledOnceWith('room-1');
    expect(service.currentRoom()?.winner_id).toBeNull();
  });

  it('relance une revanche acceptée via la RPC dédiée puis rafraîchit la room', async () => {
    const player1 = { id: 'player-1' };
    supabaseService.getCurrentUser.and.returnValue(player1 as any);
    (supabaseService.currentUserSignal as jasmine.Spy).and.returnValue(player1);
    const finished = room({ status: 'finished', p1_ready: true, p2_ready: true, winner_id: 'player-2' });
    const replay = room({ status: 'selecting', pokemon_p1: null, pokemon_p2: null });
    service.currentRoom.set(finished);
    supabaseService.getRoomById.and.returnValues(Promise.resolve(finished), Promise.resolve(finished), Promise.resolve(replay));

    await service.requestReplay('room-1');

    expect(supabaseService.replayGuessPokemonRoom).toHaveBeenCalledOnceWith('room-1');
    expect(supabaseService.updateRoom).toHaveBeenCalledOnceWith('room-1', { p1_ready: true });
    expect(service.currentRoom()).toEqual(replay);
  });

  it('ignore une réponse de polling périmée arrivée après la revanche', async () => {
    const replay = room({ status: 'selecting', pokemon_p1: null, pokemon_p2: null, version: 8 });
    service.currentRoom.set(replay);
    supabaseService.getRoomById.and.resolveTo(room({ status: 'finished', p1_ready: true, p2_ready: true, winner_id: 'player-2', version: 7 }));

    await service.refreshRoom('room-1');

    expect(service.currentRoom()).toEqual(replay);
    expect(supabaseService.replayGuessPokemonRoom).not.toHaveBeenCalled();
  });

  it('ne démarre pas de polling si le watch est arrêté pendant le chargement initial', async () => {
    (supabaseService as any).subscribeToRoom = jasmine.createSpy('subscribeToRoom').and.returnValue(NEVER);
    let resolveRoom!: (value: Room) => void;
    supabaseService.getRoomById.and.returnValue(new Promise<Room>((resolve) => { resolveRoom = resolve; }));

    const joining = service.joinAndWatch('room-1');
    service.stopWatching();
    resolveRoom(room({}));
    await joining;

    expect((service as any).pollInterval).toBeUndefined();
    expect(service.currentRoom()).toBeNull();
  });

  it('attend les deux accords avant de relancer', async () => {
    const finished = room({ status: 'finished', p1_ready: false, p2_ready: true });
    service.currentRoom.set(finished);
    supabaseService.getRoomById.and.resolveTo(finished);
    await service.requestReplay('room-1');
    expect(supabaseService.replayGuessPokemonRoom).not.toHaveBeenCalled();
  });
});
