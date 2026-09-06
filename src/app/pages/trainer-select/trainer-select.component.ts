import { Component, OnInit, inject, signal, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { Router } from '@angular/router';
import { Trainer } from '../draft-trainer/draft-trainer.component';
import { ICONS } from '../../constants/icons';
import { PokemonService } from '../../services/pokemon.service';
import { SupabaseService } from '../../services/supabase.service';
import { toSignal } from '@angular/core/rxjs-interop';
import { NgClass } from '@angular/common';

import { DraftHelpModalComponent } from '../../components/draft-help-modal/draft-help-modal.component';
import { CancelModalComponent } from '../../components/cancel-modal/cancel-modal.component';
import { AppHeaderComponent } from '../../components/app-header/app-header.component';

@Component({
  selector: 'app-trainer-select',
  imports: [NgClass, DraftHelpModalComponent, CancelModalComponent, AppHeaderComponent],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './trainer-select.component.html'
})
export class TrainerSelectComponent implements OnInit {
  protected readonly ICONS = ICONS;
  private readonly router = inject(Router);
  private readonly pokemonService = inject(PokemonService);

  private readonly supabaseService = inject(SupabaseService);

  readonly trainers = signal<Trainer[]>([]);
  readonly defeatedIndices = signal<number[]>([]);
  readonly isLoading = signal(true);
  readonly isResettingProgress = signal(false);
  readonly showResetModal = signal(false);
  readonly showHelpModal = signal(false);
  
  private readonly allPokemon = toSignal(this.pokemonService.loadAll(), {
    initialValue: []
  });

  /** Lifecycle Angular : initialise le composant. */
  async ngOnInit() {
    try {
      const res = await fetch('/assets/trainers.json');
      const data = await res.json() as Trainer[];
      this.trainers.set(data);

      const user = this.supabaseService.getCurrentUser();
      if (user) {
        const defeated = await this.supabaseService.getDefeatedTrainers(user.id);
        this.defeatedIndices.set(defeated);
      }
    } catch {
      // error
    } finally {
      this.isLoading.set(false);
    }
  }

  /** Retourne true si le dresseur est verrouille. */
  isLocked(index: number): boolean {
    if (index === 0) return false;
    // Un dresseur est verrouillé si le précédent n'a pas été battu
    return !this.defeatedIndices().includes(index - 1);
  }

  /** Retourne true si le dresseur a deja ete battu. */
  isDefeated(index: number): boolean {
    return this.defeatedIndices().includes(index);
  }

  /** Retourne l'URL du sprite d'un Pokemon. */
  getPokemonSprite(id: number): string {
    const p = this.allPokemon().find(p => p.id === id);
    return p ? p.sprite : '';
  }

  /** Retourne le nom d'un Pokemon. */
  getPokemonName(id: number): string {
    const p = this.allPokemon().find(p => p.id === id);
    return p ? p.name : 'Inconnu';
  }

  /** Selectionne un dresseur et lance le draft correspondant. */
  async selectTrainer(index: number) {
    if (this.isLocked(index)) return;
    await this.preloadDuelIntro(index);
    void this.router.navigate(['/draft-trainer', index]);
  }

  /** Revient a la page precedente. */
  goBack() {
    void this.router.navigate(['/draft']);
  }

  /** Ouvre la modal de reinitialisation. */
  openResetModal() {
    if (this.isResettingProgress()) return;
    this.showResetModal.set(true);
  }

  /** Ferme la modal de reinitialisation. */
  closeResetModal() {
    if (this.isResettingProgress()) return;
    this.showResetModal.set(false);
  }

  /** Reinitialise la progression des dresseurs. */
  async resetProgress() {
    const user = this.supabaseService.getCurrentUser();
    if (!user || this.isResettingProgress()) return;

    this.isResettingProgress.set(true);
    try {
      await this.supabaseService.resetTrainerProgress(user.id);
      window.location.reload();
    } catch (error) {
      this.isResettingProgress.set(false);
      window.alert(error instanceof Error ? error.message : 'Impossible de réinitialiser la progression.');
    }
  }

  /** Precharge les donnees et images de l'intro de duel. */
  private async preloadDuelIntro(index: number): Promise<void> {
    const trainer = this.trainers()[index];
    if (!trainer) return;

    const user = this.supabaseService.getCurrentUser();
    const profile = user
      ? await this.supabaseService.getProfile(user.id).catch(() => ({ username: 'Moi', avatar_url: undefined }))
      : { username: 'Moi', avatar_url: undefined };

    const players = [
      { username: profile.username, avatar_url: profile.avatar_url },
      { username: trainer.nom, avatar_url: trainer.image },
    ];

    sessionStorage.setItem(`draft-trainer-intro-data-${index}`, JSON.stringify(players));
    await Promise.all(
      players
        .filter(p => p.avatar_url)
        .map(p => new Promise<void>(resolve => {
          const img = new Image();
          img.onload = img.onerror = () => resolve();
          img.src = p.avatar_url!;
        }))
    );
  }
}
