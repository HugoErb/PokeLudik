import {
  DRAFT_SOLO_WIN_RATING,
  isDraftSoloVictory,
  isSizeUpSoloVictory,
  isStatDuelSoloVictory,
  isWhoSoloVictory,
  SIZE_UP_SOLO_WIN_SCORE,
  STAT_DUEL_SOLO_WIN_SCORE,
  WHO_SOLO_WIN_SCORE,
} from './end-game-effects';

describe('end-game-effects', () => {
  it('considère le seuil exact comme une victoire', () => {
    expect(isWhoSoloVictory(WHO_SOLO_WIN_SCORE)).toBeTrue();
    expect(isSizeUpSoloVictory(SIZE_UP_SOLO_WIN_SCORE)).toBeTrue();
    expect(isStatDuelSoloVictory(STAT_DUEL_SOLO_WIN_SCORE)).toBeTrue();
    expect(isDraftSoloVictory(DRAFT_SOLO_WIN_RATING)).toBeTrue();
  });

  it('considère un score sous le seuil comme une défaite', () => {
    expect(isWhoSoloVictory(WHO_SOLO_WIN_SCORE - 1)).toBeFalse();
    expect(isSizeUpSoloVictory(SIZE_UP_SOLO_WIN_SCORE - 1)).toBeFalse();
    expect(isStatDuelSoloVictory(STAT_DUEL_SOLO_WIN_SCORE - 1)).toBeFalse();
    expect(isDraftSoloVictory(DRAFT_SOLO_WIN_RATING - 0.1)).toBeFalse();
  });
});
