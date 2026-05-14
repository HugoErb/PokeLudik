import type { GameMode } from './room.model';

export type SettingsMode = GameMode | 'draft_trainer';
export type FirstPlayer = 'player1' | 'player2' | 'random';
export type WhoInitialHint = 'silhouette' | 'cry' | 'pokedex_number' | 'description';

export type SettingsControl =
  | 'generations'
  | 'categories'
  | 'noPokedex'
  | 'noSearch'
  | 'randomPokemon'
  | 'firstPlayer'
  | 'initialHint';

export interface ModeSettings {
  generations: number[];
  categories: string[];
  noPokedex: boolean;
  noSearch: boolean;
  firstPlayer: FirstPlayer;
  randomPokemon: boolean;
  initialHint: WhoInitialHint;
}

export type GuessGameSettings = Pick<ModeSettings, 'generations' | 'categories' | 'noPokedex' | 'noSearch' | 'firstPlayer' | 'randomPokemon'>;
export type WhoModeSettings = Pick<ModeSettings, 'generations' | 'categories' | 'initialHint'>;

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
  },
  stat_duel: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
  },
  draft_duo: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
  },
  who_that_pokemon: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
  },
  draft_trainer: {
    generations: [],
    categories: [],
    noPokedex: false,
    noSearch: false,
    firstPlayer: 'random',
    randomPokemon: false,
    initialHint: 'silhouette',
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

export function getActiveSettingsCount(mode: SettingsMode, settings: ModeSettings): number {
  const controls = new Set(getSettingsDefinition(mode).controls);
  let count = 0;
  if (controls.has('generations') && settings.generations.length > 0) count++;
  if (controls.has('categories') && settings.categories.length > 0) count++;
  if (controls.has('noPokedex') && settings.noPokedex) count++;
  if (controls.has('noSearch') && settings.noSearch) count++;
  if (controls.has('randomPokemon') && settings.randomPokemon) count++;
  if (controls.has('firstPlayer') && settings.firstPlayer !== 'random') count++;
  if (controls.has('initialHint') && settings.initialHint !== DEFAULT_MODE_SETTINGS.who_that_pokemon.initialHint) count++;
  return count;
}

export function resolvePendingSettingsAfterSave(
  pendingSettings: ModeSettings | null,
  savedSettings: ModeSettings,
  saved: boolean,
): ModeSettings | null {
  if (!saved) return pendingSettings;
  return JSON.stringify(pendingSettings) === JSON.stringify(savedSettings) ? null : pendingSettings;
}
