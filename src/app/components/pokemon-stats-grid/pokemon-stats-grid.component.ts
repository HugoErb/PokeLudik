import { Component, input } from '@angular/core';
import { NgClass } from '@angular/common';
import { Pokemon } from '../../models/pokemon.model';

type StatKey = keyof Pokemon['stats'];

@Component({
  selector: 'app-pokemon-stats-grid',
  standalone: true,
  imports: [NgClass],
  templateUrl: './pokemon-stats-grid.component.html',
})
export class PokemonStatsGridComponent {
  pokemon = input.required<Pokemon>();
  highlightHighest = input(true);

  protected readonly stats: { key: StatKey; label: string; color: string }[] = [
    { key: 'pv', label: 'PV', color: 'text-green-400' },
    { key: 'attaque', label: 'ATQ', color: 'text-red-400' },
    { key: 'defense', label: 'DEF', color: 'text-blue-400' },
    { key: 'atq_spe', label: 'ATQ S', color: 'text-purple-400' },
    { key: 'def_spe', label: 'DEF S', color: 'text-pink-400' },
    { key: 'vitesse', label: 'VIT', color: 'text-yellow-400' },
  ];

  protected isHighest(key: StatKey): boolean {
    return this.pokemon().stats[key] === Math.max(...Object.values(this.pokemon().stats));
  }
}
