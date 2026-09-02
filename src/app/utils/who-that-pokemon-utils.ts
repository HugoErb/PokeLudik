import { Pokemon } from '../models/pokemon.model';

export type WhoHintMode = 'silhouette' | 'cry' | 'pokedex_number' | 'description' | 'first_letter';
export type WhoInitialHintMode = Exclude<WhoHintMode, 'first_letter'>;
export type WhoInitialHintSetting = WhoInitialHintMode | 'random';
export type WhoRevealedHint = WhoHintMode;

export interface WhoGameSettings {
  generations: number[];
  categories: string[];
  initialHint: WhoInitialHintSetting;
}

export interface WhoSoloState {
  roundIndex: number;
  hintsRevealed: number;
  score: number;
  found: number;
  status: 'playing' | 'won' | 'lost';
}

export interface WhoDuoRoundState {
  round: number;
  targetPokemonId: number;
  p1Score: number;
  p2Score: number;
  p1Lives: number;
  p2Lives: number;
  status: 'playing' | 'finished';
}

export const WHO_TOTAL_ROUNDS = 10;
export const WHO_MAX_HINTS = 3;
export const WHO_BASE_SCORE = 5;
export const WHO_HINT_MODES: WhoRevealedHint[] = ['silhouette', 'cry', 'pokedex_number', 'description', 'first_letter'];

export function buildWhoPokemonPool(pokemons: Pokemon[], settings: Pick<WhoGameSettings, 'generations' | 'categories'>): Pokemon[] {
  return pokemons.filter((pokemon) => {
    if (settings.generations.length > 0 && !settings.generations.includes(pokemon.generation)) return false;
    if (settings.categories.length > 0 && !settings.categories.includes(pokemon.category)) return false;
    return true;
  });
}

export function pickWhoPokemonSequence(pool: Pokemon[], count: number): Pokemon[] {
  const shuffled = [...pool].sort(() => Math.random() - 0.5);
  if (shuffled.length >= count) return shuffled.slice(0, count);

  const result: Pokemon[] = [];
  while (result.length < count && shuffled.length > 0) {
    result.push(shuffled[result.length % shuffled.length]);
  }
  return result;
}

export function nextSoloState(state: WhoSoloState, isCorrect: boolean): WhoSoloState {
  if (state.status !== 'playing') return state;
  if (isCorrect) {
    const found = state.found + 1;
    const isLastRound = state.roundIndex >= WHO_TOTAL_ROUNDS - 1;
    return {
      roundIndex: Math.min(state.roundIndex + 1, WHO_TOTAL_ROUNDS - 1),
      hintsRevealed: 0,
      score: state.score + Math.max(0, WHO_BASE_SCORE - state.hintsRevealed),
      found,
      status: isLastRound ? (found >= WHO_TOTAL_ROUNDS ? 'won' : 'lost') : 'playing',
    };
  }

  if (state.hintsRevealed < WHO_MAX_HINTS) {
    return {
      ...state,
      hintsRevealed: state.hintsRevealed + 1,
    };
  }

  const nextRoundIndex = state.roundIndex + 1;
  return {
    ...state,
    roundIndex: Math.min(nextRoundIndex, WHO_TOTAL_ROUNDS - 1),
    hintsRevealed: 0,
    status: nextRoundIndex >= WHO_TOTAL_ROUNDS ? 'lost' : 'playing',
  };
}

export function resolveDuoGuess(
  state: WhoDuoRoundState,
  player: 'player1' | 'player2',
  pokemonId: number,
): WhoDuoRoundState {
  if (state.status !== 'playing') return state;
  const playerLives = player === 'player1' ? state.p1Lives : state.p2Lives;
  if (pokemonId === state.targetPokemonId) {
    const score = Math.max(0, WHO_BASE_SCORE - playerLives);
    return advanceDuoRound({
      ...state,
      p1Score: state.p1Score + (player === 'player1' ? score : 0),
      p2Score: state.p2Score + (player === 'player2' ? score : 0),
    });
  }

  if (playerLives >= WHO_MAX_HINTS) return advanceDuoRound(state);

  const next = {
    ...state,
    p1Lives: player === 'player1' ? state.p1Lives + 1 : state.p1Lives,
    p2Lives: player === 'player2' ? state.p2Lives + 1 : state.p2Lives,
  };

  return next;
}

function advanceDuoRound(state: WhoDuoRoundState): WhoDuoRoundState {
  const round = state.round + 1;
  return {
    ...state,
    round,
    p1Lives: 0,
    p2Lives: 0,
    status: round > WHO_TOTAL_ROUNDS ? 'finished' : 'playing',
  };
}

export function resolveWhoInitialHint(seed: number, initialHint: WhoInitialHintSetting = 'silhouette'): WhoInitialHintMode {
  if (initialHint !== 'random') return initialHint;
  const playableHints: WhoInitialHintMode[] = ['silhouette', 'cry', 'pokedex_number', 'description'];
  return playableHints[Math.abs(seed || 1) % playableHints.length];
}

export function getWhoHintOrder(seed: number, initialHint: WhoInitialHintSetting = 'silhouette'): WhoRevealedHint[] {
  const resolvedInitialHint = resolveWhoInitialHint(seed, initialHint);
  const hints = WHO_HINT_MODES.filter(hint => hint !== resolvedInitialHint);
  let value = seed || 1;
  for (let index = hints.length - 1; index > 0; index--) {
    value = (value * 9301 + 49297) % 233280;
    const swapIndex = value % (index + 1);
    [hints[index], hints[swapIndex]] = [hints[swapIndex], hints[index]];
  }
  return hints;
}
