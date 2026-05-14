import { Component, computed, input, output, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { ICONS } from '../../constants/icons';
import {
  getActiveSettingsCount,
  getSettingsDefinition,
  ModeSettings,
  SettingsControl,
  SettingsMode,
  WhoInitialHint,
} from '../../models/game-settings.model';
import { FirstPlayer } from '../../models/room.model';

@Component({
  selector: 'app-game-settings-panel',
  standalone: true,
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './game-settings-panel.component.html',
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
    { value: 'pokedex_number', label: 'Numéro', icon: ICONS.pokedex },
    { value: 'description', label: 'Description', icon: ICONS.rules },
  ];

  protected readonly definition = computed(() => getSettingsDefinition(this.mode()));
  readonly activeCount = computed(() => getActiveSettingsCount(this.mode(), this.settings()));

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

  protected selectAllGenerations(): void {
    this.update({ generations: [...this.ALL_GENERATIONS] });
  }

  protected clearAllGenerations(): void {
    this.update({ generations: [1] });
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

  protected selectAllCategories(): void {
    this.update({ categories: [...this.ALL_CATEGORIES] });
  }

  protected clearAllCategories(): void {
    this.update({ categories: ['classique'] });
  }

  protected setFirstPlayer(firstPlayer: FirstPlayer): void {
    this.update({ firstPlayer });
  }

  protected setInitialHint(initialHint: WhoInitialHint): void {
    this.update({ initialHint });
  }
}
