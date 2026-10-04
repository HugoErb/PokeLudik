import { Component, CUSTOM_ELEMENTS_SCHEMA, OnInit, computed, inject, input, output, signal } from '@angular/core';
import { NgTemplateOutlet } from '@angular/common';
import { toSignal } from '@angular/core/rxjs-interop';
import { map } from 'rxjs/operators';
import { ICONS } from '../../constants/icons';
import { modalAnimation } from '../../constants/animations';
import { SupabaseService } from '../../services/supabase.service';
import { PokemonService } from '../../services/pokemon.service';
import { Pokemon } from '../../models/pokemon.model';
import {
  LeaderboardCategory,
  LeaderboardEntry,
  LeaderboardPeriod,
  LeaderboardView,
  PersonalLeaderboard,
  SoloLeaderboardMode,
  TRAINERS_DEFEATED_KEY,
} from '../../models/leaderboard.model';
import {
  SOLO_LEADERBOARD_MODES,
  defaultSettingsKey,
  formatCategoryLabel,
  formatLeaderboardScore,
} from '../../utils/leaderboard-utils';

interface CategoryOption {
  key: string;
  label: string;
  players: number;
}

@Component({
  selector: 'app-leaderboard-modal',
  standalone: true,
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  animations: [modalAnimation],
  imports: [NgTemplateOutlet],
  templateUrl: './leaderboard-modal.component.html',
})
export class LeaderboardModalComponent implements OnInit {
  initialMode = input<SoloLeaderboardMode>('stat_duel');
  /** Catégorie à afficher à l'ouverture (celle de la partie qui vient d'être jouée). */
  initialSettingsKey = input<string | null>(null);
  close = output<void>();

  private readonly supabaseService = inject(SupabaseService);
  private readonly pokemonById = toSignal(
    inject(PokemonService).loadAll().pipe(map(all => new Map(all.map(pokemon => [pokemon.id, pokemon])))),
    { initialValue: new Map<number, Pokemon>() },
  );

  protected readonly ICONS = ICONS;
  protected readonly MODES = SOLO_LEADERBOARD_MODES;

  protected readonly view = signal<LeaderboardView>('global');
  protected readonly mode = signal<SoloLeaderboardMode>('stat_duel');
  protected readonly period = signal<LeaderboardPeriod>('all');
  protected readonly settingsKey = signal('');
  protected readonly categories = signal<LeaderboardCategory[]>([]);
  protected readonly entries = signal<LeaderboardEntry[]>([]);
  protected readonly personal = signal<PersonalLeaderboard | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal('');
  private readonly trainerNames = signal<string[]>([]);
  private requestId = 0;

  protected readonly modeIndex = computed(() => this.MODES.findIndex(m => m.mode === this.mode()));
  protected readonly modeLabel = computed(() => this.MODES[this.modeIndex()]?.label ?? '');
  /** Les modes draft affichent l'équipe de chaque partie. */
  protected readonly showsTeams = computed(() => this.mode() === 'draft' || this.mode() === 'draft_trainer');
  protected readonly isTrainersDefeated = computed(() => this.settingsKey() === TRAINERS_DEFEATED_KEY);
  /** Ligne du joueur affichée à part lorsqu'il est hors du top. */
  protected readonly myDetachedEntry = computed(() => {
    const entries = this.entries();
    const mine = entries.find(entry => entry.is_me);
    return mine && entries.indexOf(mine) >= 50 ? mine : null;
  });
  protected readonly listedEntries = computed(() => {
    const detached = this.myDetachedEntry();
    return detached ? this.entries().filter(entry => entry !== detached) : this.entries();
  });

  protected readonly categoryOptions = computed<CategoryOption[]>(() => {
    const mode = this.mode();
    const names = this.trainerNames();
    const options = new Map<string, CategoryOption>();
    const add = (key: string, settings: LeaderboardCategory['settings'], players: number) =>
      options.set(key, { key, label: formatCategoryLabel(mode, key, settings, names), players });

    // Catégorie par défaut toujours proposée en premier, même si personne n'y a encore joué.
    add(this.defaultKey(mode), {}, 0);
    for (const category of this.categories()) {
      add(category.settings_key, category.settings, category.players);
    }
    const selected = this.settingsKey();
    if (!options.has(selected)) add(selected, {}, 0);
    return [...options.values()];
  });

