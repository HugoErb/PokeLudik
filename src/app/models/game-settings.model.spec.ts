import {
  DEFAULT_MODE_SETTINGS,
  getActiveSettingsCount,
  getSettingsDefinition,
  normalizeModeSettings,
  resolvePendingSettingsAfterSave,
} from './game-settings.model';

describe('game settings model', () => {
  it('excludes trainer draft from configurable settings', () => {
    const definition = getSettingsDefinition('draft_trainer');

    expect(definition.configurable).toBeFalse();
    expect(definition.controls).toEqual([]);
    expect(getActiveSettingsCount('draft_trainer', normalizeModeSettings('draft_trainer', null))).toBe(0);
  });

  it('normalizes missing settings with mode defaults', () => {
    expect(normalizeModeSettings('who_that_pokemon', null)).toEqual(DEFAULT_MODE_SETTINGS.who_that_pokemon);
    expect(normalizeModeSettings('stat_duel', null)).toEqual(DEFAULT_MODE_SETTINGS.stat_duel);
    expect(normalizeModeSettings('draft_duo', null)).toEqual(DEFAULT_MODE_SETTINGS.draft_duo);
  });

  it('counts only active controls supported by the current mode', () => {
    const settings = normalizeModeSettings('guess_my_pokemon', {
      generations: [1],
      categories: ['starter'],
      noPokedex: true,
      initialHint: 'cry',
    });

    expect(getActiveSettingsCount('guess_my_pokemon', settings)).toBe(3);
  });

  it('keeps pending settings when remote save fails', () => {
    const settings = normalizeModeSettings('stat_duel', { generations: [1] });

    expect(resolvePendingSettingsAfterSave(settings, settings, false)).toBe(settings);
  });
});
