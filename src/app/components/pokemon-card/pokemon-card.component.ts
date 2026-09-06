import { Component, input } from '@angular/core';
import { NgClass } from '@angular/common';
import { Pokemon } from '../../models/pokemon.model';
import { TYPE_COLORS } from '../../constants/type-chart';
import { PokemonTypeIconComponent } from '../pokemon-type-icon/pokemon-type-icon.component';

@Component({
  selector: 'app-pokemon-card',
  imports: [NgClass, PokemonTypeIconComponent],
  templateUrl: './pokemon-card.component.html',
})
export class PokemonCardComponent {
  readonly pokemon = input.required<Pokemon>();
  readonly variant = input<'modal' | 'sidebar'>('modal');

  /** Retourne la classe CSS Tailwind de couleur de fond pour un type Pokémon donné. */
  getTypeColor(type: string): string {
    return TYPE_COLORS[type] ?? 'bg-gray-500';
  }

  /** Calcule la largeur de la barre de statistique en pourcentage (max = 200 → 100%). */
  getStatWidth(value: number): string {
    return `${Math.min(100, Math.round((value / 200) * 100))}%`;
  }

  /** Retourne le total des statistiques du Pokemon affiche. */
  getTotalStats(stats: Pokemon['stats']): number {
    return stats.pv + stats.attaque + stats.defense + stats.atq_spe + stats.def_spe + stats.vitesse;
  }
}
