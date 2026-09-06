import {
  DEFAULT_MODE_SETTINGS,
  getSettingsDefinition,
  normalizeModeSettings,
  resolvePendingSettingsAfterSave,
} from './game-settings.model';

describe('game settings model', () => {
  it('excludes trainer draft from configurable settings', () => {
    const definition = getSettingsDefinition('draft_trainer');

    expect(definition.configurable).toBeFalse();
    expect(definition.controls).toEqual([]);
  });

  it('normalizes missing settings with mode defaults', () => {
    expect(normalizeModeSettings('who_that_pokemon', null)).toEqual(DEFAULT_MODE_SETTINGS.who_that_pokemon);
    expect(normalizeModeSettings('stat_duel', null)).toEqual(DEFAULT_MODE_SETTINGS.stat_duel);
    expect(normalizeModeSettings('draft_duo', null)).toEqual(DEFAULT_MODE_SETTINGS.draft_duo);
    expect(normalizeModeSettings('pokemon_auction', null)).toEqual(DEFAULT_MODE_SETTINGS.pokemon_auction);
  });

  it('expose le format et le budget des enchères', () => {
    expect(getSettingsDefinition('pokemon_auction').controls).toContain('auctionFormat');
    expect(getSettingsDefinition('pokemon_auction').controls).toContain('startingBudget');
  });

  it('keeps pending settings when remote save fails', () => {
    const settings = normalizeModeSettings('stat_duel', { generations: [1] });

    expect(resolvePendingSettingsAfterSave(settings, settings, false)).toBe(settings);
  });
});
