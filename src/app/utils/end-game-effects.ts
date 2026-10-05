import confetti from 'canvas-confetti';

/** Seuils de victoire des modes solo (score ≥ seuil = victoire). */
export const WHO_SOLO_WIN_SCORE = 40;
export const SIZE_UP_SOLO_WIN_SCORE = 375;
export const STAT_DUEL_SOLO_WIN_SCORE = 600;
export const DRAFT_SOLO_WIN_RATING = 7;

export const isWhoSoloVictory = (score: number): boolean => score >= WHO_SOLO_WIN_SCORE;
export const isSizeUpSoloVictory = (score: number): boolean => score >= SIZE_UP_SOLO_WIN_SCORE;
export const isStatDuelSoloVictory = (total: number): boolean => total >= STAT_DUEL_SOLO_WIN_SCORE;
export const isDraftSoloVictory = (rating: number): boolean => rating >= DRAFT_SOLO_WIN_RATING;

const VICTORY_COLORS = ['#ef4444', '#facc15', '#a855f7', '#3b82f6', '#ffffff'];
const RAIN_COLORS = ['#64748b', '#94a3b8', '#475569', '#cbd5e1'];
const RAIN_DURATION_MS = 1500;
const RAIN_INTERVAL_MS = 50;
const RAIN_DROPS_PER_TICK = 3;
const VEIL_HOLD_MS = 1200;
const VEIL_FADE_MS = 600;

/** Lance l'animation de confettis de victoire (identique dans tous les modes). */
export function launchVictoryConfetti(): void {
  void confetti({ particleCount: 160, spread: 110, origin: { x: 0.5, y: 0.4 }, colors: VICTORY_COLORS });
}

/**
 * Lance l'animation de défaite : pluie grise qui tombe du haut de l'écran et voile sombre qui s'estompe.
 * Avec `prefers-reduced-motion`, seul le voile est affiché. Retourne une fonction de nettoyage.
 */
export function launchDefeatRain(): () => void {
  const timers: ReturnType<typeof setTimeout>[] = [];
  const veil = showDefeatVeil(timers);

  let rain: ReturnType<typeof setInterval> | null = null;
  if (!prefersReducedMotion()) {
    const drop = confetti.shapeFromPath({ path: 'M0 0 L1.5 0 L1.5 14 L0 14 Z' });
    const endAt = Date.now() + RAIN_DURATION_MS;
    rain = setInterval(() => {
      if (Date.now() > endAt) {
        if (rain) clearInterval(rain);
        rain = null;
        return;
      }
      for (let i = 0; i < RAIN_DROPS_PER_TICK; i++) {
        void confetti({
          particleCount: 1,
          angle: 270,
          spread: 0,
          startVelocity: 25,
          gravity: 3,
          ticks: 120,
          origin: { x: Math.random(), y: -0.05 },
          colors: RAIN_COLORS,
          shapes: [drop],
          scalar: 1.4,
          flat: true,
        });
      }
    }, RAIN_INTERVAL_MS);
  }

  return () => {
    if (rain) clearInterval(rain);
    timers.forEach(clearTimeout);
    veil?.remove();
  };
}

function showDefeatVeil(timers: ReturnType<typeof setTimeout>[]): HTMLElement | null {
  if (typeof document === 'undefined') return null;
  const veil = document.createElement('div');
  veil.setAttribute('aria-hidden', 'true');
  Object.assign(veil.style, {
    position: 'fixed',
    inset: '0',
    zIndex: '90',
    pointerEvents: 'none',
    background: 'radial-gradient(ellipse at center, rgba(15, 23, 42, 0.15) 0%, rgba(15, 23, 42, 0.55) 100%)',
    opacity: '0',
    transition: `opacity ${VEIL_FADE_MS / 2}ms ease-out`,
  });
  document.body.appendChild(veil);
  requestAnimationFrame(() => (veil.style.opacity = '1'));
  timers.push(
    setTimeout(() => {
      veil.style.transition = `opacity ${VEIL_FADE_MS}ms ease-in`;
      veil.style.opacity = '0';
    }, VEIL_HOLD_MS),
    setTimeout(() => veil.remove(), VEIL_HOLD_MS + VEIL_FADE_MS),
  );
  return veil;
}

function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
}
