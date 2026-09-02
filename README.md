# PokéLudik

Application web de mini-jeux Pokémon, jouables en solo ou en multijoueur temps réel.

## Modes de jeu

- **Guess my Pokémon** : deux joueurs choisissent secrètement un Pokémon et tentent de deviner celui de l'adversaire.
- **Duel de Base Stats** : duel en plusieurs manches basé sur les statistiques des Pokémon.
- **Team Builder Solo** : création d'une équipe de 6 Pokémon puis évaluation automatique.
- **Team Builder Duo** : version multijoueur du Team Builder.
- **Team Builder vs Dresseur** : draft solo contre des dresseurs prédéfinis.

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

Synchronise le catalogue Pokémon embarqué dans le schéma SQL après une régénération des données.

```bash
npm run add:ratings
```

Ajoute ou recalcule les notes des Pokémon dans les données locales.

```bash
npm test
```

Lance les tests Angular.
