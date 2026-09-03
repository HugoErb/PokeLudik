import { Component, inject, OnInit, OnDestroy, CUSTOM_ELEMENTS_SCHEMA, signal } from '@angular/core';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators, AbstractControl, ValidationErrors } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { SupabaseService } from '../../services/supabase.service';
import { Subscription } from 'rxjs';
import { ICONS } from '../../constants/icons';

/** Validateur de formulaire : vérifie que les champs `password` et `confirmPassword` sont identiques. */
function passwordMatchValidator(group: AbstractControl): ValidationErrors | null {
  const password = group.get('password')?.value;
  const confirmPassword = group.get('confirmPassword')?.value;
  return password === confirmPassword ? null : { passwordMismatch: true };
}

@Component({
  selector: 'app-reset-password',
  imports: [ReactiveFormsModule, RouterLink],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './reset-password.component.html',
})
export class ResetPasswordComponent implements OnInit, OnDestroy {
  protected readonly ICONS = ICONS;
  resetForm: FormGroup;
  errorMessage = '';
  infoMessage = '';
  isLoading = false;
  isReady = false; // true quand Supabase a établi la session PASSWORD_RECOVERY
  showPassword = signal(false);
  showConfirmPassword = signal(false);

  private readonly supabaseService = inject(SupabaseService);
  private readonly router = inject(Router);
  private readonly fb = inject(FormBuilder);
  private authSub: Subscription | null = null;
  private timeoutId: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    this.resetForm = this.fb.group(
      {
        password: ['', [Validators.required, Validators.minLength(6)]],
        confirmPassword: ['', [Validators.required]],
      },
      { validators: passwordMatchValidator }
    );
  }

  /** Bascule la visibilité du nouveau mot de passe. */
  togglePassword(): void { this.showPassword.update(value => !value); }

  /** Bascule la visibilité de la confirmation. */
  toggleConfirmPassword(): void { this.showConfirmPassword.update(value => !value); }

  /**
   * Lifecycle Angular — s'abonne aux changements d'état d'authentification
   * et démarre un timeout de sécurité de 5 secondes pour détecter les liens invalides.
   */
  ngOnInit(): void {
    // Supabase émet PASSWORD_RECOVERY quand le lien email est valide
    this.authSub = this.supabaseService.passwordRecoveryReady$.subscribe(isRecovery => {
      if (isRecovery) {
        this.isReady = true;
        if (this.timeoutId !== null) clearTimeout(this.timeoutId);
      }
    });

    // Timeout de sécurité : si pas de session après 5s, lien invalide
    this.timeoutId = setTimeout(() => {
      if (!this.isReady) {
        this.errorMessage = 'Lien invalide ou expiré. Demande un nouveau lien depuis la page de connexion.';
      }
    }, 5000);
  }

  /** Lifecycle Angular — nettoie l'abonnement et le timeout. */
  ngOnDestroy(): void {
    this.authSub?.unsubscribe();
    if (this.timeoutId !== null) clearTimeout(this.timeoutId);
  }

  /** Soumet le formulaire de réinitialisation et redirige vers la connexion en cas de succès. */
  async onSubmit(): Promise<void> {
    if (this.resetForm.invalid || !this.isReady) return;
    this.isLoading = true;
    this.errorMessage = '';

    const { password } = this.resetForm.value;
    try {
      await this.supabaseService.updatePassword(password);
      this.infoMessage = 'Mot de passe mis à jour avec succès !';
      await this.supabaseService.signOut();
      setTimeout(() => this.router.navigateByUrl('/login'), 2000);
    } catch (err: unknown) {
      this.errorMessage = err instanceof Error ? err.message : 'Une erreur est survenue.';
    } finally {
      this.isLoading = false;
    }
  }
}
