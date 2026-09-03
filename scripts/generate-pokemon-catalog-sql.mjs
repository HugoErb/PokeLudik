import { readFile, writeFile } from 'node:fs/promises';

const schemaPath = new URL('../sql-schema/ddb-schema.sql', import.meta.url);
const auctionCatalogPath = new URL('../sql-schema/pokemon-auction-catalog.sql', import.meta.url);
const pokemonPath = new URL('../src/assets/pokemon.json', import.meta.url);
const startMarker = '-- POKEMON_CATALOG_DATA_START';
const endMarker = '-- POKEMON_CATALOG_DATA_END';

const [schema, rawPokemon] = await Promise.all([
  readFile(schemaPath, 'utf8'),
  readFile(pokemonPath, 'utf8'),
]);
const pokemon = JSON.parse(rawPokemon);

const quote = value => `'${String(value).replaceAll("'", "''")}'`;
const rows = pokemon.map(entry => {
  const stats = entry.stats;
  const types = `ARRAY[${entry.types.map(quote).join(',')}]::text[]`;
  return `(${entry.id},${entry.generation},${quote(entry.category)},${types},${Number(entry.rating)},${stats.pv},${stats.attaque},${stats.defense},${stats.atq_spe},${stats.def_spe},${stats.vitesse})`;
});
const seed = [
  'INSERT INTO public.pokemon_catalog (id, generation, category, types, rating, pv, attaque, defense, atq_spe, def_spe, vitesse) VALUES',
  `${rows.join(',\n')}\nON CONFLICT (id) DO UPDATE SET`,
  'generation = EXCLUDED.generation, category = EXCLUDED.category, types = EXCLUDED.types, rating = EXCLUDED.rating, pv = EXCLUDED.pv,',
  'attaque = EXCLUDED.attaque, defense = EXCLUDED.defense, atq_spe = EXCLUDED.atq_spe,',
  'def_spe = EXCLUDED.def_spe, vitesse = EXCLUDED.vitesse;',
].join('\n');

const start = schema.indexOf(startMarker);
const end = schema.indexOf(endMarker);
if (start < 0 || end < start) throw new Error('Marqueurs du catalogue introuvables');

const updated = `${schema.slice(0, start + startMarker.length)}\n${seed}\n${schema.slice(end)}`;
const auctionCatalog = [
  '-- Fichier généré par npm run generate:pokemon-sql. Ne pas modifier manuellement.',
  '-- Migration additive autonome à appliquer avant pokemon-auction.sql.',
  '',
  'CREATE TABLE IF NOT EXISTS public.pokemon_catalog (',
  '  id integer PRIMARY KEY,',
  '  generation integer NOT NULL,',
  '  category text NOT NULL,',
  "  types text[] DEFAULT '{}'::text[] NOT NULL,",
  '  rating numeric(3,1) DEFAULT 0 NOT NULL,',
  '  pv integer NOT NULL,',
  '  attaque integer NOT NULL,',
  '  defense integer NOT NULL,',
  '  atq_spe integer NOT NULL,',
  '  def_spe integer NOT NULL,',
  '  vitesse integer NOT NULL',
  ');',
  '',
  "ALTER TABLE public.pokemon_catalog ADD COLUMN IF NOT EXISTS types text[] DEFAULT '{}'::text[] NOT NULL;",
  'ALTER TABLE public.pokemon_catalog ADD COLUMN IF NOT EXISTS rating numeric(3,1) DEFAULT 0 NOT NULL;',
  '',
  seed,
  '',
  'ALTER TABLE public.pokemon_catalog ENABLE ROW LEVEL SECURITY;',
  'REVOKE ALL ON TABLE public.pokemon_catalog FROM anon, authenticated;',
  "NOTIFY pgrst, 'reload schema';",
  '',
].join('\n');

await Promise.all([
  writeFile(schemaPath, updated, 'utf8'),
  writeFile(auctionCatalogPath, auctionCatalog, 'utf8'),
]);
