/**
 * scripts/fetch-pokemon.js
 *
 * Récupère les données des 1025 premiers Pokémon depuis PokéAPI
 * et génère src/assets/pokemon.json.
 *
 * Usage : node scripts/fetch-pokemon.js
 * Prérequis : Node 18+ (fetch natif)
 */

import { writeFile, mkdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------------------
// Constantes
// ---------------------------------------------------------------------------

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTPUT_PATH = join(__dirname, '..', 'src', 'assets', 'pokemon.json');
const POKEAPI = 'https://pokeapi.co/api/v2';

const BATCH_SIZE = 20;
const BATCH_DELAY_MS = 500;
const RETRY_COUNT = 3;
const RETRY_DELAY_MS = 1000;

/** Mapping type anglais → français */
const TYPE_FR = {
  normal: 'Normal',
  fire: 'Feu',
  water: 'Eau',
  electric: 'Électrik',
  grass: 'Plante',
  ice: 'Glace',
  fighting: 'Combat',
  poison: 'Poison',
  ground: 'Sol',
  flying: 'Vol',
  psychic: 'Psy',
  bug: 'Insecte',
  rock: 'Roche',
  ghost: 'Spectre',
  dragon: 'Dragon',
  dark: 'Ténèbres',
  steel: 'Acier',
  fairy: 'Fée',
};

/** IDs des Pokémon starters (toutes générations, évolutions 1, 2 et 3) */
const STARTER_IDS = new Set([
  1,   2,   3,   4,   5,   6,   7,   8,   9,   // Gen 1
  152, 153, 154, 155, 156, 157, 158, 159, 160,  // Gen 2
  252, 253, 254, 255, 256, 257, 258, 259, 260,  // Gen 3
  387, 388, 389, 390, 391, 392, 393, 394, 395,  // Gen 4
  495, 496, 497, 498, 499, 500, 501, 502, 503,  // Gen 5
  650, 651, 652, 653, 654, 655, 656, 657, 658,  // Gen 6
  722, 723, 724, 725, 726, 727, 728, 729, 730,  // Gen 7
  810, 811, 812, 813, 814, 815, 816, 817, 818,  // Gen 8
  906, 907, 908, 909, 910, 911, 912, 913, 914,  // Gen 9
]);

/** Chiffres romains de génération → numéro */
const GENERATION_MAP = {
  'generation-i':    1,
  'generation-ii':   2,
  'generation-iii':  3,
  'generation-iv':   4,
  'generation-v':    5,
  'generation-vi':   6,
  'generation-vii':  7,
  'generation-viii': 8,
  'generation-ix':   9,
};

// ---------------------------------------------------------------------------
// Helpers réseau
// ---------------------------------------------------------------------------

/**
 * Fetch avec retry automatique (3 tentatives, délai 1s entre chaque).
 * @param {string} url
 * @returns {Promise<any>} JSON parsé
 */
async function fetchWithRetry(url) {
  let lastError;
  for (let attempt = 1; attempt <= RETRY_COUNT; attempt++) {
    try {
      const res = await fetch(url);
      if (!res.ok) {
        throw new Error(`HTTP ${res.status} pour ${url}`);
      }
      return await res.json();
    } catch (err) {
      lastError = err;
      if (attempt < RETRY_COUNT) {
        await sleep(RETRY_DELAY_MS * attempt);  // backoff exponentiel : 1s, 2s, 3s
      }
    }
  }
  throw lastError;
}

/** Pause en millisecondes */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Helpers de mapping
// ---------------------------------------------------------------------------

/**
 * Extrait le nom FR depuis un tableau de noms PokéAPI.
 * Fallback sur la valeur anglaise si introuvable.
 * @param {Array<{language:{name:string}, name:string}>} names
 * @param {string} fallback
 * @returns {string}
 */
function getNameFr(names, fallback) {
  const fr = names.find((n) => n.language.name === 'fr');
  if (fr) return fr.name;
  const en = names.find((n) => n.language.name === 'en');
  return en ? en.name : fallback;
}

/**
 * Extrait le numéro de génération depuis le nom (ex: "generation-i").
 * Ex : "generation-i" → 1
 * @param {string} generationName
 * @returns {number}
 */
function extractGeneration(generationName) {
  return GENERATION_MAP[generationName] ?? 0;
}

/**
 * Détermine la catégorie du Pokémon.
 * Priorité : légendaire > fabuleux > starter > normal
 * @param {object} species Données de l'espèce PokéAPI
 * @param {number} id
 * @returns {'légendaire'|'fabuleux'|'starter'|'normal'}
 */
function getCategory(species, id) {
  if (species.is_legendary) return 'légendaire';
  if (species.is_mythical)  return 'fabuleux';
  if (STARTER_IDS.has(id))  return 'starter';
  return 'normal';
}

/**
 * Détermine le stade d'évolution sous forme 'actuel/max' (ex: '1/3', '2/2').
 * @param {object} species Données de l'espèce PokéAPI
 * @returns {Promise<string>}
 */
async function getEvolutionStage(species) {
  try {
    const chainData = await fetchWithRetry(species.evolution_chain.url);

    /** Analyse une chaine d'evolution pour retrouver la profondeur du Pokemon cible et la profondeur maximale. */
    function analyzeChain(node, targetName, currentDepth = 1) {
      let myDepth = node.species.name === targetName ? currentDepth : -1;
      let maxDepth = currentDepth;
      
      for (const child of node.evolves_to) {
        const childResult = analyzeChain(child, targetName, currentDepth + 1);
        if (childResult.myDepth !== -1) myDepth = childResult.myDepth;
        if (childResult.maxDepth > maxDepth) maxDepth = childResult.maxDepth;
      }
      
      return { myDepth, maxDepth };
    }

    const result = analyzeChain(chainData.chain, species.name);
    const stage = result.myDepth === -1 ? 1 : result.myDepth;
    const max = result.maxDepth;

    return `${stage}/${max}`;
  } catch {
    return '1/1';
  }
}

/**
 * Mappe les stats PokéAPI vers les clés françaises.
 * @param {Array<{stat:{name:string}, base_stat:number}>} stats
 * @returns {object}
 */
function mapStats(stats) {
  const STAT_MAP = {
    hp:               'pv',
    attack:           'attaque',
    defense:          'defense',
    'special-attack': 'atq_spe',
    'special-defense':'def_spe',
    speed:            'vitesse',
  };
  const result = {};
  for (const entry of stats) {
    const key = STAT_MAP[entry.stat.name];
    if (key) result[key] = entry.base_stat;
  }
  return result;
}

/**
 * Extrait la première description FR (ou EN en fallback) depuis flavor_text_entries.
 * @param {Array<{flavor_text:string, language:{name:string}}>} entries
 * @returns {string}
 */
function getDescription(entries) {
  const clean = (text) =>
    text.replace(/[\n\f\r]+/g, ' ').replace(/\s{2,}/g, ' ').trim();

  const fr = entries.find((e) => e.language.name === 'fr');
  if (fr) return clean(fr.flavor_text);

  const en = entries.find((e) => e.language.name === 'en');
  if (en) return clean(en.flavor_text);

  return '';
}

// ---------------------------------------------------------------------------
// Traitement d'un Pokémon
// ---------------------------------------------------------------------------

/**
 * Récupère et assemble toutes les données d'un Pokémon.
 * @param {number} id
 * @param {number} index Position dans la liste (pour le log)
 * @param {number} total
 * @returns {Promise<object|null>} Objet Pokémon ou null en cas d'échec
 */
async function processPokemon(id, index, total) {
  try {
    // Fetch Pokémon + espèce en parallèle
    const [pokemon, species] = await Promise.all([
      fetchWithRetry(`${POKEAPI}/pokemon/${id}`),
      fetchWithRetry(`${POKEAPI}/pokemon-species/${id}`),
    ]);

    // Abilities : fetch en parallèle
    const abilityData = await Promise.all(
      pokemon.abilities.map((a) =>
        fetchWithRetry(`${POKEAPI}/ability/${a.ability.name}`)
      )
    );

    // Stade d'évolution
    let evolutionStage = await getEvolutionStage(species);

    // Override pour Phione et Manaphy (PokéAPI les lie parfois à tort en évolution)
    if (id === 489 || id === 490) {
      evolutionStage = '1/1';
    }

    // Nom FR
    const name = getNameFr(species.names, pokemon.name);

    // Types FR
    const types = pokemon.types
      .sort((a, b) => a.slot - b.slot)
      .map((t) => TYPE_FR[t.type.name] ?? t.type.name);

    // Génération
    const generation = extractGeneration(species.generation.name);

    // Catégorie
    const category = getCategory(species, id);

    // Sprite
    const sprite = `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/${id}.png`;

    // Cri
    const cry = `https://raw.githubusercontent.com/PokeAPI/cries/main/cries/pokemon/latest/${id}.ogg`;

    // Stats
    const stats = mapStats(pokemon.stats);

    // Abilities FR
    const abilities = abilityData.map((a) => getNameFr(a.names, a.name));

    // Taille & Poids
    const height = pokemon.height / 10;
    const weight = pokemon.weight / 10;

    // Description
    const description = getDescription(species.flavor_text_entries);

    return {
      id,
      name,
      types,
      generation,
      category,
      evolution_stage: evolutionStage,
      sprite,
      cry,
      stats,
      abilities,
      height,
      weight,
      description,
    };
  } catch (err) {
    console.error(`  [ERREUR] Pokémon #${id} (${index}/${total}) : ${err.message}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Traitement par batches
// ---------------------------------------------------------------------------

/**
 * Exécute un tableau de fonctions async par groupes de taille `batchSize`,
 * avec une pause entre chaque groupe.
 * @param {Array<() => Promise<any>>} tasks
 * @param {number} batchSize
 * @param {number} delayMs
 * @returns {Promise<any[]>}
 */
async function runInBatches(tasks, batchSize, delayMs) {
  const results = [];
  for (let i = 0; i < tasks.length; i += batchSize) {
    const batch = tasks.slice(i, i + batchSize);
    const batchResults = await Promise.all(batch.map((fn) => fn()));
    results.push(...batchResults);
    if (i + batchSize < tasks.length) {
      await sleep(delayMs);
    }
  }
  return results;
}

// ---------------------------------------------------------------------------
// Point d'entrée
// ---------------------------------------------------------------------------

/** Point d'entree du script. */
async function main() {
  console.log('=== Génération de pokemon.json ===\n');

  // 1. Récupère la liste des 1025 premiers Pokémon
  console.log('Récupération de la liste des Pokémon...');
  const listData = await fetchWithRetry(
    `${POKEAPI}/pokemon?limit=1025&offset=0`
  );
  const total = listData.results.length;
  console.log(`${total} Pokémon trouvés.\n`);

  // 2. Extrait les IDs depuis les URLs
  const pokemonIds = listData.results.map((p) => {
    const parts = p.url.replace(/\/$/, '').split('/');
    return parseInt(parts[parts.length - 1], 10);
  });

  // 3. Crée les tâches et les exécute par batches
  let processed = 0;
  const tasks = pokemonIds.map((id) => async () => {
    processed++;
    if (processed === 1 || processed % 100 === 0) {
      console.log(`Traitement ${processed}/${total}...`);
    }
    return processPokemon(id, processed, total);
  });

  const rawResults = await runInBatches(tasks, BATCH_SIZE, BATCH_DELAY_MS);

  // 4. Filtre les erreurs (null)
  const pokemonList = rawResults.filter(Boolean);
  const failedCount = total - pokemonList.length;

  // 5. Sauvegarde
  console.log('\nSauvegarde du fichier...');
  await mkdir(dirname(OUTPUT_PATH), { recursive: true });
  await writeFile(OUTPUT_PATH, JSON.stringify(pokemonList, null, 2), 'utf-8');

  // 6. Résumé
  console.log(`\n=== Terminé ===`);
  console.log(`Pokémon traités avec succès : ${pokemonList.length}/${total}`);
  if (failedCount > 0) {
    console.log(`Pokémon en erreur : ${failedCount}`);
  }
  console.log(`Fichier généré : ${OUTPUT_PATH}`);
}

main().catch((err) => {
  console.error('Erreur fatale :', err);
  process.exit(1);
});
