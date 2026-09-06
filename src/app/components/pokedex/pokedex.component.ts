import { Component, OnInit, DestroyRef, inject, input, output, CUSTOM_ELEMENTS_SCHEMA, signal, computed, effect } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';

import { PokemonService } from '../../services/pokemon.service';
import { Pokemon } from '../../models/pokemon.model';
import { PokemonCardComponent } from '../pokemon-card/pokemon-card.component';
import { ICONS } from '../../constants/icons';
import { modalAnimation } from '../../constants/animations';

const ALL_TYPES = [
    'Normal', 'Feu', 'Eau', 'Électrik', 'Plante', 'Glace',
    'Combat', 'Vol', 'Insecte', 'Poison', 'Psy', 'Sol',
    'Roche', 'Spectre', 'Dragon', 'Ténèbres', 'Acier', 'Fée',
];

const TYPE_ICONS: Record<string, string> = {
    'Normal': 'mdi:circle-outline',
    'Feu': 'mdi:fire',
    'Eau': 'mdi:water',
    'Électrik': 'mdi:lightning-bolt',
    'Plante': 'mdi:leaf',
    'Glace': 'mdi:snowflake',
    'Combat': 'fa6-solid:hand-fist',
    'Poison': 'mdi:skull-crossbones',
    'Sol': 'mdi:terrain',
    'Vol': 'game-icons:liberty-wing',
    'Psy': 'mdi:eye',
    'Insecte': 'mdi:bug',
    'Roche': 'mdi:hexagon',
    'Spectre': 'mdi:ghost',
    'Dragon': 'game-icons:sea-dragon',
    'Ténèbres': 'ic:round-dark-mode',
    'Acier': 'mdi:shield',
    'Fée': 'mdi:star-four-points',
};

const TYPE_COLORS: Record<string, string> = {
    'Normal': 'bg-gray-400',
    'Feu': 'bg-orange-500',
    'Eau': 'bg-blue-500',
    'Électrik': 'bg-yellow-400',
    'Plante': 'bg-green-500',
    'Glace': 'bg-cyan-300',
    'Combat': 'bg-red-700',
    'Poison': 'bg-purple-500',
    'Sol': 'bg-yellow-600',
    'Vol': 'bg-indigo-400',
    'Psy': 'bg-pink-500',
    'Insecte': 'bg-lime-500',
    'Roche': 'bg-yellow-700',
    'Spectre': 'bg-purple-700',
    'Dragon': 'bg-indigo-600',
    'Ténèbres': 'bg-gray-700',
    'Acier': 'bg-gray-400',
    'Fée': 'bg-pink-300',
};

const GENERATIONS = [1, 2, 3, 4, 5, 6, 7, 8, 9];

@Component({
    selector: 'app-pokedex',
    imports: [FormsModule, PokemonCardComponent],
    schemas: [CUSTOM_ELEMENTS_SCHEMA],
    animations: [modalAnimation],
    templateUrl: './pokedex.component.html',
})
export class PokedexComponent implements OnInit {
    protected readonly ICONS = ICONS;
    private readonly pokemonService = inject(PokemonService);
    private readonly destroyRef = inject(DestroyRef);

    showGuessButton = input<boolean>(false);
    restrictedGenerations = input<number[]>([]);
    noPokedex = input<boolean>(false);
    noSearch = input<boolean>(false);
    guessedPokemonIds = input<number[]>([]);
    showFilters = input<boolean>(false);
    filtersOnly = input<boolean>(false);
    roomId = input<string | null>(null);
    guess = output<number>();

    private static readonly FILTERS_KEY = 'gmp:filters';
    private static readonly RELOAD_TOKEN_KEY = 'gmp:reload-token';
    /** Retourne la cle de stockage du grisage manuel. */
    private static dimmedKey(id: string) { return `gmp:dimmed:${id}`; }

    allPokemons = signal<Pokemon[]>([]);

