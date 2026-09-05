import { Pokemon } from '../models/pokemon.model';
import { buildDraftSlots, canUseRoomForDuoComplete, computeDuoCoverageScore, computeFinalScore, computeStatsScore, hasEnoughPokemonForDraft, pickOneStarter } from './draft-utils';

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
  it('ne compte pas un Pokémon immunisé comme exploitable', () => {
    const pikachu = pokemon(25, 'Pikachu', ['Électrik']);
    const maraiste = pokemon(195, 'Maraiste', ['Eau', 'Sol']);
    // La couverture du type Eau reste comptée (50% de deux types), pas le Pokémon (30%).
    expect(computeDuoCoverageScore([pikachu], [maraiste])).toBe(2.5);
  });

  it('tient compte des résistances qui annulent une faiblesse de double type', () => {
    expect(computeDuoCoverageScore([pokemon(4, 'Salamèche', ['Feu'])], [pokemon(230, 'Hyporoi', ['Eau', 'Dragon'])])).toBe(0);
    expect(computeDuoCoverageScore([pokemon(25, 'Pikachu', ['Électrik'])], [pokemon(230, 'Hyporoi', ['Eau', 'Dragon'])])).toBe(2.5);
    expect(computeDuoCoverageScore([pokemon(25, 'Pikachu', ['Électrik'])], [pokemon(130, 'Léviator', ['Eau', 'Vol'])])).toBe(9);
  });
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

describe('arrondi des scores', () => {
  it('arrondit une demi-décimale vers le haut comme PostgreSQL', () => {
    for (let stats = 0; stats <= 100; stats++) {
      for (let coverage = 0; coverage <= 100; coverage++) {
        expect(computeFinalScore(stats / 10, coverage / 10)).toBe(Math.round((stats + coverage) / 2) / 10);
      }
    }
  });

  it('calcule la moyenne de notes décimales sans perdre un dixième', () => {
    const team = [5.6, 6.8, 8.2, 5.5, 6.8, 8.2].map((rating, i) => ({ ...pokemon(i, `P${i}`, ['Normal']), rating }));
    expect(computeStatsScore(team, { min: 0, max: 1 })).toBe(6.9);
  });
});

describe('validation du pool de draft', () => {
  it('préserve les choix et six propositions distinctes même quand le pool est épuisé', () => {
    const pool = Array.from({ length: 6 }, (_, i) => pokemon(i + 1, `P${i}`, ['Normal']));
    const locked = [null, pool[0], null, null, null, null];
    const slots = buildDraftSlots(pool, locked, new Set(pool.map(p => p.id)));
    expect(slots[1]).toBe(pool[0]);
    expect(new Set(slots.map(p => p.id)).size).toBe(6);
  });
  it('refuse un pool qui ne contient pas six Pokemon distincts', () => {
    expect(hasEnoughPokemonForDraft([pokemon(1, 'A', []), pokemon(2, 'B', [])])).toBeFalse();
  });

  it('refuse explicitement de tirer dans un pool vide', () => {
    expect(() => pickOneStarter([], new Set())).toThrowError('Aucun Pokemon disponible pour ce draft');
  });
});
