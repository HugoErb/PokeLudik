import { Component, computed, input } from '@angular/core';
import { TYPE_ICON_PATHS } from '../../constants/type-chart';

export type PokemonTypeIconSize = 'default' | 'compact';

@Component({
  selector: 'app-pokemon-type-icon',
  styles: `
    img {
      filter: drop-shadow(0 0 0.45px #000) drop-shadow(0 0 0.45px #000);
    }
  `,
  template: `
    <img
      [src]="iconPath()"
      alt=""
      aria-hidden="true"
      [class]="size() === 'compact'
        ? 'h-[11px] w-[11px] shrink-0 rounded-sm object-contain'
        : 'h-[18px] w-[18px] shrink-0 rounded-sm object-contain'"
    />
  `,
})
export class PokemonTypeIconComponent {
  readonly type = input.required<string>();
  readonly size = input<PokemonTypeIconSize>('default');

  protected readonly iconPath = computed(
    () => TYPE_ICON_PATHS[this.type()] ?? TYPE_ICON_PATHS['Normal'],
  );
}
