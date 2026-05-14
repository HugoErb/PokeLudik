import { Component, input, output, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { ICONS } from '../../constants/icons';
import { modalAnimation } from '../../constants/animations';
import { GameSettings } from '../../models/room.model';
import { normalizeModeSettings } from '../../models/game-settings.model';
import { GameSettingsPanelComponent } from '../game-settings-panel/game-settings-panel.component';

@Component({
	selector: 'app-game-settings-modal',
	standalone: true,
	imports: [GameSettingsPanelComponent],
	schemas: [CUSTOM_ELEMENTS_SCHEMA],
	animations: [modalAnimation],
	templateUrl: './game-settings-modal.component.html',
})
export class GameSettingsModalComponent {
	settings = input.required<GameSettings>();
	close = output<void>();

	protected readonly ICONS = ICONS;
	protected readonly normalizedSettings = () => normalizeModeSettings('guess_my_pokemon', this.settings());
}
