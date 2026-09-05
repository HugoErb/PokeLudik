import { Pokemon } from '../models/pokemon.model';
import { TYPE_OFFENSIVE, effectiveMultiplier } from '../constants/type-chart';

const ARCEUS_ID = 493;

export interface RatingRange {
  min: number;
  max: number;
}

export interface DraftDuoTeams {
  p1_team: number[];
  p2_team: number[];
}

export const DRAFT_TEAM_SIZE = 6;

/** Indique si le pool permet de proposer six Pokemon distincts. */
export function hasEnoughPokemonForDraft(pool: Pokemon[]): boolean {
  return new Set(pool.map(pokemon => pokemon.id)).size >= DRAFT_TEAM_SIZE;
}

/** Indique si une room contient les deux equipes completes du mode duo. */
export function canUseRoomForDuoComplete(room: DraftDuoTeams): boolean {
  return room.p1_team.length === 6 && room.p2_team.length === 6;
}

/** Calcule le total des statistiques d'un Pokemon. */
export function computeTotal(pokemon: Pokemon): number {
  const stats = pokemon.stats;
  return stats.pv + stats.attaque + stats.defense + stats.atq_spe + stats.def_spe + stats.vitesse;
}

/** Calcule la note d'un Pokemon sur la plage donnee. */
export function computeRating(pokemon: Pokemon, range: RatingRange): number {
  if (pokemon.rating !== undefined) return pokemon.rating;
  const raw = ((computeTotal(pokemon) - range.min) / (range.max - range.min)) * 10;
  return Math.round(raw * 10) / 10;
}

/** Calcule le score moyen de statistiques d'une equipe. */
export function computeStatsScore(team: Pokemon[], range: RatingRange): number {
  if (team.length === 0) return 0;
  const ratings = team.map(pokemon => computeRating(pokemon, range));
  return Math.round(ratings.reduce((sum, rating) => sum + Math.round(rating * 10), 0) / ratings.length) / 10;
}

/** Moyenne de deux notes au dixième, sans erreur d'arrondi binaire à x,x5. */
export function computeFinalScore(stats: number, coverage: number): number {
  return Math.round((Math.round(stats * 10) + Math.round(coverage * 10)) / 2) / 10;
}

/** Calcule le score de couverture offensive et defensive d'une equipe contre une autre. */
export function computeDuoCoverageScore(myTeam: Pokemon[], opponentTeam: Pokemon[]): number {
  if (myTeam.length === 0 || opponentTeam.length === 0) return 0;

  const hasArceus = myTeam.some(pokemon => pokemon.id === ARCEUS_ID);
  if (hasArceus) return 10;

  const myTypes = new Set(myTeam.flatMap(pokemon => pokemon.types));
  const opponentHasArceus = opponentTeam.some(pokemon => pokemon.id === ARCEUS_ID);
  const standardOpponentTeam = opponentTeam.filter(pokemon => pokemon.id !== ARCEUS_ID);
  const opponentTypes = new Set(standardOpponentTeam.flatMap(pokemon => pokemon.types));
  const myTypeList = [...myTypes];

  let coveredOpponentTypes = 0;
  for (const opponentType of opponentTypes) {
    if (myTypeList.some(myType => (TYPE_OFFENSIVE[myType] ?? []).includes(opponentType))) {
      coveredOpponentTypes++;
    }
  }

  let exploitedPokemon = 0;
  for (const opponentPokemon of opponentTeam) {
    if (opponentPokemon.id === ARCEUS_ID) continue;

    const canHit = myTypeList.some(myType =>
      effectiveMultiplier(opponentPokemon.types, myType) > 1
    );
    if (canHit) exploitedPokemon++;
  }

  let resistedTypes = 0;
  if (!opponentHasArceus) {
    for (const opponentType of opponentTypes) {
      if (myTeam.some(pokemon => effectiveMultiplier(pokemon.types, opponentType) < 1)) {
        resistedTypes++;
      }
    }
  }
  // Mettre les fractions au même dénominateur avant l'arrondi, comme le SQL numeric.
  const typeCount = Math.max(1, opponentTypes.size);
  const numerator = (50 * coveredOpponentTypes + 20 * resistedTypes) * opponentTeam.length
    + 30 * exploitedPokemon * typeCount;
  return Math.round(numerator / (typeCount * opponentTeam.length)) / 10;
}

/** Retourne la classe CSS de couleur associee a un score. */
export function getScoreColor(score: number): string {
  if (score >= 8) return 'text-yellow-400';
  if (score >= 6) return 'text-green-400';
  if (score >= 4) return 'text-blue-400';
  return 'text-slate-400';
}

