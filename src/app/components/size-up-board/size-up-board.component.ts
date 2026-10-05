import { AfterViewInit, Component, CUSTOM_ELEMENTS_SCHEMA, ElementRef, OnDestroy, computed, effect, input, output, signal, viewChild } from '@angular/core';
import { ICONS } from '../../constants/icons';
import { Pokemon } from '../../models/pokemon.model';
import { SpriteBounds, measureSpriteBounds } from '../../utils/sprite-bounds';
import { clampSizeUpGuess, formatMeters, metersToSlider, SIZE_UP_SLIDER_STEPS, sliderToMeters } from '../../utils/size-up-utils';

interface Rect {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface BoardLayout {
  groundY: number;
  reference: { image: Rect; box: Rect };
  target: { image: Rect; box: Rect };
  actual: { image: Rect; box: Rect } | null;
  opponent: Rect | null;
}

/** Sensibilité du glisser vertical : 160 px multiplient (ou divisent) l'estimation par e. */
const DRAG_PX_PER_E = 160;
const WHEEL_FACTOR = 0.0015;
const KEY_STEP = 1.02;
const KEY_PAGE_STEP = 1.1;

/**
 * Plateau Size It Up : Pokémon de référence à l'échelle à gauche, Pokémon à estimer à droite.
 * Le joueur ajuste la taille du second (glisser, poignée, molette, pincement, clavier ou slider).
 */
@Component({
  selector: 'app-size-up-board',
  standalone: true,
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './size-up-board.component.html',
  styles: [`
    :host { display: block; }
    .board-anim img, .board-anim .board-box { transition: left 320ms ease, top 320ms ease, width 320ms ease, height 320ms ease; }
    @keyframes outlineIn {
      from { opacity: 0; transform: scale(0.85); }
      to { opacity: 1; transform: scale(1); }
    }
    .outline-in { animation: outlineIn 380ms cubic-bezier(0.34, 1.56, 0.64, 1) both; transform-origin: bottom center; }
    @keyframes ghostIn {
      from { opacity: 0; }
      to { opacity: 0.45; }
    }
    .ghost-in { animation: ghostIn 420ms ease-out both; filter: saturate(0.6); }
  `],
})
export class SizeUpBoardComponent implements AfterViewInit, OnDestroy {
  protected readonly ICONS = ICONS;
  protected readonly sliderSteps = SIZE_UP_SLIDER_STEPS;
  protected readonly formatMeters = formatMeters;

  readonly reference = input.required<Pokemon>();
  readonly target = input.required<Pokemon>();
  readonly guess = input.required<number>();
  readonly locked = input(false);
  readonly revealed = input(false);
  readonly opponentGuess = input<number | null>(null);
  readonly opponentLabel = input('Adversaire');
  /** Affiche les tailles en mètres avant la révélation. */
  readonly showMeters = input(true);
  readonly guessChange = output<number>();

  private readonly board = viewChild.required<ElementRef<HTMLDivElement>>('board');
  protected readonly boardWidth = signal(0);
  protected readonly boardHeight = signal(0);
  protected readonly referenceBounds = signal<SpriteBounds | null>(null);
  protected readonly targetBounds = signal<SpriteBounds | null>(null);
  protected readonly interacting = signal(false);

  private resizeObserver?: ResizeObserver;
  private readonly pointers = new Map<number, { x: number; y: number }>();
  private gestureStartGuess = 0;
  private gestureStartY = 0;
  private gestureStartDistance = 0;

  protected readonly ready = computed(() => !!this.referenceBounds() && !!this.targetBounds() && this.boardHeight() > 0);
  protected readonly sliderValue = computed(() => metersToSlider(this.guess()));

  protected readonly layout = computed<BoardLayout | null>(() => {
    const refBounds = this.referenceBounds();
    const targetBounds = this.targetBounds();
    const width = this.boardWidth();
    const height = this.boardHeight();
    if (!refBounds || !targetBounds || width <= 0 || height <= 0) return null;

    const referenceMeters = this.reference().height;
    const actual = this.revealed() ? this.target().height : null;
    const opponent = this.revealed() ? this.opponentGuess() : null;
    const targetMeters = [this.guess(), actual ?? 0, opponent ?? 0];

    const groundY = height * 0.84;
    const usableHeight = groundY - 34;
    const columnWidth = width * 0.44;
    const referenceCenter = width * 0.27;
    const targetCenter = width * 0.72;

    const tallest = Math.max(referenceMeters, ...targetMeters);
    const scale = Math.min(
      usableHeight / tallest,
      (columnWidth * 0.95) / (referenceMeters * visibleRatio(refBounds)),
      (columnWidth * 0.95) / (Math.max(...targetMeters) * visibleRatio(targetBounds)),
    );

    return {
      groundY,
      reference: placeSprite(refBounds, referenceMeters, scale, referenceCenter, groundY),
      target: placeSprite(targetBounds, this.guess(), scale, targetCenter, groundY),
      actual: actual === null ? null : placeSprite(targetBounds, actual, scale, targetCenter, groundY),
      opponent: opponent === null ? null : placeSprite(targetBounds, opponent, scale, targetCenter, groundY).box,
    };
  });

