import { readFile } from 'node:fs/promises';

const [typeChartSource, auctionSql, auctionCatalog, pokemonSource, serviceSource] = await Promise.all([
  readFile(new URL('../src/app/constants/type-chart.ts', import.meta.url), 'utf8'),
  readFile(new URL('../sql-schema/pokemon-auction.sql', import.meta.url), 'utf8'),
  readFile(new URL('../sql-schema/pokemon-auction-catalog.sql', import.meta.url), 'utf8'),
  readFile(new URL('../src/assets/pokemon.json', import.meta.url), 'utf8'),
  readFile(new URL('../src/app/services/supabase.service.ts', import.meta.url), 'utf8'),
]);

const chartDeclaration = typeChartSource.indexOf('export const TYPE_CHART');
const chartStart = typeChartSource.indexOf('{', chartDeclaration);
const chartEnd = typeChartSource.indexOf('\n};', chartStart) + 2;
if (chartDeclaration < 0 || chartStart < 0 || chartEnd < 2) throw new Error('TYPE_CHART introuvable');
const clientChart = {};
for (const line of typeChartSource.slice(chartStart + 1, chartEnd - 1).split('\n')) {
  const attacker = line.match(/^\s*'([^']+)':\s*\{(.*)\},?\s*$/);
  if (!attacker) continue;
  clientChart[attacker[1]] = {};
  for (const matchup of attacker[2].matchAll(/'([^']+)':\s*([0-9.]+)/g)) {
    clientChart[attacker[1]][matchup[1]] = Number(matchup[2]);
  }
}

const sqlChartPrefix = "SELECT coalesce((('";
const sqlChartStart = auctionSql.indexOf(sqlChartPrefix) + sqlChartPrefix.length;
const sqlChartEnd = auctionSql.indexOf("'::jsonb", sqlChartStart);
if (sqlChartStart < sqlChartPrefix.length || sqlChartEnd < 0) throw new Error('Table des types SQL introuvable');
const serverChart = JSON.parse(auctionSql.slice(sqlChartStart, sqlChartEnd));
if (JSON.stringify(clientChart) !== JSON.stringify(serverChart)) throw new Error('La table des types client et serveur diffère');

const pokemon = JSON.parse(pokemonSource);
const catalogRows = auctionCatalog.match(/^\(\d+,ARRAY\[/gm)?.length ?? 0;
if (catalogRows !== pokemon.length) throw new Error(`Catalogue incomplet : ${catalogRows}/${pokemon.length}`);

if (auctionSql.includes('save_pokemon_auction_result(p_room_id uuid,p_p1_stats')) {
  throw new Error('Ancienne RPC de résultat pilotée par le client encore présente');
}
if (!serviceSource.includes("rpc('save_pokemon_auction_result', { p_room_id: roomId })")) {
  throw new Error('Le client ne cible pas la RPC de résultat sécurisée');
}

console.log(`Enchères vérifiées : ${Object.keys(clientChart).length} types et ${catalogRows} Pokémon synchronisés.`);
