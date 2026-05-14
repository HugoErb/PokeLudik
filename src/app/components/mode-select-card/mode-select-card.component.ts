import { Component, Input, Output, EventEmitter, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { NgClass } from '@angular/common';
import { ICONS } from '../../constants/icons';

type Accent = 'purple' | 'green' | 'yellow' | 'blue' | 'red';

const ACCENT_CLASSES: Record<Accent, {
  border: string; shadow: string; bg: string; selected: string;
  iconBorder: string; iconBgHover: string; text: string;
}> = {
  purple: { border: 'hover:border-purple-500', shadow: 'hover:shadow-purple-900/30', bg: 'bg-purple-600/20', selected: '!border-purple-500', iconBorder: 'border-purple-500/30', iconBgHover: 'group-hover:bg-purple-600/30', text: 'text-purple-300' },
  green:  { border: 'hover:border-green-500',  shadow: 'hover:shadow-green-900/30',  bg: 'bg-green-600/20',  selected: '!border-green-500', iconBorder: 'border-green-500/30',  iconBgHover: 'group-hover:bg-green-600/30',  text: 'text-green-300'  },
  yellow: { border: 'hover:border-yellow-500', shadow: 'hover:shadow-yellow-900/30', bg: 'bg-yellow-600/20', selected: '!border-yellow-500', iconBorder: 'border-yellow-500/30', iconBgHover: 'group-hover:bg-yellow-600/30', text: 'text-yellow-300' },
  blue:   { border: 'hover:border-blue-500',   shadow: 'hover:shadow-blue-900/30',   bg: 'bg-blue-600/20',   selected: '!border-blue-500', iconBorder: 'border-blue-500/30',   iconBgHover: 'group-hover:bg-blue-600/30',   text: 'text-blue-300'   },
  red:    { border: 'hover:border-red-500',    shadow: 'hover:shadow-red-900/30',    bg: 'bg-red-600/20',    selected: '!border-red-500', iconBorder: 'border-red-500/30',    iconBgHover: 'group-hover:bg-red-600/30',    text: 'text-red-400'    },
};

@Component({
  selector: 'app-mode-select-card',
  standalone: true,
  imports: [NgClass],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  host: { class: 'flex flex-1', '[attr.title]': 'null' },
  templateUrl: './mode-select-card.component.html',
})
export class ModeSelectCardComponent {
  protected readonly ICONS = ICONS;

  @Input({ alias: 'cardTitle' }) title = '';
  @Input() description = '';
  @Input() icon = '';
  @Input() accent: Accent = 'purple';
  @Input() isLoading = false;
  @Input() disabled = false;
  @Input({ alias: 'selected' }) isSelected = false;

  @Output() selected = new EventEmitter<void>();

  /** Retourne les classes CSS d'accentuation de la carte. */
  get accentClasses() {
    return ACCENT_CLASSES[this.accent];
  }
}