    // États des filtres (Signals)
    searchQuery = signal('');
    selectedGenerations = signal<number[]>([...GENERATIONS]);
    selectedTypes = signal<string[]>([...ALL_TYPES]);
    selectedCategories = signal<string[]>(['classique', 'starter', 'légendaire', 'fabuleux', 'fossile', 'ultra-chimère', 'pseudo-légendaire', 'bébé', 'paradoxe']);
    selectedEvoStages = signal<number[]>([1, 2, 3]);
    minWeight = signal<number | null>(0);
    maxWeight = signal<number | null>(null);
    minHeight = signal<number | null>(0);
    maxHeight = signal<number | null>(null);
    showStatsPanel = signal(false);
    showCategoryPanel = signal(false);
    minStatPv      = signal<number | null>(null);
    maxStatPv      = signal<number | null>(null);
    minStatAtq     = signal<number | null>(null);
    maxStatAtq     = signal<number | null>(null);
    minStatDef     = signal<number | null>(null);
    maxStatDef     = signal<number | null>(null);
    minStatAtqSpe  = signal<number | null>(null);
    maxStatAtqSpe  = signal<number | null>(null);
    minStatDefSpe  = signal<number | null>(null);
    maxStatDefSpe  = signal<number | null>(null);
    minStatVit     = signal<number | null>(null);
    maxStatVit     = signal<number | null>(null);
    minStatTotal   = signal<number | null>(null);
    maxStatTotal   = signal<number | null>(null);
    onlyDualType = signal(false);
    onlyDualTypeStrict = signal(false);
    onlyMonoType = signal(false);

    // Grisage manuel
    manuallyDimmedIds = signal<number[]>([]);

    // Pagination (Signal)
    displayedCount = signal(100);
    private readonly PAGE_SIZE = 100;
    private isLoadingMore = false;
    selectedPokemonDetails: Pokemon | null = null;

    // Données constantes
    readonly generations = GENERATIONS;
    readonly desktopTypeFirstRow = ALL_TYPES.slice(0, 9);
    readonly desktopTypeSecondRow = ALL_TYPES.slice(9);
    readonly mobileAllTypes = [
        'Normal', 'Feu', 'Eau', 'Électrik', 'Fée', 'Plante', 'Glace',
        'Combat', 'Vol', 'Insecte', 'Poison', 'Psy', 'Sol',
        'Roche', 'Spectre', 'Dragon', 'Ténèbres', 'Acier',
    ];
    readonly categories = [
        { id: 'classique', label: 'Classique' },
        { id: 'starter', label: 'Starter' },
        { id: 'bébé', label: 'Bébé' },
        { id: 'fossile', label: 'Fossile' },
        { id: 'paradoxe', label: 'Paradoxe' },
        { id: 'ultra-chimère', label: 'Ultra-Chimère' },
        { id: 'pseudo-légendaire', label: 'Pseudo-Légendaire', shortLabel: 'Pseudo-Lég.' },
        { id: 'légendaire', label: 'Légendaire' },
        { id: 'fabuleux', label: 'Fabuleux' },
    ];
    readonly evoStages = [1, 2, 3];

    readonly statFilters = [
        { key: 'pv',     label: 'PV',    min: this.minStatPv,     max: this.maxStatPv },
        { key: 'atq',    label: 'ATQ',   min: this.minStatAtq,    max: this.maxStatAtq },
        { key: 'def',    label: 'DEF',   min: this.minStatDef,    max: this.maxStatDef },
        { key: 'atqSpe', label: 'ATQ S', min: this.minStatAtqSpe, max: this.maxStatAtqSpe },
        { key: 'defSpe', label: 'DEF S', min: this.minStatDefSpe, max: this.maxStatDefSpe },
        { key: 'vit',    label: 'VIT',   min: this.minStatVit,    max: this.maxStatVit },
        { key: 'total',  label: 'TOTAL', min: this.minStatTotal,  max: this.maxStatTotal },
    ];

    hasStatFilter = computed(() =>
        [this.minStatPv(), this.maxStatPv(), this.minStatAtq(), this.maxStatAtq(),
         this.minStatDef(), this.maxStatDef(), this.minStatAtqSpe(), this.maxStatAtqSpe(),
         this.minStatDefSpe(), this.maxStatDefSpe(), this.minStatVit(), this.maxStatVit(),
         this.minStatTotal(), this.maxStatTotal()].some(v => v !== null)
    );

    hasCategoryFilter = computed(() => this.selectedCategories().length !== this.categories.length);
    private readonly selectedGenerationSet = computed(() => new Set(this.selectedGenerations()));
    private readonly selectedTypeSet = computed(() => new Set(this.selectedTypes()));
    private readonly selectedCategorySet = computed(() => new Set(this.selectedCategories()));
    private readonly selectedEvoStageSet = computed(() => new Set(this.selectedEvoStages()));
    private readonly restrictedGenerationSet = computed(() => new Set(this.restrictedGenerations()));
    private readonly guessedPokemonIdSet = computed(() => new Set(this.guessedPokemonIds()));
    private readonly manuallyDimmedIdSet = computed(() => new Set(this.manuallyDimmedIds()));

