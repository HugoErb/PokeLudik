export type SoloLeaderboardMode = 'stat_duel' | 'who_that_pokemon' | 'draft' | 'draft_trainer' | 'size_up';
export type LeaderboardPeriod = 'all' | 'week';
export type LeaderboardView = 'global' | 'personal';

/** Paramètres normalisés d'une catégorie de classement. */
export interface LeaderboardSettings {
  generations?: number[];
  categories?: string[];
  initialHint?: string;
  trainer?: number;
  /** Size Up : chrono par manche en secondes (0 = sans limite). */
  roundTimer?: number;
}

export interface LeaderboardEntry {
  rank: number;
  user_id: string;
  username: string;
  avatar_url: string | null;
  score: number;
  achieved_at: string;
  is_me: boolean;
  /** Équipe de la meilleure partie (Team Builder et dresseurs). */
  team: number[] | null;
}

/** Partie du joueur connecté dans l'onglet « Classement personnel ». */
export interface PersonalScoreEntry {
  score: number;
  achieved_at: string;
  won: boolean;
  team: number[] | null;
  settings_key: string;
}

export interface PersonalLeaderboard {
  games: number;
  best: number | null;
  average: number | null;
  /** Rang dans le classement global de la catégorie, null sans partie. */
  rank: number | null;
  entries: PersonalScoreEntry[];
}

export interface LeaderboardCategory {
  settings_key: string;
  settings: LeaderboardSettings;
  players: number;
}

/** Résultat renvoyé après l'enregistrement d'une partie solo. */
export interface SoloScoreResult {
  score: number;
  won: boolean;
  settings_key: string;
  previous_best: number | null;
  is_record: boolean;
  rank_all_time: number;
  rank_week: number;
}

export interface StatDuelScorePick {
  pokemon_id: number;
  stat: string;
}

/** Manche d'une partie Size Up envoyée au serveur, qui recalcule les points. */
export interface SizeUpScoreRound {
  reference_id: number;
  target_id: number;
  guess: number | null;
}

/** Catégorie spéciale du mode dresseur : nombre de dresseurs différents battus. */
export const TRAINERS_DEFEATED_KEY = 'trainers_defeated';
