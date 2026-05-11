import { Pokemon } from '../models/pokemon.model';
import {
  buildWhoPokemonPool,
  getWhoHintOrder,
  nextSoloState,
  pickWhoPokemonSequence,
  resolveDuoGuess,
  WHO_MAX_HINTS,
  WhoDuoRoundState,
  WhoSoloState,
} from './who-that-pokemon-utils';

const pokemon = (id: number, generation = 1, category: Pokemon['category'] = 'classique'): Pokemon => ({
  id,
  name: `pokemon-${id}`,
  types: ['normal'],
  generation,
  category,
  evolution_stage: '1/1',
  sprite: `${id}.png`,
  cry: `${id}.ogg`,
  stats: { pv: 1, attaque: 1, defense: 1, atq_spe: 1, def_spe: 1, vitesse: 1 },
  height: 1,
  weight: 1,
  description: `description-${id}`,
});

describe('who-that-pokemon-utils', () => {
  it('filtre le pool par generation et categorie', () => {
    const pool = [pokemon(1, 1), pokemon(2, 2, 'starter'), pokemon(3, 2, 'légendaire')];

    const result = buildWhoPokemonPool(pool, { generations: [2], categories: ['starter'] });

    expect(result.map(p => p.id)).toEqual([2]);
  });

  it('tire une sequence sans doublon quand le pool est suffisant', () => {
    const pool = Array.from({ length: 12 }, (_, index) => pokemon(index + 1));

    const result = pickWhoPokemonSequence(pool, 10);

    expect(result.length).toBe(10);
    expect(new Set(result.map(p => p.id)).size).toBe(10);
  });

  it('termine le solo apres 10 bonnes reponses', () => {
    let state: WhoSoloState = { roundIndex: 9, hintsRevealed: 0, score: 40, found: 9, status: 'playing' };

    state = nextSoloState(state, true);

    expect(state).toEqual({ roundIndex: 9, hintsRevealed: 0, score: 45, found: 10, status: 'won' });
  });

  it('revele un indice apres une mauvaise reponse solo', () => {
    const state = nextSoloState({ roundIndex: 0, hintsRevealed: 0, score: 0, found: 0, status: 'playing' }, false);

    expect(state).toEqual({ roundIndex: 0, hintsRevealed: 1, score: 0, found: 0, status: 'playing' });
  });

  it('passe au pokemon suivant sans point apres une mauvaise reponse avec 3 indices', () => {
    const state = nextSoloState({ roundIndex: 0, hintsRevealed: WHO_MAX_HINTS, score: 0, found: 0, status: 'playing' }, false);

    expect(state).toEqual({ roundIndex: 1, hintsRevealed: 0, score: 0, found: 0, status: 'playing' });
  });

  it('donne 5 points moins les indices reveles en solo', () => {
    const state = nextSoloState({ roundIndex: 0, hintsRevealed: 2, score: 4, found: 0, status: 'playing' }, true);

    expect(state).toEqual({ roundIndex: 1, hintsRevealed: 0, score: 7, found: 1, status: 'playing' });
  });

  it('ne repropose pas le premier indice dans les indices aleatoires', () => {
    const result = getWhoHintOrder(25, 'cry');

    expect(result).not.toContain('cry');
    expect(result).toContain('silhouette');
  });

  it('bloque un joueur duo a 0 vie apres une mauvaise reponse', () => {
    const state: WhoDuoRoundState = {
      round: 1,
      targetPokemonId: 25,
      p1Score: 0,
      p2Score: 0,
      p1Lives: 2,
      p2Lives: 0,
      status: 'playing',
    };

    const result = resolveDuoGuess(state, 'player1', 1);

    expect(result.p1Lives).toBe(3);
    expect(result.status).toBe('playing');
  });

  it('passe a la manche suivante sans point apres une mauvaise reponse avec 3 indices en duo', () => {
    const state: WhoDuoRoundState = {
      round: 1,
      targetPokemonId: 25,
      p1Score: 0,
      p2Score: 0,
      p1Lives: 0,
      p2Lives: 3,
      status: 'playing',
    };

    const result = resolveDuoGuess(state, 'player2', 1);

    expect(result.round).toBe(2);
    expect(result.p1Score).toBe(0);
    expect(result.p2Score).toBe(0);
    expect(result.p1Lives).toBe(0);
    expect(result.p2Lives).toBe(0);
  });

  it('donne 5 points moins les indices reveles au premier joueur qui trouve en duo', () => {
    const state: WhoDuoRoundState = {
      round: 1,
      targetPokemonId: 25,
      p1Score: 0,
      p2Score: 0,
      p1Lives: 0,
      p2Lives: 2,
      status: 'playing',
    };

    const result = resolveDuoGuess(state, 'player2', 25);

    expect(result.round).toBe(2);
    expect(result.p2Score).toBe(3);
    expect(result.p1Lives).toBe(0);
    expect(result.p2Lives).toBe(0);
  });
});