    // Logic de filtrage réactive (Computed)
    filteredPokemons = computed(() => {
        const list = this.allPokemons();
        const q = this.searchQuery().trim().toLowerCase();
        const restricted = this.restrictedGenerationSet();
        const hasRestrictedGenerations = restricted.size > 0;
        const gens = this.selectedGenerationSet();
        const types = this.selectedTypeSet();
        const cats = this.selectedCategorySet();
        const evos = this.selectedEvoStageSet();
        const isDualOnly = this.onlyDualType();
        const isDualOnlyStrict = this.onlyDualTypeStrict();
        const isMonoOnly = this.onlyMonoType();

        const minW = this.minWeight();
        const maxW = this.maxWeight();
        const minH = this.minHeight();
        const maxH = this.maxHeight();

        const minPv      = this.minStatPv();      const maxPv      = this.maxStatPv();
        const minAtq     = this.minStatAtq();     const maxAtq     = this.maxStatAtq();
        const minDef     = this.minStatDef();     const maxDef     = this.maxStatDef();
        const minAtqSpe  = this.minStatAtqSpe();  const maxAtqSpe  = this.maxStatAtqSpe();
        const minDefSpe  = this.minStatDefSpe();  const maxDefSpe  = this.maxStatDefSpe();
        const minVit     = this.minStatVit();     const maxVit     = this.maxStatVit();
        const minTotal   = this.minStatTotal();   const maxTotal   = this.maxStatTotal();

        return list.filter(p => {
            if (hasRestrictedGenerations && !restricted.has(p.generation)) return false;
            if (q && !p.name.toLowerCase().includes(q)) return false;
            if (!gens.has(p.generation)) return false;

            if ((isDualOnly || isDualOnlyStrict) && p.types.length !== 2) return false;
            if (isMonoOnly && p.types.length !== 1) return false;

            if (isDualOnlyStrict ? !p.types.every(t => types.has(t)) : !p.types.some(t => types.has(t))) return false;

            if (!cats.has(p.category)) return false;
            if (!evos.has(p._stage ?? 1)) return false;

            if (minW !== null && p.weight < minW) return false;
            if (maxW !== null && p.weight > maxW) return false;
            if (minH !== null && p.height < minH) return false;
            if (maxH !== null && p.height > maxH) return false;

            const s = p.stats;
            const total = s.pv + s.attaque + s.defense + s.atq_spe + s.def_spe + s.vitesse;
            if (minPv     !== null && s.pv       < minPv)     return false;
            if (maxPv     !== null && s.pv       > maxPv)     return false;
            if (minAtq    !== null && s.attaque   < minAtq)    return false;
            if (maxAtq    !== null && s.attaque   > maxAtq)    return false;
            if (minDef    !== null && s.defense   < minDef)    return false;
            if (maxDef    !== null && s.defense   > maxDef)    return false;
            if (minAtqSpe !== null && s.atq_spe  < minAtqSpe) return false;
            if (maxAtqSpe !== null && s.atq_spe  > maxAtqSpe) return false;
            if (minDefSpe !== null && s.def_spe  < minDefSpe) return false;
            if (maxDefSpe !== null && s.def_spe  > maxDefSpe) return false;
            if (minVit    !== null && s.vitesse   < minVit)    return false;
            if (maxVit    !== null && s.vitesse   > maxVit)    return false;
            if (minTotal  !== null && total       < minTotal)  return false;
            if (maxTotal  !== null && total       > maxTotal)  return false;

            return true;
        });
    });

    visiblePokemons = computed(() => {
        return this.filteredPokemons().slice(0, this.displayedCount());
    });

