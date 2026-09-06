import { inject, Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { catchError, map, shareReplay } from 'rxjs/operators';
import { Observable, of } from 'rxjs';
import { Pokemon } from '../models/pokemon.model';

@Injectable({ providedIn: 'root' })
export class PokemonService {
  private http = inject(HttpClient);

  /** Cache partagé : le fichier JSON n'est chargé qu'une seule fois. */
  private all$: Observable<Pokemon[]> = this.http
    .get<Pokemon[]>('/assets/pokemon.json')
    .pipe(
      catchError(() => of([])),
      shareReplay(1)
    );

  // ─── API publique ────────────────────────────────────────────────────────────

  /** Retourne tous les Pokémon disponibles depuis le cache partagé. */
  loadAll(): Observable<Pokemon[]> {
    return this.all$;
  }

  /** Retourne un Pokémon par son identifiant, ou `undefined` s'il n'existe pas. */
  getById(id: number): Observable<Pokemon | undefined> {
    return this.all$.pipe(
      map(pokemons => pokemons.find(p => p.id === id))
    );
  }
}
