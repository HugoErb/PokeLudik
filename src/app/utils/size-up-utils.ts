import { Pokemon } from '../models/pokemon.model';

/** Paire d'une manche : le Pokémon de référence est affiché à l'échelle, la cible est à estimer. */
export interface SizeUpPair {
  referenceId: number;
  targetId: number;
}

/** Résultat d'une manche (solo et historique duo). */
export interface SizeUpRoundResult extends SizeUpPair {
  guess: number | null;
  points: number;
}

export const SIZE_UP_TOTAL_ROUNDS = 5;
export const SIZE_UP_MAX_ROUND_POINTS = 100;
export const SIZE_UP_TIMER_OPTIONS = [0, 15, 30, 60] as const;
export const SIZE_UP_MIN_M = 0.05;
export const SIZE_UP_MAX_M = 30;
/** Écart (en facteur) à partir duquel une estimation ne rapporte plus rien. */
export const SIZE_UP_ZERO_FACTOR = 5;
/** Résolution du slider logarithmique. */
export const SIZE_UP_SLIDER_STEPS = 1000;

/**
 * Points d'une estimation : 100 pour une estimation exacte, 0 à partir d'un facteur 5.
 * L'écart est symétrique (×2 et ÷2 rapportent autant). Doit rester identique à public.size_up_points côté SQL.
 */
export function sizeUpPoints(guess: number | null, actual: number): number {
  if (guess === null || !(guess > 0) || !(actual > 0)) return 0;
  const error = Math.abs(Math.log(guess / actual)) / Math.log(SIZE_UP_ZERO_FACTOR);
  return Math.round(SIZE_UP_MAX_ROUND_POINTS * Math.max(0, 1 - error));
}

/** Facteur d'écart lisible (toujours ≥ 1) entre une estimation et la taille réelle. */
export function sizeUpErrorFactor(guess: number, actual: number): number {
  return Math.max(guess, actual) / Math.min(guess, actual);
}

export function clampSizeUpGuess(meters: number): number {
  if (!Number.isFinite(meters)) return 1;
  return Math.min(SIZE_UP_MAX_M, Math.max(SIZE_UP_MIN_M, meters));
}

/** Arrondit au centimètre entier : l'estimation ne doit pas contenir de décimales invisibles à l'affichage. */
export function roundToCm(meters: number): number {
  return Math.round(meters * 100) / 100;
}

/** Position du slider (0 → SIZE_UP_SLIDER_STEPS) vers une taille en mètres, sur une échelle logarithmique. */
export function sliderToMeters(position: number): number {
  const ratio = Math.min(1, Math.max(0, position / SIZE_UP_SLIDER_STEPS));
  const min = Math.log(SIZE_UP_MIN_M);
  const max = Math.log(SIZE_UP_MAX_M);
  return Math.exp(min + ratio * (max - min));
}

export function metersToSlider(meters: number): number {
  const min = Math.log(SIZE_UP_MIN_M);
  const max = Math.log(SIZE_UP_MAX_M);
  return Math.round(((Math.log(clampSizeUpGuess(meters)) - min) / (max - min)) * SIZE_UP_SLIDER_STEPS);
}

/** Pixels par mètre pour que le plus grand des deux Pokémon affichés occupe `fill` de la hauteur du plateau. */
export function computeBoardScale(boardHeightPx: number, referenceMeters: number, ...otherMeters: number[]): number {
  const tallest = Math.max(referenceMeters, ...otherMeters.filter(value => value > 0));
  if (!(tallest > 0) || !(boardHeightPx > 0)) return 0;
  return (boardHeightPx * 0.78) / tallest;
}

export function formatMeters(meters: number | null | undefined): string {
  if (meters === null || meters === undefined || !Number.isFinite(meters)) return '—';
  if (meters < 1) return `${Math.round(meters * 100)} cm`;
  return `${meters.toFixed(2).replace(/\.?0+$/, '').replace('.', ',')} m`;
}

/** Tire `rounds` paires de deux Pokémon distincts, sans réutiliser un Pokémon tant que le pool le permet. */
export function pickSizeUpPairs(pool: Pokemon[], rounds: number, random: () => number = Math.random): SizeUpPair[] {
  const usable = pool.filter(pokemon => pokemon.height > 0);
  if (usable.length < 2) return [];

  const pairs: SizeUpPair[] = [];
  let bag: Pokemon[] = [];
  const draw = (exclude: number | null): Pokemon => {
    if (bag.length === 0 || (bag.length === 1 && bag[0].id === exclude)) bag = shuffle(usable, random);
    const index = bag.findIndex(pokemon => pokemon.id !== exclude);
    return bag.splice(index, 1)[0];
  };

  for (let round = 0; round < rounds; round++) {
    const reference = draw(null);
    const target = draw(reference.id);
    pairs.push({ referenceId: reference.id, targetId: target.id });
  }
  return pairs;
}

function shuffle<T>(items: T[], random: () => number): T[] {
  const copy = [...items];
  for (let index = copy.length - 1; index > 0; index--) {
    const swapIndex = Math.floor(random() * (index + 1));
    [copy[index], copy[swapIndex]] = [copy[swapIndex], copy[index]];
  }
  return copy;
}
