# PokéLudik

Application web de mini-jeux Pokémon, jouables en solo ou en multijoueur temps réel.

## Modes de jeu

- **Guess my Pokémon** : deux joueurs choisissent secrètement un Pokémon et tentent de deviner celui de l'adversaire.
- **Duel de Base Stats** : duel en plusieurs manches basé sur les statistiques des Pokémon.
- **Team Builder Solo** : création d'une équipe de 6 Pokémon puis évaluation automatique.
- **Team Builder Duo** : version multijoueur du Team Builder.
- **Team Builder vs Dresseur** : draft solo contre des dresseurs prédéfinis.
- **Enchères Pokémon** : deux joueurs gèrent un budget et se disputent les Pokémon pour composer leurs équipes.

## Fonctionnalités

- Authentification Supabase.
- Profils utilisateurs avec pseudo et avatar.
- Système d'amis.
- Invitations de jeu entre amis.
- Salons multijoueur avec lobby.
- Synchronisation temps réel via Supabase Realtime.
- Pokédex intégré avec filtres.
- Données Pokémon générées depuis PokéAPI.

## Stack

| Technologie | Usage |
|-------------|-------|
| Angular 21 | Frontend |
| TypeScript | Langage |
| TailwindCSS | Styles |
| Supabase | Auth, PostgreSQL, Realtime |
| PokéAPI | Source des données Pokémon |

## Prérequis

- Node.js 18 ou plus récent.
- npm.
- Un projet Supabase configuré.

## Installation

```bash
npm install
```

## Configuration

Créer ou mettre à jour `src/environments/environment.ts` :

```ts
export const environment = {
  production: false,
  supabaseUrl: 'https://VOTRE_PROJET.supabase.co',
  supabaseKey: 'VOTRE_CLE_ANON_PUBLIQUE'
};
```

Le schéma de référence est dans `sql-schema/ddb-schema.sql`. Il doit être appliqué à Supabase : les règles de jeu multijoueur et le catalogue de validation sont exécutés côté PostgreSQL.

- Installation neuve : appliquer `sql-schema/ddb-schema.sql`, puis `sql-schema/pokemon-auction.sql`.
- Base existante : appliquer `sql-schema/pokemon-auction-catalog.sql`, puis `sql-schema/pokemon-auction.sql`.

Le fichier de catalogue intermédiaire est une migration additive autonome : il crée uniquement `pokemon_catalog` si cette table manque, puis synchronise les données nécessaires au calcul sécurisé du résultat côté serveur.
La migration des enchères active également `pokemon_auction_rooms` dans Supabase Realtime.

Pour une base existante, appliquer `sql-schema/pokemon-auction-catalog.sql`, puis
`sql-schema/functional-fixes.sql` avant de déployer le frontend corrigé. Cette migration
ajoute la RPC de revanche Guess, aligne le gagnant du Draft Duo sur la moyenne des
notes de statistiques et de couverture, et corrige les immunités dans le calcul de couverture.
Elle est transactionnelle et peut être réexécutée. Ces fonctions sont déjà incluses
dans `ddb-schema.sql` pour une installation neuve.

## Scripts

```bash
npm start
```

Lance le serveur Angular en développement.

```bash
npm run build
```

Génère le build de production dans `dist/pokeludik`.

```bash
npm run generate:pokemon
```

Régénère `src/assets/pokemon.json` depuis PokéAPI.

```bash
npm run generate:pokemon-sql
```

Synchronise le catalogue Pokémon du schéma de référence et la migration de catalogue des enchères après une régénération des données.

```bash
npm run add:ratings
```

Ajoute ou recalcule les notes des Pokémon dans les données locales.

```bash
npm test
```

Lance les tests Angular.

```bash
npm run verify:functional-sql
```

Exécute les fonctions SQL dans un PostgreSQL local en mémoire (PGlite), vérifie les
revanches, les permissions, la migration et la parité des scores avec le TypeScript.
Ce contrôle ne se connecte pas au projet Supabase.
