import { Pokemon } from '../models/pokemon.model';
import { canUseRoomForDuoComplete, computeDuoCoverageScore, hasEnoughPokemonForDraft, pickOneStarter } from './draft-utils';

function pokemon(id: number, name: string, types: string[]): Pokemon {
  return {
    id,
    name,
    types,
    generation: 1,
    category: 'classique',
    evolution_stage: 'base',
    sprite: '',
    stats: { pv: 1, attaque: 1, defense: 1, atq_spe: 1, def_spe: 1, vitesse: 1 },
    height: 1,
    weight: 1,
    description: '',
  };
}

describe('computeDuoCoverageScore', () => {
  it('considere Arceus comme impossible a toucher en super efficace et super efficace contre tous les types', () => {
    const fightingPokemon = pokemon(68, 'Mackogneur', ['Combat']);
    const arceus = pokemon(493, 'Arceus', ['Normal']);

    expect(computeDuoCoverageScore([fightingPokemon], [arceus])).toBe(0);
    expect(computeDuoCoverageScore([arceus], [fightingPokemon])).toBe(10);
  });
});

describe('canUseRoomForDuoComplete', () => {
  it('refuse une room stale quand une des deux equipes a moins de 6 Pokemon', () => {
    expect(canUseRoomForDuoComplete({ p1_team: [1, 2, 3, 4, 5], p2_team: [6, 7, 8, 9, 10, 11] })).toBeFalse();
  });

  it('accepte uniquement quand les deux equipes ont 6 Pokemon', () => {
    expect(canUseRoomForDuoComplete({ p1_team: [1, 2, 3, 4, 5, 6], p2_team: [7, 8, 9, 10, 11, 12] })).toBeTrue();
  });
});

describe('validation du pool de draft', () => {
  it('refuse un pool qui ne contient pas six Pokemon distincts', () => {
    expect(hasEnoughPokemonForDraft([pokemon(1, 'A', []), pokemon(2, 'B', [])])).toBeFalse();
  });

  it('refuse explicitement de tirer dans un pool vide', () => {
    expect(() => pickOneStarter([], new Set())).toThrowError('Aucun Pokemon disponible pour ce draft');
  });
});
