export const ICONS = {
  // Navigation & UI
  home: 'mdi:home',
  back: 'mdi:arrow-left',
  copy: 'mdi:content-copy',
  check: 'mdi:check',
  close: 'mdi:close',
  search: 'mdi:magnify',
  alert: 'mdi:alert',
  loading: 'mdi:loading',       // animé : animate-spin
  refresh: 'mdi:refresh',       // animé : animate-spin
  edit: 'mdi:pencil',

  // Jeu
  game: 'mdi:gamepad-variant',
  dice: 'mdi:dice-multiple',    // animé : animate-bounce
  trophy: 'mdi:trophy',
  crown: 'mdi:crown',
  skull: 'mdi:skull',
  pokedex: 'mdi:book-open-page-variant',
  timer: 'mdi:timer-sand',      // animé : animate-pulse
  guess: 'ri:question-fill',
  whoPokemon: 'mdi:incognito',
  sound: 'mdi:volume-high',
  play: 'mdi:play',
  pause: 'mdi:pause',

  // Auth
  email: 'mdi:email-outline',
  password: 'mdi:lock-outline',
  eye: 'mdi:eye-outline',
  eyeOff: 'mdi:eye-off-outline',
  login: 'mdi:login',
  logout: 'mdi:logout',
  user: 'mdi:account-outline',

  // Pokémon / Lobby
  pokeball: 'mdi:pokeball',
  checkCircle: 'mdi:check-circle',
  clock: 'mdi:clock-outline',   // animé : animate-spin [animation-duration:3s]
  share: 'mdi:share-variant',
  sword: 'mdi:sword-cross',
  shield: 'mdi:shield-outline',

  // Règles
  rules: 'mdi:help-circle-outline',
  help: 'mdi:information-outline',

  // Amis
  friends: 'mdi:account-group',
  addFriend: 'mdi:account-plus',
  trash: 'mdi:trash-can-outline',
  moreVert: 'mdi:dots-horizontal',

  // Filtres
  weight: 'mdi:weight-kilogram',
  height: 'mdi:ruler',
  category: 'mdi:shape-outline',
  evolution: 'mdi:auto-fix', // can represent evolution/upgrade

  // Team Builder
  draft: 'arcticons:pokemon-masters-ex-alt-2',
  lock: 'mdi:lock',
  star: 'mdi:star',

  // Duel de Base Stats
  statDuel: 'famicons:stats-chart',
  robot: 'mdi:robot',
} as const;

export type IconName = keyof typeof ICONS;
export type IconValue = (typeof ICONS)[IconName];
