import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map, take } from 'rxjs/operators';
import { SupabaseService } from '../services/supabase.service';

/**
 * Guard de navigation : redirige vers `/login` si l'utilisateur n'est pas connecté,
 * en conservant l'URL de destination dans le paramètre `redirect`.
 */
export const authGuard: CanActivateFn = (_route, state) => {
  const supabaseService = inject(SupabaseService);
  const router = inject(Router);

  return supabaseService.authReady$.pipe(
    take(1),
    map(user => {
      if (user) return true;
      // Sauvegarder l'URL de destination pour rediriger après login
      return router.createUrlTree(['/login'], {
        queryParams: { redirect: state.url }
      });
    })
  );
};
