import { Component, Input, Output, EventEmitter, CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { NgClass } from '@angular/common';
import { ICONS } from '../../constants/icons';

type Accent = 'purple' | 'green' | 'yellow' | 'blue' | 'red';

const ACCENT_CLASSES: Record<Accent, {
  border: string; shadow: string; bg: string; selected: string;
  iconBorder: string; iconBgHover: string; text: string; glow: string; pill: string;
}> = {
  purple: { border: 'group-hover/mode-card:border-purple-400/60', shadow: 'group-hover/mode-card:shadow-purple-950/40', bg: 'bg-purple-500/10', selected: '!border-purple-400/70 ring-1 ring-purple-400/30', iconBorder: 'border-purple-400/20', iconBgHover: 'group-hover/mode-card:bg-purple-500/15', text: 'text-purple-300', glow: 'bg-purple-500/15', pill: 'bg-purple-400' },
  green:  { border: 'group-hover/mode-card:border-emerald-400/60', shadow: 'group-hover/mode-card:shadow-emerald-950/40', bg: 'bg-emerald-500/10', selected: '!border-emerald-400/70 ring-1 ring-emerald-400/30', iconBorder: 'border-emerald-400/20', iconBgHover: 'group-hover/mode-card:bg-emerald-500/15', text: 'text-emerald-300', glow: 'bg-emerald-500/15', pill: 'bg-emerald-400' },
  yellow: { border: 'group-hover/mode-card:border-amber-400/60', shadow: 'group-hover/mode-card:shadow-amber-950/40', bg: 'bg-amber-500/10', selected: '!border-amber-400/70 ring-1 ring-amber-400/30', iconBorder: 'border-amber-400/20', iconBgHover: 'group-hover/mode-card:bg-amber-500/15', text: 'text-amber-300', glow: 'bg-amber-500/15', pill: 'bg-amber-400' },
  blue:   { border: 'group-hover/mode-card:border-cyan-400/60', shadow: 'group-hover/mode-card:shadow-cyan-950/40', bg: 'bg-cyan-500/10', selected: '!border-cyan-400/70 ring-1 ring-cyan-400/30', iconBorder: 'border-cyan-400/20', iconBgHover: 'group-hover/mode-card:bg-cyan-500/15', text: 'text-cyan-300', glow: 'bg-cyan-500/15', pill: 'bg-cyan-400' },
  red:    { border: 'group-hover/mode-card:border-rose-400/60', shadow: 'group-hover/mode-card:shadow-rose-950/40', bg: 'bg-rose-500/10', selected: '!border-rose-400/70 ring-1 ring-rose-400/30', iconBorder: 'border-rose-400/20', iconBgHover: 'group-hover/mode-card:bg-rose-500/15', text: 'text-rose-300', glow: 'bg-rose-500/15', pill: 'bg-rose-400' },
};

@Component({
  selector: 'app-mode-select-card',
  standalone: true,
  imports: [NgClass],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  host: { class: 'flex min-w-0 flex-1 basis-0', '[attr.title]': 'null' },
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
