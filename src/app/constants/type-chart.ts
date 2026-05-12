export const TYPE_ICONS: Record<string, string> = {
  'Normal': 'mdi:circle-outline',
  'Feu': 'mdi:fire',
  'Eau': 'mdi:water',
  'Électrik': 'mdi:lightning-bolt',
  'Plante': 'mdi:leaf',
  'Glace': 'mdi:snowflake',
  'Combat': 'fa6-solid:hand-fist',
  'Poison': 'mdi:skull-crossbones',
  'Sol': 'mdi:terrain',
  'Vol': 'game-icons:liberty-wing',
  'Psy': 'mdi:eye',
  'Insecte': 'mdi:bug',
  'Roche': 'mdi:hexagon',
  'Spectre': 'mdi:ghost',
  'Dragon': 'game-icons:sea-dragon',
  'Ténèbres': 'ic:round-dark-mode',
  'Acier': 'mdi:shield',
  'Fée': 'mdi:star-four-points',
};

export const TYPE_COLORS: Record<string, string> = {
  'Normal': 'bg-gray-400',
  'Feu': 'bg-orange-500',
  'Eau': 'bg-blue-500',
  'Électrik': 'bg-yellow-400',
  'Plante': 'bg-green-500',
  'Glace': 'bg-cyan-400',
  'Combat': 'bg-red-700',
  'Poison': 'bg-purple-500',
  'Sol': 'bg-yellow-600',
  'Vol': 'bg-indigo-400',
  'Psy': 'bg-pink-500',
  'Insecte': 'bg-lime-500',
  'Roche': 'bg-yellow-700',
  'Spectre': 'bg-violet-700',
  'Dragon': 'bg-indigo-600',
  'Ténèbres': 'bg-gray-700',
  'Acier': 'bg-slate-400',
  'Fée': 'bg-pink-300',
};

/** Attaquant → liste des types défensifs touchés en super-efficace */
export const TYPE_OFFENSIVE: Record<string, string[]> = {
  'Normal':   [],
  'Feu':      ['Plante', 'Glace', 'Insecte', 'Acier'],
  'Eau':      ['Feu', 'Sol', 'Roche'],
  'Plante':   ['Eau', 'Sol', 'Roche'],
  'Électrik': ['Eau', 'Vol'],
  'Glace':    ['Plante', 'Sol', 'Vol', 'Dragon'],
  'Combat':   ['Normal', 'Glace', 'Roche', 'Ténèbres', 'Acier'],
  'Poison':   ['Plante', 'Fée'],
  'Sol':      ['Feu', 'Électrik', 'Poison', 'Roche', 'Acier'],
  'Vol':      ['Plante', 'Combat', 'Insecte'],
  'Psy':      ['Combat', 'Poison'],
  'Insecte':  ['Plante', 'Psy', 'Ténèbres'],
  'Roche':    ['Feu', 'Glace', 'Vol', 'Insecte'],
  'Spectre':  ['Psy', 'Spectre'],
  'Dragon':   ['Dragon'],
  'Ténèbres': ['Psy', 'Spectre'],
  'Acier':    ['Glace', 'Roche', 'Fée'],
  'Fée':      ['Combat', 'Dragon', 'Ténèbres'],
};

/** Attaquant → multiplicateur par type défensif (uniquement les valeurs ≠ 1) */
export const TYPE_CHART: Record<string, Record<string, number>> = {
  'Normal':   { 'Roche': 0.5, 'Acier': 0.5, 'Spectre': 0 },
  'Feu':      { 'Feu': 0.5, 'Eau': 0.5, 'Plante': 2, 'Glace': 2, 'Insecte': 2, 'Roche': 0.5, 'Dragon': 0.5, 'Acier': 2 },
  'Eau':      { 'Feu': 2, 'Eau': 0.5, 'Plante': 0.5, 'Sol': 2, 'Roche': 2, 'Dragon': 0.5 },
  'Plante':   { 'Feu': 0.5, 'Eau': 2, 'Plante': 0.5, 'Poison': 0.5, 'Sol': 2, 'Vol': 0.5, 'Insecte': 0.5, 'Roche': 2, 'Dragon': 0.5, 'Acier': 0.5 },
  'Électrik': { 'Eau': 2, 'Plante': 0.5, 'Électrik': 0.5, 'Sol': 0, 'Vol': 2, 'Dragon': 0.5 },
  'Glace':    { 'Feu': 0.5, 'Eau': 0.5, 'Plante': 2, 'Glace': 0.5, 'Sol': 2, 'Vol': 2, 'Dragon': 2, 'Acier': 0.5 },
  'Combat':   { 'Normal': 2, 'Glace': 2, 'Poison': 0.5, 'Vol': 0.5, 'Psy': 0.5, 'Insecte': 0.5, 'Roche': 2, 'Spectre': 0, 'Ténèbres': 2, 'Acier': 2, 'Fée': 0.5 },
  'Poison':   { 'Plante': 2, 'Poison': 0.5, 'Sol': 0.5, 'Roche': 0.5, 'Spectre': 0.5, 'Acier': 0, 'Fée': 2 },
  'Sol':      { 'Feu': 2, 'Plante': 0.5, 'Électrik': 2, 'Poison': 2, 'Vol': 0, 'Insecte': 0.5, 'Roche': 2, 'Acier': 2 },
  'Vol':      { 'Plante': 2, 'Électrik': 0.5, 'Combat': 2, 'Insecte': 2, 'Roche': 0.5, 'Acier': 0.5 },
  'Psy':      { 'Combat': 2, 'Poison': 2, 'Psy': 0.5, 'Ténèbres': 0, 'Acier': 0.5 },
  'Insecte':  { 'Feu': 0.5, 'Plante': 2, 'Combat': 0.5, 'Poison': 0.5, 'Vol': 0.5, 'Psy': 2, 'Spectre': 0.5, 'Ténèbres': 2, 'Acier': 0.5, 'Fée': 0.5 },
  'Roche':    { 'Feu': 2, 'Glace': 2, 'Combat': 0.5, 'Sol': 0.5, 'Vol': 2, 'Insecte': 2, 'Acier': 0.5 },
  'Spectre':  { 'Normal': 0, 'Psy': 2, 'Spectre': 2, 'Ténèbres': 0.5 },
  'Dragon':   { 'Dragon': 2, 'Acier': 0.5, 'Fée': 0 },
  'Ténèbres': { 'Combat': 0.5, 'Psy': 2, 'Spectre': 2, 'Ténèbres': 0.5, 'Fée': 0.5 },
  'Acier':    { 'Feu': 0.5, 'Eau': 0.5, 'Électrik': 0.5, 'Glace': 2, 'Roche': 2, 'Acier': 0.5, 'Fée': 2 },
  'Fée':      { 'Feu': 0.5, 'Combat': 2, 'Poison': 0.5, 'Dragon': 2, 'Ténèbres': 2, 'Acier': 0.5 },
};

/** Multiplicateur effectif d'un type attaquant contre un défenseur multi-type */
export function effectiveMultiplier(defenderTypes: string[], attackerType: string): number {
  return defenderTypes.reduce((mult, defType) => mult * (TYPE_CHART[attackerType]?.[defType] ?? 1), 1);
}