/** Retourne la classe CSS de barre associee a un score. */
export function getScoreBarColor(score: number): string {
  if (score >= 8) return 'bg-yellow-400';
  if (score >= 6) return 'bg-green-400';
  if (score >= 4) return 'bg-blue-400';
  return 'bg-slate-500';
}

/** Retourne la largeur CSS correspondant a une note. */
export function getRatingWidth(rating: number): string {
  return `${(rating / 10) * 100}%`;
}

/** Selectionne un starter disponible dans le pool. */
export function pickOneStarter(pool: Pokemon[], exclude: Set<number>, currentSlots: (Pokemon | null)[] = []): Pokemon {
  if (pool.length === 0) throw new Error('Aucun Pokemon disponible pour ce draft');
  const starters = pool.filter(pokemon => pokemon.category === 'starter');
  if (starters.length === 0) {
    const fallback = pool.filter(pokemon => !exclude.has(pokemon.id));
    return (fallback.length > 0 ? fallback : pool)[0];
  }

  const available = starters.filter(pokemon => !exclude.has(pokemon.id));
  if (available.length > 0) {
    return available[Math.floor(Math.random() * available.length)];
  }

  const currentIds = new Set(currentSlots.filter((pokemon): pokemon is Pokemon => pokemon !== null).map(pokemon => pokemon.id));
  const secondary = starters.filter(pokemon => !currentIds.has(pokemon.id));
  const finalSource = secondary.length > 0 ? secondary : starters;
  return finalSource[Math.floor(Math.random() * finalSource.length)];
}

/** Selectionne un Pokemon legendaire ou fabuleux disponible dans le pool. */
export function pickOneLegendary(pool: Pokemon[], exclude: Set<number>, currentSlots: (Pokemon | null)[] = []): Pokemon {
  if (pool.length === 0) throw new Error('Aucun Pokemon disponible pour ce draft');
  const legends = pool.filter(pokemon => pokemon.category === 'l\u00e9gendaire' || pokemon.category === 'fabuleux');
  if (legends.length === 0) {
    const fallback = pool.filter(pokemon => !exclude.has(pokemon.id));
    return (fallback.length > 0 ? fallback : pool)[0];
  }

  const available = legends.filter(pokemon => !exclude.has(pokemon.id));
  if (available.length > 0) {
    return available[Math.floor(Math.random() * available.length)];
  }

  const currentIds = new Set(currentSlots.filter((pokemon): pokemon is Pokemon => pokemon !== null).map(pokemon => pokemon.id));
  const secondary = legends.filter(pokemon => !currentIds.has(pokemon.id));
  const finalSource = secondary.length > 0 ? secondary : legends;
  return finalSource[Math.floor(Math.random() * finalSource.length)];
}

/** Selectionne plusieurs Pokemon uniques dans le pool. */
export function pickNUnique(pool: Pokemon[], exclude: Set<number>, count: number): Pokemon[] {
  const available = pool.filter(pokemon => !exclude.has(pokemon.id));
  for (let i = available.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [available[i], available[j]] = [available[j], available[i]];
  }
  return available.slice(0, count);
}

/** Remplit les places libres sans réintroduire un Pokémon déjà verrouillé. */
export function buildDraftSlots(pool: Pokemon[], locked: (Pokemon | null)[], usedIds = new Set<number>()): Pokemon[] {
  if (!hasEnoughPokemonForDraft(pool)) throw new Error('Au moins six Pokémon distincts sont nécessaires');
  const slots = [...locked];
  const reserved = new Set(locked.filter((p): p is Pokemon => p !== null).map(p => p.id));
  // Réserver les catégories spéciales avant de remplir les places ordinaires.
  for (const index of [0, 5, 1, 2, 3, 4]) {
    if (slots[index]) continue;
    const available = pool.filter(p => !reserved.has(p.id));
    const preferred = available.filter(p => index === 0 ? p.category === 'starter'
      : index === 5 ? ['légendaire', 'fabuleux'].includes(p.category) : true);
    const source = preferred.length ? preferred : available;
    const unseen = source.filter(p => !usedIds.has(p.id));
    const choices = unseen.length ? unseen : source;
    const picked = choices[Math.floor(Math.random() * choices.length)];
    slots[index] = picked;
    reserved.add(picked.id);
  }
  return slots as Pokemon[];
}

/** Precharge les images donnees. */
export function preloadImages(urls: string[]): Promise<void[]> {
  return Promise.all(
    urls.map(url => new Promise<void>(resolve => {
      const img = new Image();
      img.onload = () => resolve();
      img.onerror = () => resolve();
      img.src = url;
    }))
  );
}
