import { ComponentFixture, TestBed } from '@angular/core/testing';
import { TYPE_ICON_PATHS } from '../../constants/type-chart';
import { PokemonTypeIconComponent } from './pokemon-type-icon.component';

describe('PokemonTypeIconComponent', () => {
  let fixture: ComponentFixture<PokemonTypeIconComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [PokemonTypeIconComponent],
    }).compileComponents();

    fixture = TestBed.createComponent(PokemonTypeIconComponent);
  });

  it('maps all 18 Pokemon types to a local Scarlet/Violet asset', () => {
    expect(TYPE_ICON_PATHS).toEqual({
      Normal: 'assets/type-icons/scarlet-violet/outlined/1.png',
      Combat: 'assets/type-icons/scarlet-violet/outlined/2.png',
      Vol: 'assets/type-icons/scarlet-violet/outlined/3.png',
      Poison: 'assets/type-icons/scarlet-violet/outlined/4.png',
      Sol: 'assets/type-icons/scarlet-violet/outlined/5.png',
      Roche: 'assets/type-icons/scarlet-violet/outlined/6.png',
      Insecte: 'assets/type-icons/scarlet-violet/outlined/7.png',
      Spectre: 'assets/type-icons/scarlet-violet/outlined/8.png',
      Acier: 'assets/type-icons/scarlet-violet/outlined/9.png',
      Feu: 'assets/type-icons/scarlet-violet/outlined/10.png',
      Eau: 'assets/type-icons/scarlet-violet/outlined/11.png',
      Plante: 'assets/type-icons/scarlet-violet/outlined/12.png',
      'Électrik': 'assets/type-icons/scarlet-violet/outlined/13.png',
      Psy: 'assets/type-icons/scarlet-violet/outlined/14.png',
      Glace: 'assets/type-icons/scarlet-violet/outlined/15.png',
      Dragon: 'assets/type-icons/scarlet-violet/outlined/16.png',
      'Ténèbres': 'assets/type-icons/scarlet-violet/outlined/17.png',
      'Fée': 'assets/type-icons/scarlet-violet/outlined/18.png',
    });
  });

  it('renders the requested type with the default size', () => {
    fixture.componentRef.setInput('type', 'Feu');
    fixture.detectChanges();

    const image: HTMLImageElement = fixture.nativeElement.querySelector('img');
    expect(image.getAttribute('src')).toBe('assets/type-icons/scarlet-violet/outlined/10.png');
    expect(image.classList).toContain('h-[18px]');
    expect(image.classList).toContain('w-[18px]');
    expect(image.alt).toBe('');
    expect(image.getAttribute('aria-hidden')).toBe('true');
  });

  it('renders the compact size', () => {
    fixture.componentRef.setInput('type', 'Eau');
    fixture.componentRef.setInput('size', 'compact');
    fixture.detectChanges();

    const image: HTMLImageElement = fixture.nativeElement.querySelector('img');
    expect(image.classList).toContain('h-[11px]');
    expect(image.classList).toContain('w-[11px]');
  });

  it('falls back to the Normal icon for an unknown type', () => {
    fixture.componentRef.setInput('type', 'Inconnu');
    fixture.detectChanges();

    const image: HTMLImageElement = fixture.nativeElement.querySelector('img');
    expect(image.getAttribute('src')).toBe('assets/type-icons/scarlet-violet/outlined/1.png');
  });
});
