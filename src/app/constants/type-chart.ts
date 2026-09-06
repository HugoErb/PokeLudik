export const TYPE_ICON_PATHS: Record<string, string> = {
  'Normal': 'assets/type-icons/scarlet-violet/outlined/1.png',
  'Combat': 'assets/type-icons/scarlet-violet/outlined/2.png',
  'Vol': 'assets/type-icons/scarlet-violet/outlined/3.png',
  'Poison': 'assets/type-icons/scarlet-violet/outlined/4.png',
  'Sol': 'assets/type-icons/scarlet-violet/outlined/5.png',
  'Roche': 'assets/type-icons/scarlet-violet/outlined/6.png',
  'Insecte': 'assets/type-icons/scarlet-violet/outlined/7.png',
  'Spectre': 'assets/type-icons/scarlet-violet/outlined/8.png',
  'Acier': 'assets/type-icons/scarlet-violet/outlined/9.png',
  'Feu': 'assets/type-icons/scarlet-violet/outlined/10.png',
  'Eau': 'assets/type-icons/scarlet-violet/outlined/11.png',
  'Plante': 'assets/type-icons/scarlet-violet/outlined/12.png',
  'Électrik': 'assets/type-icons/scarlet-violet/outlined/13.png',
  'Psy': 'assets/type-icons/scarlet-violet/outlined/14.png',
  'Glace': 'assets/type-icons/scarlet-violet/outlined/15.png',
  'Dragon': 'assets/type-icons/scarlet-violet/outlined/16.png',
  'Ténèbres': 'assets/type-icons/scarlet-violet/outlined/17.png',
  'Fée': 'assets/type-icons/scarlet-violet/outlined/18.png',
};

export const TYPE_COLORS: Record<string, string> = {
  'Normal': 'bg-[#9fa19f]',
  'Combat': 'bg-[#ff8000]',
  'Vol': 'bg-[#81b9ef]',
  'Poison': 'bg-[#9141cb]',
  'Sol': 'bg-[#915121]',
  'Roche': 'bg-[#afa981]',
  'Insecte': 'bg-[#91a119]',
  'Spectre': 'bg-[#704170]',
  'Acier': 'bg-[#60a1b8]',
  'Feu': 'bg-[#e62829]',
  'Eau': 'bg-[#2980ef]',
  'Plante': 'bg-[#3fa129]',
  'Électrik': 'bg-[#fac000]',
  'Psy': 'bg-[#ef4179]',
  'Glace': 'bg-[#3fd8ff]',
  'Dragon': 'bg-[#5060e1]',
  'Ténèbres': 'bg-[#50413f]',
  'Fée': 'bg-[#ef70ef]',
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
