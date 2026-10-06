import { Pokemon } from '../models/pokemon.model';
import { buildDraftSlots, canUseRoomForDuoComplete, computeDuoCoverageScore, computeFinalScore, explainDuoCoverage, computeStatsScore, hasEnoughPokemonForDraft, pickOneLegendary, pickOneStarter } from './draft-utils';

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
  const pikachu = pokemon(25, 'Pikachu', ['Électrik']);
  const salameche = pokemon(4, 'Salamèche', ['Feu']);
  const leviator = pokemon(130, 'Léviator', ['Eau', 'Vol']);
  const maraiste = pokemon(195, 'Maraiste', ['Eau', 'Sol']);
  const arceus = pokemon(493, 'Arceus', ['Normal']);

  it('ne compte pas un type couvert quand le double type annule la faiblesse', () => {
    // Électrik touche Eau, mais pas Maraiste (Eau/Sol) ; Pikachu est en plus faible au Sol.
    expect(computeDuoCoverageScore([pikachu], [maraiste])).toBe(0);
  });

  it('tient compte des résistances qui annulent une faiblesse de double type', () => {
    expect(computeDuoCoverageScore([salameche], [pokemon(230, 'Hyporoi', ['Eau', 'Dragon'])])).toBe(0);
    // ×1 en attaque (1 pt sur 2) et Pikachu n'est faible à aucun type d'Hyporoi.
    expect(computeDuoCoverageScore([pikachu], [pokemon(230, 'Hyporoi', ['Eau', 'Dragon'])])).toBe(5);
    // ×4 en attaque, pas de résistance aux deux types, pas de faiblesse.
    expect(computeDuoCoverageScore([pikachu], [leviator])).toBe(7.5);
  });

  it('pénalise les faiblesses partagées par plusieurs Pokémon', () => {
    const sorbebe = pokemon(582, 'Sorbébé', ['Glace']);
    const plantes = Array.from({ length: 5 }, (_, i) => pokemon(i + 1, `Plante${i}`, ['Plante']));
    const feux = Array.from({ length: 6 }, (_, i) => pokemon(i + 10, `Feu${i}`, ['Feu']));
    expect(computeDuoCoverageScore([...plantes, salameche], [sorbebe])).toBe(7.9);
    expect(computeDuoCoverageScore(feux, [sorbebe])).toBe(10);
  });

  it('compte chaque doublon adverse', () => {
    expect(computeDuoCoverageScore([pikachu], [leviator, maraiste])).toBe(3.8);
    expect(computeDuoCoverageScore([pikachu], [leviator, leviator, maraiste])).toBe(5);
  });

  it('garde Arceus comme joker : 10 dans son équipe, 0 sur son seul slot en face', () => {
    expect(computeDuoCoverageScore([pokemon(68, 'Mackogneur', ['Combat'])], [arceus])).toBe(0);
    expect(computeDuoCoverageScore([arceus], [pokemon(68, 'Mackogneur', ['Combat'])])).toBe(10);
    expect(computeDuoCoverageScore([pikachu], [leviator, arceus])).toBe(3.8);
  });
});

describe('explainDuoCoverage', () => {
  it('détaille l\'attaquant, la résistance et les Pokémon menacés', () => {
    const pikachu = pokemon(25, 'Pikachu', ['Électrik']);
    const tortank = pokemon(9, 'Tortank', ['Eau']);
    const arcanin = pokemon(59, 'Arcanin', ['Feu']);
    const detail = explainDuoCoverage([pikachu, tortank], [arcanin]);
    const [entry] = detail.entries;
    expect(entry.attacker).toBe(tortank);
    expect(entry.attackType).toBe('Eau');
    expect(entry.multiplier).toBe(2);
    expect(entry.attackPoints).toBe(2);
    expect(entry.resistor).toBe(tortank);
    expect(entry.weakMembers).toEqual([]);
    expect(entry.safeCount).toBe(2);
    expect([detail.attackScore, detail.resistScore, detail.safeScore, detail.score]).toEqual([10, 10, 10, 10]);
  });

  it('signale le joker Arceus sans détail par Pokémon', () => {
    const arceus = pokemon(493, 'Arceus', ['Normal']);
    const detail = explainDuoCoverage([arceus], [pokemon(25, 'Pikachu', ['Électrik'])]);
    expect(detail.joker).toBe(arceus);
    expect(detail.entries).toEqual([]);
    expect(detail.score).toBe(10);
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

  it('arrondit une moyenne à x,x5 vers le haut, comme le serveur (Team Builder solo)', () => {
    // La moyenne flottante vaut 6,9499… : l'ancien calcul affichait 6,9 (défaite) au lieu de 7,0.
    const team = [6.7, 8.2, 6.9, 5.9, 8.2, 5.8].map((rating, i) => ({ ...pokemon(i, `P${i}`, ['Normal']), rating }));
    expect(computeStatsScore(team, { min: 0, max: 1 })).toBe(7);
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

describe('tirage de remplacement du draft', () => {
  const withCategory = (id: number, category: Pokemon['category']): Pokemon => ({ ...pokemon(id, `P${id}`, ['Normal']), category });

  it('ne reprend pas un légendaire déjà présent quand tous ont été vus', () => {
    const legends = [withCategory(1, 'légendaire'), withCategory(2, 'fabuleux')];
    const others = [withCategory(3, 'classique'), withCategory(4, 'classique')];
    const pool = [...legends, ...others];
    const seen = new Set(pool.map(p => p.id));
    for (let i = 0; i < 50; i++) {
      const picked = pickOneLegendary(pool, seen, [legends[0], legends[1], others[0]]);
      expect(picked.id).toBe(4);
    }
  });

  it('privilégie un légendaire déjà vu mais absent du draft', () => {
    const legends = [withCategory(1, 'légendaire'), withCategory(2, 'légendaire')];
    const pool = [...legends, withCategory(3, 'classique')];
    const seen = new Set(pool.map(p => p.id));
    for (let i = 0; i < 50; i++) {
      expect(pickOneLegendary(pool, seen, [legends[0]]).id).toBe(2);
    }
  });

  it('sans starter dans le pool, ignore les Pokémon déjà présents', () => {
    const pool = [withCategory(1, 'classique'), withCategory(2, 'classique'), withCategory(3, 'classique')];
    expect(pickOneStarter(pool, new Set([1, 2, 3]), [pool[0]]).id).toBe(2);
    expect(pickOneStarter(pool, new Set([1]), [pool[0]]).id).toBe(2);
  });
});