    constructor() {
        effect(() => {
            localStorage.setItem(PokedexComponent.FILTERS_KEY, JSON.stringify({
                roomId: this.roomId(),
                selectedTypes: this.selectedTypes(),
                selectedGenerations: this.selectedGenerations(),
                selectedCategories: this.selectedCategories(),
                selectedEvoStages: this.selectedEvoStages(),
                minWeight: this.minWeight(),
                maxWeight: this.maxWeight(),
                minHeight: this.minHeight(),
                maxHeight: this.maxHeight(),
                onlyDualType: this.onlyDualType(),
                onlyDualTypeStrict: this.onlyDualTypeStrict(),
                onlyMonoType: this.onlyMonoType(),
                minStatPv: this.minStatPv(), maxStatPv: this.maxStatPv(),
                minStatAtq: this.minStatAtq(), maxStatAtq: this.maxStatAtq(),
                minStatDef: this.minStatDef(), maxStatDef: this.maxStatDef(),
                minStatAtqSpe: this.minStatAtqSpe(), maxStatAtqSpe: this.maxStatAtqSpe(),
                minStatDefSpe: this.minStatDefSpe(), maxStatDefSpe: this.maxStatDefSpe(),
                minStatVit: this.minStatVit(), maxStatVit: this.maxStatVit(),
                minStatTotal: this.minStatTotal(), maxStatTotal: this.maxStatTotal(),
            }));
        });

        effect(() => {
            const id = this.roomId();
            const dimmed = this.manuallyDimmedIds();
            if (id) localStorage.setItem(PokedexComponent.dimmedKey(id), JSON.stringify(dimmed));
        });
    }

    /** Lifecycle Angular — charge la liste des Pokémon et pré-calcule leur stade d'évolution. */
    ngOnInit(): void {
        const navEntry = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming | undefined;
        const isReload = navEntry?.type === 'reload';
        const reloadToken = Math.floor(performance.timeOrigin).toString();
        const savedToken = sessionStorage.getItem(PokedexComponent.RELOAD_TOKEN_KEY);
        const isFirstInitAfterReload = isReload && savedToken !== reloadToken;

        if (isFirstInitAfterReload) {
            sessionStorage.setItem(PokedexComponent.RELOAD_TOKEN_KEY, reloadToken);
            try {
                const saved = localStorage.getItem(PokedexComponent.FILTERS_KEY);
                if (saved) {
                    const s = JSON.parse(saved);
                    const currentRoomId = this.roomId();
                    // Sur iOS, une navigation vers une nouvelle partie peut être perçue comme un 'reload'.
                    // Si le roomId a changé, on force la réinitialisation plutôt que de restaurer.
                    if (currentRoomId && s.roomId && s.roomId !== currentRoomId) {
                        this.clearFilters();
                    } else {
                    if (Array.isArray(s.selectedTypes))       this.selectedTypes.set(s.selectedTypes);
                    if (Array.isArray(s.selectedGenerations)) this.selectedGenerations.set(s.selectedGenerations);
                    if (Array.isArray(s.selectedCategories))  this.selectedCategories.set(s.selectedCategories);
                    if (Array.isArray(s.selectedEvoStages))   this.selectedEvoStages.set(s.selectedEvoStages);
                    if (s.minWeight      !== undefined) this.minWeight.set(s.minWeight);
                    if (s.maxWeight      !== undefined) this.maxWeight.set(s.maxWeight);
                    if (s.minHeight      !== undefined) this.minHeight.set(s.minHeight);
                    if (s.maxHeight      !== undefined) this.maxHeight.set(s.maxHeight);
                    if (s.onlyDualType   !== undefined) this.onlyDualType.set(s.onlyDualType);
                    if (s.onlyDualTypeStrict !== undefined) this.onlyDualTypeStrict.set(s.onlyDualTypeStrict);
                    if (s.onlyMonoType   !== undefined) this.onlyMonoType.set(s.onlyMonoType);
                    if (s.minStatPv      !== undefined) this.minStatPv.set(s.minStatPv);
                    if (s.maxStatPv      !== undefined) this.maxStatPv.set(s.maxStatPv);
                    if (s.minStatAtq     !== undefined) this.minStatAtq.set(s.minStatAtq);
                    if (s.maxStatAtq     !== undefined) this.maxStatAtq.set(s.maxStatAtq);
                    if (s.minStatDef     !== undefined) this.minStatDef.set(s.minStatDef);
                    if (s.maxStatDef     !== undefined) this.maxStatDef.set(s.maxStatDef);
                    if (s.minStatAtqSpe  !== undefined) this.minStatAtqSpe.set(s.minStatAtqSpe);
                    if (s.maxStatAtqSpe  !== undefined) this.maxStatAtqSpe.set(s.maxStatAtqSpe);
                    if (s.minStatDefSpe  !== undefined) this.minStatDefSpe.set(s.minStatDefSpe);
                    if (s.maxStatDefSpe  !== undefined) this.maxStatDefSpe.set(s.maxStatDefSpe);
                    if (s.minStatVit     !== undefined) this.minStatVit.set(s.minStatVit);
                    if (s.maxStatVit     !== undefined) this.maxStatVit.set(s.maxStatVit);
                    if (s.minStatTotal   !== undefined) this.minStatTotal.set(s.minStatTotal);
                    if (s.maxStatTotal   !== undefined) this.maxStatTotal.set(s.maxStatTotal);
                    }
                }
            } catch { /* localStorage corrompu, on ignore */ }
        } else {
            this.clearFilters();
        }

        const id = this.roomId();
        if (id) {
            try {
                const saved = localStorage.getItem(PokedexComponent.dimmedKey(id));
                if (saved) this.manuallyDimmedIds.set(JSON.parse(saved));
            } catch { /* ignore */ }
        }

        this.pokemonService.loadAll().pipe(
            takeUntilDestroyed(this.destroyRef)
        ).subscribe(pokemons => {
            this.allPokemons.set(pokemons.map(p => ({
                ...p,
                _stage: parseInt(p.evolution_stage?.split('/')[0] || '1') || 1
            })));
        });
    }