  ngOnInit(): void {
    this.mode.set(this.initialMode());
    this.settingsKey.set(this.initialSettingsKey() ?? this.defaultKey(this.initialMode()));
    void this.loadTrainerNames();
    void this.reloadAll();
  }

  protected setView(view: LeaderboardView): void {
    if (view === this.view()) return;
    this.view.set(view);
    void this.loadEntries();
  }

  protected setMode(mode: SoloLeaderboardMode): void {
    if (mode === this.mode()) return;
    this.mode.set(mode);
    this.settingsKey.set(this.defaultKey(mode));
    this.categories.set([]);
    void this.reloadAll();
  }

  protected setPeriod(period: LeaderboardPeriod): void {
    if (period === this.period()) return;
    this.period.set(period);
    void this.reloadAll();
  }

  protected setCategory(event: Event): void {
    this.settingsKey.set((event.target as HTMLSelectElement).value);
    void this.loadEntries();
  }

  protected formatScore(score: number): string {
    return formatLeaderboardScore(this.mode(), this.settingsKey(), score);
  }

  /** Score d'une partie personnelle : dans « Dresseurs battus », c'est la note du match gagné. */
  protected formatPersonalScore(score: number): string {
    return formatLeaderboardScore(this.mode(), this.isTrainersDefeated() ? 'trainer' : this.settingsKey(), score);
  }

  /** Date courte en français, sans DatePipe pour ne pas alourdir le bundle initial. */
  protected formatDate(iso: string, withTime: boolean): string {
    const date = new Date(iso);
    const day = date.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' });
    return withTime ? `${day} à ${date.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}` : day;
  }

  protected trainerLabel(settingsKey: string): string {
    return formatCategoryLabel('draft_trainer', settingsKey, {}, this.trainerNames());
  }

  protected teamPokemons(team: number[] | null): Pokemon[] {
    const byId = this.pokemonById();
    return (team ?? []).map(id => byId.get(id)).filter((pokemon): pokemon is Pokemon => !!pokemon);
  }

  protected playersLabel(option: CategoryOption): string {
    if (option.players <= 0) return option.label;
    return `${option.label} (${option.players} joueur${option.players > 1 ? 's' : ''})`;
  }

  protected rankClass(rank: number): string {
    if (rank === 1) return 'border-yellow-300/40 bg-yellow-400/15 text-yellow-200';
    if (rank === 2) return 'border-slate-200/30 bg-slate-200/10 text-slate-100';
    if (rank === 3) return 'border-orange-400/35 bg-orange-500/15 text-orange-200';
    return 'border-white/[0.06] bg-white/[0.03] text-slate-400';
  }

  private defaultKey(mode: SoloLeaderboardMode): string {
    return mode === 'draft_trainer' ? TRAINERS_DEFEATED_KEY : defaultSettingsKey(mode);
  }

  private async reloadAll(): Promise<void> {
    const mode = this.mode();
    const period = this.period();
    void this.loadEntries();
    try {
      const categories = await this.supabaseService.getSoloLeaderboardCategories(mode, period);
      if (mode === this.mode() && period === this.period()) this.categories.set(categories);
    } catch (err) {
      console.error('[Leaderboard] Catégories indisponibles', err);
    }
  }

  private async loadEntries(): Promise<void> {
    const id = ++this.requestId;
    const view = this.view();
    this.loading.set(true);
    this.error.set('');
    try {
      if (view === 'global') {
        const entries = await this.supabaseService.getSoloLeaderboard(this.mode(), this.settingsKey(), this.period());
        if (id === this.requestId) this.entries.set(entries);
      } else {
        const personal = await this.supabaseService.getMySoloScores(this.mode(), this.settingsKey(), this.period());
        if (id === this.requestId) this.personal.set(personal);
      }
    } catch (err) {
      if (id !== this.requestId) return;
      console.error('[Leaderboard] Classement indisponible', err);
      this.entries.set([]);
      this.personal.set(null);
      this.error.set('Impossible de charger le classement pour le moment.');
    } finally {
      if (id === this.requestId) this.loading.set(false);
    }
  }

  private async loadTrainerNames(): Promise<void> {
    try {
      const res = await fetch('/assets/trainers.json');
      const trainers = await res.json() as { nom: string }[];
      this.trainerNames.set(trainers.map(trainer => trainer.nom));
    } catch {
      this.trainerNames.set([]);
    }
  }
}
