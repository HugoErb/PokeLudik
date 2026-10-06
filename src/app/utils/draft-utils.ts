import { Pokemon } from '../models/pokemon.model';
import { effectiveMultiplier } from '../constants/type-chart';

export const ARCEUS_ID = 493;

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

/** Détail de la couverture face à un Pokémon adverse. */
export interface CoverageEntry {
  opponent: Pokemon;
  isArceus: boolean;
  /** 2 si super efficace, 1 si neutre, 0 si résisté. */
  attackPoints: number;
  /** Meilleur multiplicateur obtenu par un type de l'équipe. */
  multiplier: number;
  /** Premier Pokémon de l'équipe qui atteint ce multiplicateur, avec le type utilisé. */
  attacker: Pokemon | null;
  attackType: string | null;
  /** Premier Pokémon de l'équipe qui résiste à tous les types de l'adversaire. */
  resistor: Pokemon | null;
  /** Pokémon de l'équipe faibles à au moins un type de l'adversaire. */
  weakMembers: Pokemon[];
  /** Nombre de Pokémon de l'équipe qui ne sont faibles à aucun type de l'adversaire. */
  safeCount: number;
}

/** Détail complet du calcul de couverture, affiché dans l'info-bulle des résultats. */
export interface CoverageBreakdown {
  /** Arceus dans l'équipe : couverture maximale d'office. */
  joker: Pokemon | null;
  teamSize: number;
  opponentCount: number;
  entries: CoverageEntry[];
  attackPoints: number;
  resistPoints: number;
  safePoints: number;
  /** Sous-notes sur 10, pour l'affichage uniquement. */
  attackScore: number;
  resistScore: number;
  safeScore: number;
  score: number;
}

const roundTenth = (value: number): number => Math.round(value * 10) / 10;

/**
 * Évalue la couverture d'une équipe contre une autre, Pokémon adverse par Pokémon adverse
 * (doublons compris) : attaque 50 %, résistance 25 %, faiblesses partagées 25 %.
 */
export function explainDuoCoverage(myTeam: Pokemon[], opponentTeam: Pokemon[]): CoverageBreakdown {
  const teamSize = myTeam.length;
  const opponentCount = opponentTeam.length;
  const joker = myTeam.find(pokemon => pokemon.id === ARCEUS_ID) ?? null;
  const empty: CoverageBreakdown = {
    joker, teamSize, opponentCount, entries: [], attackPoints: 0, resistPoints: 0, safePoints: 0,
    attackScore: 0, resistScore: 0, safeScore: 0, score: 0,
  };
  if (teamSize === 0 || opponentCount === 0) return empty;
  if (joker) return { ...empty, attackScore: 10, resistScore: 10, safeScore: 10, score: 10 };

  const entries = opponentTeam.map((opponent): CoverageEntry => {
    if (opponent.id === ARCEUS_ID) {
      // Arceus adverse change de type : impossible à exploiter, personne ne lui résiste.
      return { opponent, isArceus: true, attackPoints: 0, multiplier: 0, attacker: null, attackType: null,
        resistor: null, weakMembers: [...myTeam], safeCount: 0 };
    }

    let multiplier = -1;
    let attacker: Pokemon | null = null;
    let attackType: string | null = null;
    for (const member of myTeam) {
      for (const type of member.types) {
        const value = effectiveMultiplier(opponent.types, type);
        if (value > multiplier) {
          multiplier = value;
          attacker = member;
          attackType = type;
        }
      }
    }
    const attackPoints = multiplier > 1 ? 2 : multiplier === 1 ? 1 : 0;
    const resistor = myTeam.find(member =>
      opponent.types.every(type => effectiveMultiplier(member.types, type) < 1)) ?? null;
    const weakMembers = myTeam.filter(member =>
      opponent.types.some(type => effectiveMultiplier(member.types, type) > 1));

    return { opponent, isArceus: false, attackPoints, multiplier: Math.max(0, multiplier), attacker, attackType,
      resistor, weakMembers, safeCount: teamSize - weakMembers.length };
  });

  const attackPoints = entries.reduce((sum, entry) => sum + entry.attackPoints, 0);
  const resistPoints = entries.filter(entry => entry.resistor).length;
  const safePoints = entries.reduce((sum, entry) => sum + entry.safeCount, 0);
  // Tout ramener à un seul dénominateur entier avant l'arrondi, comme le SQL numeric.
  const numerator = 25 * (attackPoints * teamSize + resistPoints * teamSize + safePoints);
  return {
    joker, teamSize, opponentCount, entries, attackPoints, resistPoints, safePoints,
    attackScore: roundTenth(attackPoints * 5 / opponentCount),
    resistScore: roundTenth(resistPoints * 10 / opponentCount),
    safeScore: roundTenth(safePoints * 10 / (opponentCount * teamSize)),
    score: Math.round(numerator / (opponentCount * teamSize)) / 10,
  };
}

/** Calcule le score de couverture offensive et defensive d'une equipe contre une autre. */
export function computeDuoCoverageScore(myTeam: Pokemon[], opponentTeam: Pokemon[]): number {
  return explainDuoCoverage(myTeam, opponentTeam).score;
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
  return pickOneOfCategory(pool, pokemon => pokemon.category === 'starter', exclude, currentSlots);
}

/** Selectionne un Pokemon legendaire ou fabuleux disponible dans le pool. */
export function pickOneLegendary(pool: Pokemon[], exclude: Set<number>, currentSlots: (Pokemon | null)[] = []): Pokemon {
  return pickOneOfCategory(pool, pokemon => pokemon.category === 'légendaire' || pokemon.category === 'fabuleux', exclude, currentSlots);
}

/**
 * Tire un Pokemon de la categorie demandee, en evitant d'abord ceux deja vus (`exclude`),
 * puis, quand le pool est epuise, ceux deja presents dans le draft (`currentSlots`) : un doublon
 * avec un Pokemon verrouille rendrait l'equipe invalide.
 */
function pickOneOfCategory(pool: Pokemon[], inCategory: (pokemon: Pokemon) => boolean, exclude: Set<number>, currentSlots: (Pokemon | null)[]): Pokemon {
  if (pool.length === 0) throw new Error('Aucun Pokemon disponible pour ce draft');
  const currentIds = new Set(currentSlots.filter((pokemon): pokemon is Pokemon => pokemon !== null).map(pokemon => pokemon.id));
  const notPresent = pool.filter(pokemon => !currentIds.has(pokemon.id));
  const category = pool.filter(inCategory);
  if (category.length === 0) {
    const fallback = notPresent.filter(pokemon => !exclude.has(pokemon.id));
    return (fallback.length > 0 ? fallback : notPresent.length > 0 ? notPresent : pool)[0];
  }

  const available = category.filter(pokemon => !exclude.has(pokemon.id));
  if (available.length > 0) {
    return available[Math.floor(Math.random() * available.length)];
  }

  const secondary = category.filter(pokemon => !currentIds.has(pokemon.id));
  const finalSource = secondary.length > 0 ? secondary : notPresent.length > 0 ? notPresent : category;
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
