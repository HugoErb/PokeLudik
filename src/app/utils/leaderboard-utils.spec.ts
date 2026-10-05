import { buildSettingsKey, defaultSettingsKey, formatCategoryLabel, formatLeaderboardScore } from './leaderboard-utils';

describe('leaderboard utils', () => {
  it('construit la même clé canonique que le SQL (tri, dédoublonnage)', () => {
    expect(buildSettingsKey('stat_duel', { generations: [3, 1, 3], categories: [] })).toBe('g=1,3;c=');
    expect(buildSettingsKey('draft', { generations: [], categories: ['starter', 'bébé', 'starter'] })).toBe('g=;c=bébé,starter');
    expect(buildSettingsKey('who_that_pokemon', { generations: [10, 9], categories: [], initialHint: 'cry' })).toBe('g=9,10;c=;h=cry');
    expect(buildSettingsKey('size_up', { generations: [2], categories: [], roundTimer: 30 })).toBe('g=2;c=;t=30');
    expect(buildSettingsKey('size_up', { generations: [], categories: [], roundTimer: 0, showMeters: true })).toBe('g=;c=;t=0');
    expect(buildSettingsKey('size_up', { generations: [], categories: [], roundTimer: 15, showMeters: false })).toBe('g=;c=;t=15;m=0');
  });

  it('utilise les paramètres par défaut quand aucun filtre n\'est choisi', () => {
    expect(defaultSettingsKey('stat_duel')).toBe('g=;c=');
    expect(defaultSettingsKey('who_that_pokemon')).toBe('g=;c=;h=silhouette');
    expect(defaultSettingsKey('size_up')).toBe('g=;c=;t=0');
    expect(defaultSettingsKey('draft_trainer')).toBe('trainers_defeated');
    expect(buildSettingsKey('draft_trainer', { trainer: 4 })).toBe('trainer:4');
  });

  it('affiche un libellé lisible pour chaque catégorie', () => {
    expect(formatCategoryLabel('stat_duel', 'g=;c=', {})).toBe('Toutes générations · Toutes catégories');
    expect(formatCategoryLabel('who_that_pokemon', 'g=1,2;c=légendaire;h=cry', {
      generations: [1, 2], categories: ['légendaire'], initialHint: 'cry',
    })).toBe('Gén. 1, 2 · Légendaire · Indice : Cri');
    expect(formatCategoryLabel('draft_trainer', 'trainer:1', { trainer: 1 }, ['Pierre', 'Ondine'])).toBe('Ondine');
    expect(formatCategoryLabel('draft_trainer', 'trainers_defeated', {})).toBe('Dresseurs battus');
    expect(formatCategoryLabel('size_up', 'g=;c=;t=15', { roundTimer: 15 })).toBe('Toutes générations · Toutes catégories · Chrono 15 s');
    expect(formatCategoryLabel('size_up', 'g=;c=;t=0', {})).toBe('Toutes générations · Toutes catégories · Sans chrono');
    expect(formatCategoryLabel('size_up', 'g=;c=;t=0;m=0', { roundTimer: 0, showMeters: false })).toBe('Toutes générations · Toutes catégories · Sans chrono · Sans mètres');
  });

  it('formate les scores selon le mode', () => {
    expect(formatLeaderboardScore('stat_duel', 'g=;c=', 612)).toBe('612');
    expect(formatLeaderboardScore('draft', 'g=;c=', 7)).toBe('7.0/10');
    expect(formatLeaderboardScore('who_that_pokemon', 'g=;c=;h=silhouette', 42)).toBe('42 pts');
    expect(formatLeaderboardScore('draft_trainer', 'trainers_defeated', 3)).toBe('3 battus');
    expect(formatLeaderboardScore('size_up', 'g=;c=;t=0', 412)).toBe('412 pts');
  });
});