    /** Charge une nouvelle page de Pokémon lors du défilement vers le bas de la grille. */
    onGridScroll(event: Event): void {
        if (this.isLoadingMore) return;
        const el = event.target as HTMLElement;
        if (el.scrollHeight - el.scrollTop - el.clientHeight < 300 && this.displayedCount() < this.filteredPokemons().length) {
            this.isLoadingMore = true;
            this.displayedCount.update(c => c + this.PAGE_SIZE);
            setTimeout(() => { this.isLoadingMore = false; }, 300);
        }
    }

    /** Ajoute ou retire une génération du filtre actif. */
    toggleGeneration(gen: number): void {
        this.selectedGenerations.update(list =>
            list.includes(gen) ? list.filter(g => g !== gen) : [...list, gen]
        );
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Retourne true si la génération donnée est actuellement sélectionnée dans le filtre. */
    isGenSelected(gen: number): boolean {
        return this.selectedGenerationSet().has(gen);
    }

    /** Retourne true si la génération est hors des générations autorisées par les paramètres de la room. */
    isGenRestricted(gen: number): boolean {
        const restricted = this.restrictedGenerationSet();
        return restricted.size > 0 && !restricted.has(gen);
    }

    /** Ajoute ou retire un type du filtre actif. */
    toggleType(type: string): void {
        this.selectedTypes.update(list => {
            if (list.includes(type)) return list.filter(t => t !== type);
            return [...list, type];
        });
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Active ou désactive le filtre "double type uniquement" (inclusif). */
    toggleOnlyDualType(): void {
        const next = !this.onlyDualType();
        this.onlyDualType.set(next);
        if (next) { this.onlyDualTypeStrict.set(false); this.onlyMonoType.set(false); }
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Active ou désactive le filtre "double type uniquement" (strict). */
    toggleOnlyDualTypeStrict(): void {
        const next = !this.onlyDualTypeStrict();
        this.onlyDualTypeStrict.set(next);
        if (next) { this.onlyDualType.set(false); this.onlyMonoType.set(false); }
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Active ou désactive le filtre "mono type uniquement". */
    toggleOnlyMonoType(): void {
        const next = !this.onlyMonoType();
        this.onlyMonoType.set(next);
        if (next) { this.onlyDualType.set(false); this.onlyDualTypeStrict.set(false); }
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Retourne true si le type donné est actuellement sélectionné dans le filtre. */
    isTypeSelected(type: string): boolean {
        return this.selectedTypeSet().has(type);
    }

    /** Selectionne tous les types. */
    selectAllTypes(): void {
        this.selectedTypes.set([...ALL_TYPES]);
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Deselectionne tous les types. */
    deselectAllTypes(): void {
        this.selectedTypes.set([]);
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Selectionne toutes les generations. */
    selectAllGenerations(): void {
        this.selectedGenerations.set([...GENERATIONS]);
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Deselectionne toutes les generations. */
    deselectAllGenerations(): void {
        this.selectedGenerations.set([]);
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Selectionne toutes les categories. */
    selectAllCategories(): void {
        this.selectedCategories.set(this.categories.map(c => c.id));
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Deselectionne toutes les categories. */
    deselectAllCategories(): void {
        this.selectedCategories.set([]);
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Ajoute ou retire une catégorie du filtre actif. */
    toggleCategory(catId: string): void {
        this.selectedCategories.update(list =>
            list.includes(catId) ? list.filter(c => c !== catId) : [...list, catId]
        );
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Retourne true si la catégorie donnée est actuellement sélectionnée dans le filtre. */
    isCategorySelected(catId: string): boolean {
        return this.selectedCategorySet().has(catId);
    }

    /** Ajoute ou retire un stade d'évolution du filtre actif. */
    toggleEvoStage(stage: number): void {
        this.selectedEvoStages.update(list =>
            list.includes(stage) ? list.filter(s => s !== stage) : [...list, stage]
        );
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Retourne true si le stade d'évolution donné est actuellement sélectionné dans le filtre. */
    isEvoStageSelected(stage: number): boolean {
        return this.selectedEvoStageSet().has(stage);
    }

    /** Réinitialise les filtres de stats à null. */
    clearStatFilters(): void {
        [this.minStatPv, this.maxStatPv, this.minStatAtq, this.maxStatAtq,
         this.minStatDef, this.maxStatDef, this.minStatAtqSpe, this.maxStatAtqSpe,
         this.minStatDefSpe, this.maxStatDefSpe, this.minStatVit, this.maxStatVit,
         this.minStatTotal, this.maxStatTotal].forEach(s => s.set(null));
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Réinitialise tous les filtres à leur valeur par défaut. */
    clearFilters(): void {
        this.searchQuery.set('');
        this.selectedGenerations.set([...GENERATIONS]);
        this.selectedTypes.set([...ALL_TYPES]);
        this.selectedCategories.set(['classique', 'starter', 'légendaire', 'fabuleux', 'fossile', 'ultra-chimère', 'pseudo-légendaire', 'bébé', 'paradoxe']);
        this.selectedEvoStages.set([1, 2, 3]);
        this.minWeight.set(0);
        this.maxWeight.set(null);
        this.minHeight.set(0);
        this.maxHeight.set(null);
        this.onlyDualType.set(false);
        this.onlyDualTypeStrict.set(false);
        this.onlyMonoType.set(false);
        this.clearStatFilters();
        this.displayedCount.set(this.PAGE_SIZE);
    }

    /** Retourne la classe CSS Tailwind de couleur de fond pour un type Pokémon donné. */
    getTypeColor(type: string): string {
        return TYPE_COLORS[type] ?? 'bg-gray-500';
    }

    /** Retourne l'icône Iconify correspondant à un type Pokémon donné. */
    getTypeIcon(type: string): string {
        return TYPE_ICONS[type] ?? 'mdi:circle-outline';
    }

    /** Ouvre la modal de détails d'un Pokémon. */
    openPokemonDetails(pokemon: Pokemon): void {
        this.selectedPokemonDetails = pokemon;
    }

    /** Ferme la modal de détails d'un Pokémon. */
    closePokemonDetails(): void {
        this.selectedPokemonDetails = null;
    }

    /** Émet le guess depuis la modal de détails et ferme celle-ci. */
    onGuessFromDetails(pokemon: Pokemon): void {
        this.guess.emit(pokemon.id);
        this.closePokemonDetails();
    }

    /** Retourne true si le Pokémon a été grisé manuellement par le joueur. */
    isManuallyDimmed(id: number): boolean {
        return this.manuallyDimmedIdSet().has(id);
    }

    /** Retourne true si le Pokemon a deja ete propose. */
    isPokemonGuessed(id: number): boolean {
        return this.guessedPokemonIdSet().has(id);
    }

    /** Retourne true si le Pokemon ne peut pas etre selectionne. */
    isPokemonUnavailable(id: number): boolean {
        return this.guessedPokemonIdSet().has(id) || this.manuallyDimmedIdSet().has(id);
    }

    /** Bascule le grisage manuel d'un Pokémon et arrête la propagation du clic. */
    toggleManualDim(id: number, event: Event): void {
        event.stopPropagation();
        this.manuallyDimmedIds.update(ids =>
            ids.includes(id) ? ids.filter(i => i !== id) : [...ids, id]
        );
    }
}
