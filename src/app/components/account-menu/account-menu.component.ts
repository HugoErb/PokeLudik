import { Component, CUSTOM_ELEMENTS_SCHEMA, input, output, signal } from '@angular/core';
import { ICONS } from '../../constants/icons';

@Component({
  selector: 'app-account-menu',
  standalone: true,
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  host: { class: 'relative block' },
  templateUrl: './account-menu.component.html',
})
export class AccountMenuComponent {
  username = input('');
  avatarUrl = input<string | null>(null);
  isUpdatingAvatar = input(false);

  avatarSelected = output<Event>();
  editUsername = output<void>();
  editPassword = output<void>();
  logoutRequested = output<void>();

  protected readonly ICONS = ICONS;
  protected readonly isOpen = signal(false);

  protected toggle(): void {
    this.isOpen.update(value => !value);
  }

  protected close(): void {
    this.isOpen.set(false);
  }

  protected onAvatarSelected(event: Event): void {
    this.avatarSelected.emit(event);
    this.close();
  }

  protected requestUsernameEdit(): void {
    this.close();
    this.editUsername.emit();
  }

  protected requestPasswordEdit(): void {
    this.close();
    this.editPassword.emit();
  }

  protected requestLogout(): void {
    this.close();
    this.logoutRequested.emit();
  }
}
