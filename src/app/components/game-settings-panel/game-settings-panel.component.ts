import { Component, computed, input, output, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { ICONS } from '../../constants/icons';
import {
  getSettingsDefinition,
  ModeSettings,
  SettingsControl,
  SettingsMode,
  WhoInitialHint,
} from '../../models/game-settings.model';
import { FirstPlayer } from '../../models/room.model';
import { AuctionFormat } from '../../models/room.model';
import { normalizeAuctionBudget } from '../../utils/auction-utils';

@Component({
  selector: 'app-game-settings-panel',
  standalone: true,
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './game-settings-panel.component.html',
  styles: [`
    :host button:disabled,
    :host input:disabled {
      cursor: not-allowed;
    }
  `],
})
export class GameSettingsPanelComponent {
  mode = input.required<SettingsMode>();
  settings = input.required<ModeSettings>();
  readonly = input(false);
  compact = input(false);
  settingsChange = output<ModeSettings>();

  protected readonly ICONS = ICONS;
  protected readonly ALL_GENERATIONS = [1, 2, 3, 4, 5, 6, 7, 8, 9];
  protected readonly ALL_CATEGORIES = [
    'classique', 'starter', 'légendaire', 'fabuleux', 'fossile',
    'ultra-chimère', 'pseudo-légendaire', 'bébé', 'paradoxe',
  ];
  protected readonly CATEGORY_LABELS: Record<string, string> = {
    classique: 'Classique',
    starter: 'Starter',
    légendaire: 'Légendaire',
    fabuleux: 'Fabuleux',
    fossile: 'Fossile',
    'ultra-chimère': 'Ultra-Chimère',
    'pseudo-légendaire': 'Pseudo-Lég.',
    bébé: 'Bébé',
    paradoxe: 'Paradoxe',
  };
  protected readonly firstPlayerOptions: { value: FirstPlayer; label: string }[] = [
    { value: 'random', label: 'Aléatoire' },
    { value: 'player1', label: 'Vous' },
    { value: 'player2', label: 'Adversaire' },
  ];
  protected readonly hintModes: { value: WhoInitialHint; label: string; icon: string }[] = [
    { value: 'silhouette', label: 'Silhouette', icon: ICONS.whoPokemon },
    { value: 'cry', label: 'Cri', icon: ICONS.sound },
    { value: 'pokedex_number', label: 'Numéro de Pokédex', icon: ICONS.pokedex },
    { value: 'description', label: 'Description', icon: ICONS.rules },
    { value: 'random', label: 'Aléatoire', icon: ICONS.dice },
  ];
  protected readonly auctionFormats: { value: AuctionFormat; label: string; description: string }[] = [
    { value: 'live', label: 'En direct', description: 'Offres visibles et chrono prolongé.' },
    { value: 'sealed', label: 'Secrètes', description: 'Une offre cachée et définitive.' },
    { value: 'turn_based', label: 'Tours alternés', description: 'Miser ou passer chacun son tour.' },
  ];

  protected readonly definition = computed(() => getSettingsDefinition(this.mode()));

  protected generationSelectionLabel(): string {
    const count = this.settings().generations.length;
    return count === 0 ? 'Toutes' : `${count} sélectionnée${count > 1 ? 's' : ''}`;
  }

  protected categorySelectionLabel(): string {
    const count = this.settings().categories.length;
    return count === 0 ? 'Toutes' : `${count} sélectionnée${count > 1 ? 's' : ''}`;
  }

  protected hasControl(control: SettingsControl): boolean {
    return this.definition().controls.includes(control);
  }

  protected update(patch: Partial<ModeSettings>): void {
    if (this.readonly()) return;
    this.settingsChange.emit({ ...this.settings(), ...patch });
  }

  protected toggleGenMode(): void {
    const generations = this.settings().generations.length > 0 ? [] : [1];
    this.update({ generations });
  }

  protected toggleGeneration(gen: number): void {
    const current = this.settings().generations;
    const filtered = current.filter((g) => g !== gen);
    const generations = current.includes(gen) ? (filtered.length === 0 ? [gen] : filtered) : [...current, gen].sort();
    this.update({ generations });
  }

  protected toggleCategoryMode(): void {
    const categories = this.settings().categories.length > 0 ? [] : ['classique'];
    this.update({ categories });
  }

  protected toggleCategory(category: string): void {
    const current = this.settings().categories;
    const filtered = current.filter((c) => c !== category);
    const categories = current.includes(category) ? (filtered.length === 0 ? [category] : filtered) : [...current, category];
    this.update({ categories });
  }

  protected setFirstPlayer(firstPlayer: FirstPlayer): void {
    this.update({ firstPlayer });
  }

  protected setInitialHint(initialHint: WhoInitialHint): void {
    this.update({ initialHint });
  }

  protected setAuctionFormat(auctionFormat: AuctionFormat): void {
    this.update({ auctionFormat });
  }

  protected setStartingBudget(event: Event): void {
    const value = Number((event.target as HTMLInputElement).value);
    this.update({ startingBudget: normalizeAuctionBudget(value) });
  }
}
