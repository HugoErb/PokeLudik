import type { GameMode } from './room.model';
import type { AuctionFormat, AuctionGameSettings } from './room.model';

export type SettingsMode = GameMode | 'draft_trainer';
export type FirstPlayer = 'player1' | 'player2' | 'random';
export type WhoInitialHint = 'silhouette' | 'cry' | 'pokedex_number' | 'description' | 'random';

export type SettingsControl =
  | 'generations'
  | 'categories'
  | 'noPokedex'
  | 'noSearch'
  | 'randomPokemon'
  | 'firstPlayer'
  | 'initialHint'
  | 'auctionFormat'
  | 'startingBudget';

export interface ModeSettings {
  generations: number[];
  categories: string[];
  noPokedex: boolean;
  noSearch: boolean;
  firstPlayer: FirstPlayer;
  randomPokemon: boolean;
  initialHint: WhoInitialHint;
  auctionFormat: AuctionFormat;
  startingBudget: number;
}

export type GuessGameSettings = Pick<ModeSettings, 'generations' | 'categories' | 'noPokedex' | 'noSearch' | 'firstPlayer' | 'randomPokemon'>;
export type WhoModeSettings = Pick<ModeSettings, 'generations' | 'categories' | 'initialHint'>;
export type AuctionModeSettings = Pick<ModeSettings, 'generations' | 'categories' | 'auctionFormat' | 'startingBudget'>;

export interface SettingsDefinition {
  configurable: boolean;
  controls: SettingsControl[];
}

export const DEFAULT_MODE_SETTINGS: Record<SettingsMode, ModeSettings> = {
  guess_my_pokemon: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
    auctionFormat: 'live',
    startingBudget: 1000,
  },
  stat_duel: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
    auctionFormat: 'live',
    startingBudget: 1000,
  },
  draft_duo: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
    auctionFormat: 'live',
    startingBudget: 1000,
  },
  who_that_pokemon: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
    auctionFormat: 'live',
    startingBudget: 1000,
  },
  pokemon_auction: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
    auctionFormat: 'live',
    startingBudget: 1000,
  },
  draft_trainer: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
    auctionFormat: 'live',
    startingBudget: 1000,
  },
};

const SETTINGS_DEFINITIONS: Record<SettingsMode, SettingsDefinition> = {
  guess_my_pokemon: {
    configurable: true,
    controls: ['generations', 'categories', 'noPokedex', 'noSearch', 'randomPokemon', 'firstPlayer'],
  },
  who_that_pokemon: {
    configurable: true,
    controls: ['generations', 'categories', 'initialHint'],
  },
  stat_duel: {
    configurable: true,
    controls: ['generations', 'categories'],
  },
  draft_duo: {
    configurable: true,
    controls: ['generations', 'categories'],
  },
  draft_trainer: {
    configurable: false,
    controls: [],
  },
  pokemon_auction: {
    configurable: true,
    controls: ['generations', 'categories', 'auctionFormat', 'startingBudget'],
  },
};

export function getSettingsDefinition(mode: SettingsMode): SettingsDefinition {
  return SETTINGS_DEFINITIONS[mode];
}

export function normalizeModeSettings(mode: SettingsMode, settings: Partial<ModeSettings> | null | undefined): ModeSettings {
  return { ...DEFAULT_MODE_SETTINGS[mode], ...(settings ?? {}) };
}

export function toGuessSettings(settings: ModeSettings): GuessGameSettings {
  return {
    generations: settings.generations,
    categories: settings.categories,
    noPokedex: settings.noPokedex,
    noSearch: settings.noSearch,
    firstPlayer: settings.firstPlayer,
    randomPokemon: settings.randomPokemon,
  };
}

export function toWhoSettings(settings: ModeSettings): WhoModeSettings {
  return {
    generations: settings.generations,
    categories: settings.categories,
    initialHint: settings.initialHint,
  };
}

export function toAuctionSettings(settings: ModeSettings): AuctionGameSettings {
  return {
    generations: settings.generations,
    categories: settings.categories,
    auctionFormat: settings.auctionFormat,
    startingBudget: settings.startingBudget,
  };
}

export function resolvePendingSettingsAfterSave(
  pendingSettings: ModeSettings | null,
  savedSettings: ModeSettings,
  saved: boolean,
): ModeSettings | null {
  if (!saved) return pendingSettings;
  return JSON.stringify(pendingSettings) === JSON.stringify(savedSettings) ? null : pendingSettings;
}
