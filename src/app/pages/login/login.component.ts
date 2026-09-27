import { Component, inject, CUSTOM_ELEMENTS_SCHEMA, signal } from '@angular/core';
import { NgClass } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators, AbstractControl, ValidationErrors } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { SupabaseService } from '../../services/supabase.service';
import { ICONS } from '../../constants/icons';

/** Validateur de formulaire : vérifie que les champs `password` et `confirmPassword` sont identiques. */
function passwordMatchValidator(group: AbstractControl): ValidationErrors | null {
  const password = group.get('password')?.value;
  const confirmPassword = group.get('confirmPassword')?.value;
  return password === confirmPassword ? null : { passwordMismatch: true };
}

@Component({
  selector: 'app-login',
  imports: [NgClass, ReactiveFormsModule],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './login.component.html',
  styles: [':host .auth-label { font-size: 0.875rem; }'],
})
export class LoginComponent {
  protected readonly ICONS = ICONS;
  mode: 'login' | 'register' | 'forgot' = 'login';
  errorMessage = '';
  infoMessage = '';
  isLoading = false;

  showLoginPassword = signal(false);
  showRegisterPassword = signal(false);
  showRegisterConfirmPassword = signal(false);

  /** Bascule la visibilité du mot de passe sur le formulaire de connexion. */
  toggleLoginPassword(): void { this.showLoginPassword.update(v => !v); }
  /** Bascule la visibilité du mot de passe sur le formulaire d'inscription. */
  toggleRegisterPassword(): void { this.showRegisterPassword.update(v => !v); }
  /** Bascule la visibilité de la confirmation du mot de passe sur le formulaire d'inscription. */
  toggleRegisterConfirmPassword(): void { this.showRegisterConfirmPassword.update(v => !v); }

  loginForm: FormGroup;
  registerForm: FormGroup;
  forgotForm: FormGroup;

  private readonly supabaseService = inject(SupabaseService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly fb = inject(FormBuilder);

  constructor() {
    this.loginForm = this.fb.group({
      email: ['', [Validators.required, Validators.email]],
      password: ['', [Validators.required]],
    });

    this.registerForm = this.fb.group(
      {
        email: ['', [Validators.required, Validators.email]],
        username: ['', [Validators.required, Validators.minLength(3)]],
        password: ['', [Validators.required, Validators.minLength(6)]],
        confirmPassword: ['', [Validators.required]],
      },
      { validators: passwordMatchValidator }
    );

    this.forgotForm = this.fb.group({
      email: ['', [Validators.required, Validators.email]],
    });
  }

  /** Bascule entre les modes connexion, inscription et mot de passe oublié. */
  setMode(mode: 'login' | 'register' | 'forgot'): void {
    this.mode = mode;
    this.errorMessage = '';
    this.infoMessage = '';
  }

  /** Soumet le formulaire de connexion et redirige vers l'URL d'origine ou l'accueil. */
  async onLogin(): Promise<void> {
    if (this.loginForm.invalid) return;
    this.isLoading = true;
    this.errorMessage = '';

    const { email, password } = this.loginForm.value;
    try {
      await this.supabaseService.signIn(email, password);
      const rawRedirect = this.route.snapshot.queryParams['redirect'];
      const redirect = (rawRedirect?.startsWith('/') && !rawRedirect.startsWith('//')) ? rawRedirect : '/home';
      this.router.navigateByUrl(redirect);
    } catch (err: unknown) {
      this.errorMessage = err instanceof Error ? err.message : 'Une erreur est survenue.';
    } finally {
      this.isLoading = false;
    }
  }

  /** Soumet le formulaire d'inscription et redirige ou affiche le message de confirmation email. */
  async onRegister(): Promise<void> {
    if (this.registerForm.invalid) return;
    this.isLoading = true;
    this.errorMessage = '';

    const { email, username, password } = this.registerForm.value;
    try {
      await this.supabaseService.signUp(email, password, username);
      const rawRedirect = this.route.snapshot.queryParams['redirect'];
      const redirect = (rawRedirect?.startsWith('/') && !rawRedirect.startsWith('//')) ? rawRedirect : '/home';
      this.router.navigateByUrl(redirect);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : (err as any)?.message ?? 'Une erreur est survenue.';
      if (message.startsWith('Un email de confirmation')) {
        this.infoMessage = message;
      } else {
        this.errorMessage = message;
      }
    } finally {
      this.isLoading = false;
    }
  }

  /** Envoie un email de réinitialisation du mot de passe à l'adresse saisie. */
  async onForgotPassword(): Promise<void> {
    if (this.forgotForm.invalid) return;
    this.isLoading = true;
    this.errorMessage = '';

    const { email } = this.forgotForm.value;
    try {
      await this.supabaseService.resetPasswordForEmail(email);
      this.infoMessage = `Un lien de réinitialisation a été envoyé à ${email}. Vérifie ta boîte mail.`;
      this.forgotForm.reset();
    } catch (err: unknown) {
      this.errorMessage = err instanceof Error ? err.message : 'Une erreur est survenue.';
    } finally {
      this.isLoading = false;
    }
  }
}
