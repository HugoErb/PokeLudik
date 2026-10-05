import { Pokemon } from '../models/pokemon.model';
import {
  computeBoardScale,
  formatMeters,
  metersToSlider,
  pickSizeUpPairs,
  roundToCm,
  SIZE_UP_MAX_M,
  SIZE_UP_MIN_M,
  SIZE_UP_SLIDER_STEPS,
  sizeUpErrorFactor,
  sizeUpPoints,
  sliderToMeters,
} from './size-up-utils';

const pokemon = (id: number, height = 1): Pokemon => ({
  id,
  name: `pokemon-${id}`,
  types: ['normal'],
  generation: 1,
  category: 'classique',
  evolution_stage: '1/1',
  sprite: `${id}.png`,
  stats: { pv: 1, attaque: 1, defense: 1, atq_spe: 1, def_spe: 1, vitesse: 1 },
  height,
  weight: 1,
  description: '',
});

describe('size-up-utils', () => {
  it('attribue les points selon un écart symétrique', () => {
    expect(sizeUpPoints(1.2, 1.2)).toBe(100);
    expect(sizeUpPoints(1.1, 1)).toBe(94);
    expect(sizeUpPoints(1.5, 1)).toBe(75);
    expect(sizeUpPoints(2, 1)).toBe(57);
    expect(sizeUpPoints(0.5, 1)).toBe(57);
    expect(sizeUpPoints(3, 1)).toBe(32);
    expect(sizeUpPoints(5, 1)).toBe(0);
    expect(sizeUpPoints(0.1, 1)).toBe(0);
  });

  it('ne donne aucun point sans estimation', () => {
    expect(sizeUpPoints(null, 1)).toBe(0);
    expect(sizeUpPoints(0, 1)).toBe(0);
  });

  it('calcule le facteur d’écart', () => {
    expect(sizeUpErrorFactor(2, 1)).toBe(2);
    expect(sizeUpErrorFactor(1, 2)).toBe(2);
  });

  it('convertit le slider en mètres sur une échelle logarithmique', () => {
    expect(sliderToMeters(0)).toBeCloseTo(SIZE_UP_MIN_M, 5);
    expect(sliderToMeters(SIZE_UP_SLIDER_STEPS)).toBeCloseTo(SIZE_UP_MAX_M, 5);
    expect(sliderToMeters(metersToSlider(1.7))).toBeCloseTo(1.7, 1);
    expect(metersToSlider(1000)).toBe(SIZE_UP_SLIDER_STEPS);
  });

  it('cale l’échelle sur le plus grand Pokémon affiché', () => {
    expect(computeBoardScale(100, 1, 2)).toBeCloseTo(39, 5);
    expect(computeBoardScale(100, 4, 2)).toBeCloseTo(19.5, 5);
  });

  it('formate les tailles en centimètres ou en mètres', () => {
    expect(formatMeters(0.4)).toBe('40 cm');
    expect(formatMeters(1.5)).toBe('1,5 m');
    expect(formatMeters(14.5)).toBe('14,5 m');
    expect(formatMeters(2)).toBe('2 m');
    expect(formatMeters(14.53)).toBe('14,53 m');
    expect(formatMeters(20)).toBe('20 m');
  });

  it('arrondit les estimations au centimètre entier', () => {
    expect(roundToCm(0.403)).toBe(0.4);
    expect(roundToCm(1.236)).toBe(1.24);
    expect(roundToCm(14.534)).toBe(14.53);
    expect(sizeUpPoints(roundToCm(0.104), 0.1)).toBe(100);
  });

  it('tire des paires de Pokémon distincts sans répétition tant que le pool suffit', () => {
    const pool = Array.from({ length: 10 }, (_, index) => pokemon(index + 1));
    const pairs = pickSizeUpPairs(pool, 5);
    const ids = pairs.flatMap(pair => [pair.referenceId, pair.targetId]);

    expect(pairs.length).toBe(5);
    expect(new Set(ids).size).toBe(10);
  });

  it('réutilise le pool quand il est trop petit, sans paire identique', () => {
    const pairs = pickSizeUpPairs([pokemon(1), pokemon(2), pokemon(3)], 5);

    expect(pairs.length).toBe(5);
    pairs.forEach(pair => expect(pair.referenceId).not.toBe(pair.targetId));
  });

  it('refuse un pool de moins de deux Pokémon', () => {
    expect(pickSizeUpPairs([pokemon(1)], 5)).toEqual([]);
  });
});
