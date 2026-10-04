# PokéLudik — Architecture

Angular 21 + Tailwind + Supabase (realtime multiplayer). Stack standalone components, lazy routing, SSE via Supabase channels.

---

## Arborescence src/app/

```
src/app/
├── app.component.ts / .html / .css     ← shell (router-outlet)
├── app.config.ts                        ← providers Angular
├── app.routes.ts                        ← routes lazy-loadées
│
├── pages/                               ← composants routés
│   ├── login/          /login           (public)
│   ├── reset-password/ /reset-password  (public)
│   ├── home/           /home            (auth)
│   ├── invite/         /invite/:roomId  (auth)
│   ├── lobby/          /lobby/:roomId   (auth)
│   ├── game/           /game/:roomId    (auth)
│   ├── draft/          /draft           (auth)
│   ├── stat-duel/      /stat-duel       (auth) + /stat-duel/:roomId
│   └── size-up/        /size-up         (auth) + /size-up/:roomId
│
├── components/                          ← réutilisables
│   ├── cancel-modal/
│   ├── draft-help-modal/
│   ├── duel-intro/
│   ├── end-game-modal/
│   ├── friends-card/
│   ├── game-settings-modal/
│   ├── help-modal/
│   ├── incorrect-guess-modal/
│   ├── my-turn-modal/
│   ├── pokedex/
│   ├── pokemon-card/
│   ├── rules-modal/
│   └── size-up-board/  ← plateau Size Up (sprites à l'échelle)
│
├── services/
│   ├── supabase.service.ts   ← auth + DB + realtime (Supabase client)
│   ├── game.service.ts       ← logique partie (rooms, tours, états)
│   └── pokemon.service.ts    ← données Pokémon (liste, recherche)
│
├── models/
│   ├── pokemon.model.ts      ← interface Pokemon
│   └── room.model.ts         ← interface Room / GameState
│
├── guards/
│   └── auth.guard.ts         ← redirige vers /login si non connecté
│
└── constants/
    ├── animations.ts
    ├── icons-registry.ts
    └── icons.ts
```

---

## Flux de navigation

```
/login ──────────────────────────────────────────────┐
/reset-password ─────────────────────────────────────┤ public
                                                      │
/home ──→ crée/rejoint room ──→ /invite/:roomId      │ auth (authGuard)
                                      │
                              /lobby/:roomId
                                      │
                    ┌─────────────────┴──────────────┐
              /game/:roomId                  /stat-duel/:roomId
          (Guess My Pokémon)             (Stat Duel)
                                                      │
                                             /stat-duel (solo)
                                                      │
                                             /draft (team builder)
```

---

## Services — responsabilités

| Service | Rôle principal |
|---|---|
| `SupabaseService` | Client Supabase, auth (signIn/signOut/session), CRUD DB, subscriptions realtime |
| `GameService` | Orchestration d'une partie : création de room, gestion des tours, états, timers |
| `PokemonService` | Chargement du JSON Pokémon, filtres, recherche autocomplete |

---

## Modèles clés

- **Pokemon** — id, name, types, stats, image, génération, etc.
- **Room** — id, players[], status, currentTurn, gameMode, settings

---

## Scripts utiles

```bash
npm start                  # ng serve (dev)
npm run build              # ng build (prod)
npm run generate:pokemon   # fetch Pokémon data → assets JSON
npm run add:ratings        # ajoute ratings au dataset
bash redeploiement.sh      # déploiement prod
```

---

## Conventions projet

- Tous les composants sont **standalone** (pas de NgModule)
- Routes **lazy-loadées** (`loadComponent`)
- Styles : **Tailwind CSS** (postcss)
- Icônes : **Iconify** (`iconify-icon`, registry dans `constants/icons-registry.ts`)
- Animations : centralisées dans `constants/animations.ts`
- Backend : **Supabase** (PostgreSQL + realtime channels + auth)
