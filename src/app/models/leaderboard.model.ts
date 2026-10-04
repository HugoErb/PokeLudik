export type SoloLeaderboardMode = 'stat_duel' | 'who_that_pokemon' | 'draft' | 'draft_trainer';
export type LeaderboardPeriod = 'all' | 'week';

/** Paramètres normalisés d'une catégorie de classement. */
export interface LeaderboardSettings {
  generations?: number[];
  categories?: string[];
  initialHint?: string;
  trainer?: number;
}

export interface LeaderboardEntry {
  rank: number;
  user_id: string;
  username: string;
  avatar_url: string | null;
  score: number;
  achieved_at: string;
  is_me: boolean;
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

/** Catégorie spéciale du mode dresseur : nombre de dresseurs différents battus. */
export const TRAINERS_DEFEATED_KEY = 'trainers_defeated';
