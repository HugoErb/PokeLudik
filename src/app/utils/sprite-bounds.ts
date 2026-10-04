/** Boîte des pixels visibles d'un sprite, en fractions (0 → 1) de l'image d'origine. */
export interface SpriteBounds {
  top: number;
  bottom: number;
  left: number;
  right: number;
  /** Rapport largeur / hauteur de l'image d'origine. */
  aspect: number;
}

const FULL_IMAGE: SpriteBounds = { top: 0, bottom: 1, left: 0, right: 1, aspect: 1 };
const ALPHA_THRESHOLD = 10;
/** Taille d'analyse : suffisante pour une boîte précise, légère pour le canvas. */
const SAMPLE_SIZE = 160;
const cache = new Map<string, Promise<SpriteBounds>>();

/**
 * Mesure la zone non transparente d'un artwork : les artworks officiels ont des marges variables,
 * il faut donc les ignorer pour afficher deux Pokémon à la même échelle.
 * Si l'image ne peut pas être lue (CORS, erreur réseau), l'image entière sert de repli.
 */
export function measureSpriteBounds(url: string): Promise<SpriteBounds> {
  let pending = cache.get(url);
  if (!pending) {
    pending = loadBounds(url);
    cache.set(url, pending);
  }
  return pending;
}

function loadBounds(url: string): Promise<SpriteBounds> {
  return new Promise(resolve => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.decoding = 'async';
    img.onload = () => resolve(computeBounds(img));
    img.onerror = () => resolve(FULL_IMAGE);
    img.src = url;
  });
}

function computeBounds(img: HTMLImageElement): SpriteBounds {
  const naturalWidth = img.naturalWidth || 1;
  const naturalHeight = img.naturalHeight || 1;
  const aspect = naturalWidth / naturalHeight;
  try {
    const scale = Math.min(1, SAMPLE_SIZE / Math.max(naturalWidth, naturalHeight));
    const width = Math.max(1, Math.round(naturalWidth * scale));
    const height = Math.max(1, Math.round(naturalHeight * scale));
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (!context) return { ...FULL_IMAGE, aspect };
    context.drawImage(img, 0, 0, width, height);
    const { data } = context.getImageData(0, 0, width, height);

    let top = height;
    let bottom = -1;
    let left = width;
    let right = -1;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        if (data[(y * width + x) * 4 + 3] <= ALPHA_THRESHOLD) continue;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
        if (x < left) left = x;
        if (x > right) right = x;
      }
    }
    if (bottom < 0) return { ...FULL_IMAGE, aspect };
    return {
      top: top / height,
      bottom: (bottom + 1) / height,
      left: left / width,
      right: (right + 1) / width,
      aspect,
    };
  } catch {
    // Canvas « tainted » : on ne peut pas lire les pixels.
    return { ...FULL_IMAGE, aspect };
  }
}
