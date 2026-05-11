import { Routes } from '@angular/router';
import { authGuard } from './guards/auth.guard';

export const routes: Routes = [
  { path: '', redirectTo: '/home', pathMatch: 'full' },
  { path: 'login', loadComponent: () => import('./pages/login/login.component').then(m => m.LoginComponent) },
  { path: 'home', loadComponent: () => import('./pages/home/home.component').then(m => m.HomeComponent), canActivate: [authGuard] },
  { path: 'invite/:roomId', loadComponent: () => import('./pages/invite/invite.component').then(m => m.InviteComponent), canActivate: [authGuard] },
  { path: 'lobby/:roomId', loadComponent: () => import('./pages/lobby/lobby.component').then(m => m.LobbyComponent), canActivate: [authGuard] },
  { path: 'game/:roomId', loadComponent: () => import('./pages/game/game.component').then(m => m.GameComponent), canActivate: [authGuard] },
  { path: 'who-that-pokemon', loadComponent: () => import('./pages/who-that-pokemon/who-that-pokemon.component').then(m => m.WhoThatPokemonComponent), canActivate: [authGuard] },
  { path: 'who-that-pokemon/:roomId', loadComponent: () => import('./pages/who-that-pokemon/who-that-pokemon.component').then(m => m.WhoThatPokemonComponent), canActivate: [authGuard] },
  { path: 'reset-password', loadComponent: () => import('./pages/reset-password/reset-password.component').then(m => m.ResetPasswordComponent) },
  { path: 'draft', loadComponent: () => import('./pages/draft/draft.component').then(m => m.DraftComponent), canActivate: [authGuard] },
  { path: 'stat-duel', loadComponent: () => import('./pages/stat-duel/stat-duel.component').then(m => m.StatDuelComponent), canActivate: [authGuard] },
  { path: 'stat-duel/:roomId', loadComponent: () => import('./pages/stat-duel/stat-duel.component').then(m => m.StatDuelComponent), canActivate: [authGuard] },
  { path: 'draft-duo/:roomId', loadComponent: () => import('./pages/draft-duo/draft-duo.component').then(m => m.DraftDuoComponent), canActivate: [authGuard] },
  { path: 'trainer-select', loadComponent: () => import('./pages/trainer-select/trainer-select.component').then(m => m.TrainerSelectComponent), canActivate: [authGuard] },
  { path: 'draft-trainer/:id', loadComponent: () => import('./pages/draft-trainer/draft-trainer.component').then(m => m.DraftTrainerComponent), canActivate: [authGuard] },
  { path: '**', redirectTo: '/login' }
];
