import { Component, Input, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { NgClass } from '@angular/common';

@Component({
  selector: 'app-mode-select',
  standalone: true,
  imports: [NgClass],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  host: { '[attr.title]': 'null' },
  templateUrl: './mode-select.component.html',
})
export class ModeSelectComponent {
  @Input() title = '';
  @Input() icon = '';
  @Input() iconColor = 'text-white';
  @Input() iconSize = 'text-3xl';
  @Input() maxWidth = 'max-w-2xl';
}
