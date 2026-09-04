import { Component, input, output, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { NgClass } from '@angular/common';
import { ICONS } from '../../constants/icons';
import { modalAnimation } from '../../constants/animations';

import { HelpSectionTitleComponent } from './help-section-title.component';
import { HelpCardComponent } from './help-card.component';

@Component({
	selector: 'app-help-modal',
	standalone: true,
	schemas: [CUSTOM_ELEMENTS_SCHEMA],
	animations: [modalAnimation],
	imports: [NgClass, HelpSectionTitleComponent, HelpCardComponent],
	templateUrl: './help-modal.component.html',
})
export class HelpModalComponent {
	mode = input<'guess' | 'stat-duel' | 'auction'>('guess');
	showFilters = input<boolean>(true);
	close = output<void>();

	protected readonly ICONS = ICONS;
}
