export interface Pokemon {
  id: number;
  name: string;
  types: string[];
  generation: number;
  category: 'classique' | 'starter' | 'légendaire' | 'fabuleux' | 'fossile' | 'ultra-chimère' | 'pseudo-légendaire' | 'bébé' | 'paradoxe';
  evolution_stage: string;
  _stage?: number;
  sprite: string;
  cry?: string;
  stats: {
    pv: number;
    attaque: number;
    defense: number;
    atq_spe: number;
    def_spe: number;
    vitesse: number;
  };
  height: number;
  weight: number;
  description: string;
  rating?: number;
}