  constructor() {
    effect(() => {
      const url = this.reference().sprite;
      this.referenceBounds.set(null);
      void measureSpriteBounds(url).then(bounds => {
        if (this.reference().sprite === url) this.referenceBounds.set(bounds);
      });
    });
    effect(() => {
      const url = this.target().sprite;
      this.targetBounds.set(null);
      void measureSpriteBounds(url).then(bounds => {
        if (this.target().sprite === url) this.targetBounds.set(bounds);
      });
    });
  }

  ngAfterViewInit(): void {
    const element = this.board().nativeElement;
    const measure = () => {
      this.boardWidth.set(element.clientWidth);
      this.boardHeight.set(element.clientHeight);
    };
    measure();
    this.resizeObserver = new ResizeObserver(measure);
    this.resizeObserver.observe(element);
  }

  ngOnDestroy(): void {
    this.resizeObserver?.disconnect();
  }

  protected onSliderInput(event: Event): void {
    this.emitGuess(sliderToMeters(Number((event.target as HTMLInputElement).value)));
  }

  protected nudge(factor: number): void {
    this.emitGuess(this.guess() * factor);
  }

  protected onKeydown(event: KeyboardEvent): void {
    const factors: Record<string, number> = {
      ArrowUp: KEY_STEP,
      ArrowRight: KEY_STEP,
      ArrowDown: 1 / KEY_STEP,
      ArrowLeft: 1 / KEY_STEP,
      PageUp: KEY_PAGE_STEP,
      PageDown: 1 / KEY_PAGE_STEP,
    };
    const factor = factors[event.key];
    if (!factor) return;
    event.preventDefault();
    this.nudge(factor);
  }

  protected onWheel(event: WheelEvent): void {
    if (this.locked()) return;
    event.preventDefault();
    this.emitGuess(this.guess() * Math.exp(-event.deltaY * WHEEL_FACTOR));
  }

  /** Un doigt (ou la souris) : glisser vers le haut agrandit. Deux doigts : pincement. */
  protected onPointerDown(event: PointerEvent): void {
    if (this.locked()) return;
    (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
    this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    this.startGesture();
    this.interacting.set(true);
  }

  protected onPointerMove(event: PointerEvent): void {
    if (this.locked() || !this.pointers.has(event.pointerId)) return;
    this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    const points = [...this.pointers.values()];
    if (points.length >= 2) {
      const distance = pointerDistance(points);
      if (this.gestureStartDistance > 0) this.emitGuess(this.gestureStartGuess * (distance / this.gestureStartDistance));
      return;
    }
    const deltaY = points[0].y - this.gestureStartY;
    this.emitGuess(this.gestureStartGuess * Math.exp(-deltaY / DRAG_PX_PER_E));
  }

  protected onPointerUp(event: PointerEvent): void {
    this.pointers.delete(event.pointerId);
    if (this.pointers.size > 0) {
      this.startGesture();
      return;
    }
    this.interacting.set(false);
  }

  private startGesture(): void {
    const points = [...this.pointers.values()];
    this.gestureStartGuess = this.guess();
    this.gestureStartY = points[0]?.y ?? 0;
    this.gestureStartDistance = points.length >= 2 ? pointerDistance(points) : 0;
  }

  private emitGuess(meters: number): void {
    if (this.locked()) return;
    this.guessChange.emit(Math.round(clampSizeUpGuess(meters) * 1000) / 1000);
  }
}

/** Rapport largeur / hauteur de la zone visible d'un sprite. */
function visibleRatio(bounds: SpriteBounds): number {
  return ((bounds.right - bounds.left) / Math.max(0.01, bounds.bottom - bounds.top)) * bounds.aspect;
}

/** Positionne l'image pour que sa zone visible mesure `meters` et repose sur le sol, centrée sur `centerX`. */
function placeSprite(bounds: SpriteBounds, meters: number, scale: number, centerX: number, groundY: number): { image: Rect; box: Rect } {
  const visibleHeight = meters * scale;
  const imageHeight = visibleHeight / Math.max(0.01, bounds.bottom - bounds.top);
  const imageWidth = imageHeight * bounds.aspect;
  const boxWidth = visibleHeight * visibleRatio(bounds);
  return {
    image: {
      left: centerX - ((bounds.left + bounds.right) / 2) * imageWidth,
      top: groundY - bounds.bottom * imageHeight,
      width: imageWidth,
      height: imageHeight,
    },
    box: { left: centerX - boxWidth / 2, top: groundY - visibleHeight, width: boxWidth, height: visibleHeight },
  };
}

function pointerDistance(points: { x: number; y: number }[]): number {
  return Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y);
}
