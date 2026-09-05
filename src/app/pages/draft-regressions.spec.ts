import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { DraftComponent } from './draft/draft.component';
import { DraftDuoComponent } from './draft-duo/draft-duo.component';
import { DraftTrainerComponent } from './draft-trainer/draft-trainer.component';
import { PokemonService } from '../services/pokemon.service';
import { SupabaseService } from '../services/supabase.service';
import { Pokemon } from '../models/pokemon.model';
import { DraftDuoRoom } from '../models/room.model';
import { DEFAULT_MODE_SETTINGS } from '../models/game-settings.model';

describe('Régressions des parcours de draft', () => {
  const pool: Pokemon[] = Array.from({ length: 12 }, (_, i) => ({
    id: i + 1, name: `Pokémon ${i + 1}`, types: ['Normal'], generation: i < 6 ? 1 : 2,
    category: 'classique', evolution_stage: 'base', sprite: '', height: 1, weight: 1, description: '',
    stats: { pv: 50, attaque: 50, defense: 50, atq_spe: 50, def_spe: 50, vitesse: 50 }, rating: 5,
  }));
  let supabase: jasmine.SpyObj<SupabaseService>;

  beforeEach(() => {
    sessionStorage.removeItem('draft_state');
    sessionStorage.removeItem('draft-duo-state-test-room-p1');
    supabase = jasmine.createSpyObj('SupabaseService', ['updateDraftDuoRoom', 'getProfile', 'getCurrentUser', 'trackPresence']);
    supabase.updateDraftDuoRoom.and.resolveTo();
    supabase.getCurrentUser.and.returnValue({ id: 'p1' } as any);
    TestBed.configureTestingModule({
      imports: [DraftComponent, DraftDuoComponent, DraftTrainerComponent],
      providers: [provideRouter([]), { provide: PokemonService, useValue: { loadAll: () => of(pool) } },
        { provide: SupabaseService, useValue: supabase }],
    });
  });

  afterEach(() => {
    sessionStorage.removeItem('draft_state');
    sessionStorage.removeItem('draft-duo-state-test-room-p1');
  });

  function duo(team: number[]) {
    const fixture = TestBed.createComponent(DraftDuoComponent);
    fixture.componentRef.setInput('roomId', 'test-room');
    const component = fixture.componentInstance;
    const room = { id: 'test-room', player1_id: 'p1', player2_id: 'p2', p1_team: team,
      p2_team: [7], status: 'playing', settings: null, winner: null } as DraftDuoRoom;
    component.room.set(room);
    component.isPlayer1.set(true);
    component.player2Username.set('Adversaire');
    const timer = spyOn<any>(component, 'startTimer');
    return { component, room, timer };
  }

  it('restaure les choix du serveur après une actualisation sans cache local', async () => {
    const { component, room } = duo([1, 2, 3]);
    await (component as any).enterPlayingPhase(room);
    expect(component.lockedCount()).toBe(3);
    expect(component.lockedPokemon().filter(Boolean).map(p => p!.id).sort()).toEqual([1, 2, 3]);
    expect(new Set(component.slots().map(p => p!.id)).size).toBe(6);
    expect(supabase.updateDraftDuoRoom).not.toHaveBeenCalled();
  });

  it('conserve les positions et les propositions du cache quand il correspond à la base', async () => {
    const first = duo([1, 2, 3]);
    await (first.component as any).enterPlayingPhase(first.room);
    const second = duo([1, 2, 3]);
    await (second.component as any).enterPlayingPhase(second.room);
    expect(second.component.slots()).toEqual(first.component.slots());
    expect(second.component.lockedPokemon()).toEqual(first.component.lockedPokemon());
  });

  it('ignore un ancien cache quand la base contient une équipe différente', async () => {
    const first = duo([1, 2, 3]);
    await (first.component as any).enterPlayingPhase(first.room);
    const second = duo([4, 5]);
    await (second.component as any).enterPlayingPhase(second.room);
    expect(second.component.lockedCount()).toBe(2);
    expect(second.component.lockedPokemon().filter(Boolean).map(p => p!.id).sort()).toEqual([4, 5]);
  });

  it('reprend directement l’attente si les six choix sont déjà enregistrés', async () => {
    const { component, room, timer } = duo([1, 2, 3, 4, 5, 6]);
    await (component as any).enterPlayingPhase(room);
    expect(component.phase()).toBe('waiting-opponent');
    expect(component.lockedCount()).toBe(6);
    expect(timer).not.toHaveBeenCalled();
  });

  it('permet de retenter le sixième choix après une erreur réseau sans perdre les cinq premiers', async () => {
    const { component, room } = duo([1, 2, 3, 4, 5]);
    await (component as any).enterPlayingPhase(room);
    const index = component.lockedPokemon().findIndex(p => !p);
    supabase.updateDraftDuoRoom.and.rejectWith(new Error('network'));
    await component.onSlotClick(index);
    expect(component.lockedCount()).toBe(5);
    expect(component.phase()).toBe('playing');
    expect(component.saveError()).not.toBe('');

    supabase.updateDraftDuoRoom.and.resolveTo();
    await component.onSlotClick(index);
    expect(component.lockedCount()).toBe(6);
    expect(component.phase()).toBe('waiting-opponent');
    expect(component.saveError()).toBe('');
    const team = supabase.updateDraftDuoRoom.calls.mostRecent().args[1].p1_team!;
    expect(team.length).toBe(6);
    expect(team).toEqual(jasmine.arrayContaining([1, 2, 3, 4, 5]));
  });

  it('restaure les filtres du solo avant les tirages suivants', () => {
    const first = TestBed.createComponent(DraftComponent).componentInstance;
    first.updateGameSettings({ ...DEFAULT_MODE_SETTINGS.draft_duo, generations: [1], categories: ['classique'] });
    (first as any).initDraft();
    const saved = JSON.parse(sessionStorage.getItem('draft_state')!);
    const second = TestBed.createComponent(DraftComponent).componentInstance;
    (second as any).restoreState(saved);
    expect(second.settings().generations).toEqual([1]);
    expect(second.settings().categories).toEqual(['classique']);
    expect((second as any).getConfiguredPokemonPool().every((p: Pokemon) => p.generation === 1)).toBeTrue();
  });

  it('conserve la progression des sauvegardes solo antérieures au correctif', () => {
    const component = TestBed.createComponent(DraftComponent).componentInstance;
    (component as any).restoreState({ slots: [1, 2, 3, 4, 5, 6], lockedIndices: [2],
      lockedPokemon: [null, null, 3, null, null, null], usedIds: [1, 2, 3, 4, 5, 6], phase: 'draft', showScore: false });
    expect(component.lockedCount()).toBe(1);
    expect(component.lockedPokemon()[2]?.id).toBe(3);
    expect(component.phase()).toBe('draft');
  });

  it('démarre le chronomètre à la fermeture de l’intro même si le profil n’a pas répondu', async () => {
    let resolveProfile!: (profile: any) => void;
    supabase.getProfile.and.returnValue(new Promise(resolve => resolveProfile = resolve));
    const component = TestBed.createComponent(DraftTrainerComponent).componentInstance;
    component.trainer.set({ nom: 'Pierre', region: 'Kanto', generation: 1, role: '', version: '', image: '', pokemons: [1] });
    const timer = spyOn<any>(component, 'startTimer');
    const initializing = (component as any).initDraft();
    expect(component.showDuelIntro()).toBeTrue();
    component.onDuelIntroClosed();
    expect(timer).toHaveBeenCalledTimes(1);
    resolveProfile({ username: 'Moi' });
    await initializing;
    expect(timer).toHaveBeenCalledTimes(1);
  });
});
