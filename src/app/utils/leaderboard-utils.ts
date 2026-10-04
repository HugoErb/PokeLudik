import { CATEGORY_LABELS, INITIAL_HINT_LABELS } from '../constants/pokemon-categories';
import { LeaderboardSettings, SoloLeaderboardMode, TRAINERS_DEFEATED_KEY } from '../models/leaderboard.model';

export interface LeaderboardModeInfo {
  mode: SoloLeaderboardMode;
  label: string;
  shortLabel: string;
}

export const SOLO_LEADERBOARD_MODES: LeaderboardModeInfo[] = [
  { mode: 'stat_duel', label: 'Duel de Base Stats', shortLabel: 'Base Stats' },
  { mode: 'who_that_pokemon', label: "Who's That Pokémon", shortLabel: "Who's That" },
  { mode: 'draft', label: 'Team Builder', shortLabel: 'Team Builder' },
  { mode: 'draft_trainer', label: 'Contre un dresseur', shortLabel: 'Dresseurs' },
  { mode: 'size_up', label: 'Size It Up', shortLabel: 'Size It Up' },
];

/** Clé canonique d'une catégorie ; doit rester identique à public.solo_settings_key côté SQL. */
export function buildSettingsKey(mode: SoloLeaderboardMode, settings: LeaderboardSettings): string {
  if (mode === 'draft_trainer') {
    return settings.trainer === undefined ? TRAINERS_DEFEATED_KEY : `trainer:${settings.trainer}`;
  }
  const generations = [...new Set(settings.generations ?? [])].sort((a, b) => a - b);
  // Même tri que ORDER BY c en SQL (collation C : ordre des points de code).
  const categories = [...new Set(settings.categories ?? [])].sort(compareCodePoints);
  const key = `g=${generations.join(',')};c=${categories.join(',')}`;
  if (mode === 'who_that_pokemon') return `${key};h=${settings.initialHint ?? 'silhouette'}`;
  if (mode === 'size_up') return `${key};t=${settings.roundTimer ?? 0}`;
  return key;
}

/** Clé de la catégorie par défaut (aucun filtre). */
export function defaultSettingsKey(mode: SoloLeaderboardMode): string {
  return buildSettingsKey(mode, {});
}

/** Libellé lisible d'une catégorie de classement. */
export function formatCategoryLabel(
  mode: SoloLeaderboardMode,
  settingsKey: string,
  settings: LeaderboardSettings,
  trainerNames: string[] = [],
): string {
  if (mode === 'draft_trainer') {
    if (settingsKey === TRAINERS_DEFEATED_KEY) return 'Dresseurs battus';
    const index = settings.trainer ?? Number(settingsKey.replace('trainer:', ''));
    return trainerNames[index] ?? `Dresseur n°${index + 1}`;
  }

  const generations = settings.generations ?? [];
  const categories = settings.categories ?? [];
  const parts = [
    generations.length === 0 ? 'Toutes générations' : `Gén. ${generations.join(', ')}`,
    categories.length === 0 ? 'Toutes catégories' : categories.map(c => CATEGORY_LABELS[c] ?? c).join(', '),
  ];
  if (mode === 'who_that_pokemon') {
    const hint = settings.initialHint ?? 'silhouette';
    parts.push(`Indice : ${INITIAL_HINT_LABELS[hint] ?? hint}`);
  }
  if (mode === 'size_up') {
    const timer = settings.roundTimer ?? 0;
    parts.push(timer > 0 ? `Chrono ${timer} s` : 'Sans chrono');
  }
  return parts.join(' · ');
}

/** Affiche un score selon l'unité du mode. */
export function formatLeaderboardScore(mode: SoloLeaderboardMode, settingsKey: string, score: number): string {
  if (mode === 'draft_trainer' && settingsKey === TRAINERS_DEFEATED_KEY) {
    return `${score} battu${score > 1 ? 's' : ''}`;
  }
  if (mode === 'draft' || mode === 'draft_trainer') return `${score.toFixed(1)}/10`;
  if (mode === 'who_that_pokemon' || mode === 'size_up') return `${score} pts`;
  return `${score}`;
}

function compareCodePoints(a: string, b: string): number {
  if (a === b) return 0;
  return a < b ? -1 : 1;
}
