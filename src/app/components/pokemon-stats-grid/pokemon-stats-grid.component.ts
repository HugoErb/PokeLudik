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
  variant = input<'tiles' | 'bars'>('tiles');

  protected readonly stats: { key: StatKey; label: string; color: string; barColor: string }[] = [
    { key: 'pv', label: 'PV', color: 'text-green-400', barColor: 'bg-green-500' },
    { key: 'attaque', label: 'ATQ', color: 'text-red-400', barColor: 'bg-red-500' },
    { key: 'defense', label: 'DEF', color: 'text-blue-400', barColor: 'bg-blue-500' },
    { key: 'atq_spe', label: 'ATQ S', color: 'text-purple-400', barColor: 'bg-purple-500' },
    { key: 'def_spe', label: 'DEF S', color: 'text-pink-400', barColor: 'bg-pink-500' },
    { key: 'vitesse', label: 'VIT', color: 'text-yellow-400', barColor: 'bg-yellow-400' },
  ];

  protected getStatBarWidth(value: number): string {
    return `${Math.min(100, Math.round((value / 200) * 100))}%`;
  }

  protected isHighest(key: StatKey): boolean {
    return this.pokemon().stats[key] === Math.max(...Object.values(this.pokemon().stats));
  }
}
