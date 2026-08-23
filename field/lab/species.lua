-- Gen 1 lab catalog: types, approx RBY stats, STAB move pools.
-- Indexed by National Dex. Used only by the field lab.

local Species = {}

-- { t = types, hp, atk, def, spa, spe }
Species.DEX = {
  [1]   = { t = { "GRASS", "POISON" }, hp = 45, atk = 49, def = 49, spa = 65, spe = 45 },
  [2]   = { t = { "GRASS", "POISON" }, hp = 60, atk = 62, def = 63, spa = 80, spe = 60 },
  [3]   = { t = { "GRASS", "POISON" }, hp = 80, atk = 82, def = 83, spa = 100, spe = 80 },
  [4]   = { t = { "FIRE" }, hp = 39, atk = 52, def = 43, spa = 50, spe = 65 },
  [5]   = { t = { "FIRE" }, hp = 58, atk = 64, def = 58, spa = 65, spe = 80 },
  [6]   = { t = { "FIRE", "FLYING" }, hp = 78, atk = 84, def = 78, spa = 85, spe = 100 },
  [7]   = { t = { "WATER" }, hp = 44, atk = 48, def = 65, spa = 50, spe = 43 },
  [8]   = { t = { "WATER" }, hp = 59, atk = 63, def = 80, spa = 65, spe = 58 },
  [9]   = { t = { "WATER" }, hp = 79, atk = 83, def = 100, spa = 85, spe = 78 },
  [10]  = { t = { "BUG" }, hp = 45, atk = 30, def = 35, spa = 20, spe = 45 },
  [11]  = { t = { "BUG" }, hp = 50, atk = 20, def = 55, spa = 25, spe = 30 },
  [12]  = { t = { "BUG", "FLYING" }, hp = 60, atk = 45, def = 50, spa = 80, spe = 70 },
  [13]  = { t = { "BUG", "POISON" }, hp = 40, atk = 35, def = 30, spa = 20, spe = 50 },
  [14]  = { t = { "BUG", "POISON" }, hp = 45, atk = 25, def = 50, spa = 25, spe = 35 },
  [15]  = { t = { "BUG", "POISON" }, hp = 65, atk = 80, def = 40, spa = 45, spe = 75 },
  [16]  = { t = { "NORMAL", "FLYING" }, hp = 40, atk = 45, def = 40, spa = 35, spe = 56 },
  [17]  = { t = { "NORMAL", "FLYING" }, hp = 63, atk = 60, def = 55, spa = 50, spe = 71 },
  [18]  = { t = { "NORMAL", "FLYING" }, hp = 83, atk = 80, def = 75, spa = 70, spe = 91 },
  [19]  = { t = { "NORMAL" }, hp = 30, atk = 56, def = 35, spa = 25, spe = 72 },
  [20]  = { t = { "NORMAL" }, hp = 55, atk = 81, def = 60, spa = 50, spe = 97 },
  [21]  = { t = { "NORMAL", "FLYING" }, hp = 40, atk = 60, def = 30, spa = 31, spe = 70 },
  [22]  = { t = { "NORMAL", "FLYING" }, hp = 65, atk = 90, def = 65, spa = 61, spe = 100 },
  [23]  = { t = { "POISON" }, hp = 35, atk = 60, def = 44, spa = 40, spe = 55 },
  [24]  = { t = { "POISON" }, hp = 60, atk = 85, def = 69, spa = 65, spe = 80 },
  [25]  = { t = { "ELECTRIC" }, hp = 35, atk = 55, def = 30, spa = 50, spe = 90 },
  [26]  = { t = { "ELECTRIC" }, hp = 60, atk = 90, def = 55, spa = 90, spe = 100 },
  [27]  = { t = { "GROUND" }, hp = 50, atk = 75, def = 85, spa = 20, spe = 40 },
  [28]  = { t = { "GROUND" }, hp = 75, atk = 100, def = 110, spa = 45, spe = 65 },
  [29]  = { t = { "POISON" }, hp = 55, atk = 47, def = 52, spa = 40, spe = 41 },
  [30]  = { t = { "POISON" }, hp = 70, atk = 62, def = 67, spa = 55, spe = 56 },
  [31]  = { t = { "POISON", "GROUND" }, hp = 90, atk = 82, def = 87, spa = 75, spe = 76 },
  [32]  = { t = { "POISON" }, hp = 46, atk = 57, def = 40, spa = 40, spe = 50 },
  [33]  = { t = { "POISON" }, hp = 61, atk = 72, def = 57, spa = 55, spe = 65 },
  [34]  = { t = { "POISON", "GROUND" }, hp = 81, atk = 92, def = 77, spa = 75, spe = 85 },
  [35]  = { t = { "NORMAL" }, hp = 70, atk = 45, def = 48, spa = 60, spe = 35 },
  [36]  = { t = { "NORMAL" }, hp = 95, atk = 70, def = 73, spa = 85, spe = 60 },
  [37]  = { t = { "FIRE" }, hp = 38, atk = 41, def = 40, spa = 65, spe = 65 },
  [38]  = { t = { "FIRE" }, hp = 73, atk = 76, def = 75, spa = 81, spe = 100 },
  [39]  = { t = { "NORMAL" }, hp = 115, atk = 45, def = 20, spa = 25, spe = 20 },
  [40]  = { t = { "NORMAL" }, hp = 140, atk = 70, def = 45, spa = 50, spe = 45 },
  [41]  = { t = { "POISON", "FLYING" }, hp = 40, atk = 45, def = 35, spa = 40, spe = 55 },
  [42]  = { t = { "POISON", "FLYING" }, hp = 75, atk = 80, def = 70, spa = 75, spe = 90 },
  [43]  = { t = { "GRASS", "POISON" }, hp = 45, atk = 50, def = 55, spa = 75, spe = 30 },
  [44]  = { t = { "GRASS", "POISON" }, hp = 60, atk = 65, def = 70, spa = 85, spe = 40 },
  [45]  = { t = { "GRASS", "POISON" }, hp = 75, atk = 80, def = 85, spa = 100, spe = 50 },
  [46]  = { t = { "BUG", "GRASS" }, hp = 35, atk = 70, def = 55, spa = 45, spe = 25 },
  [47]  = { t = { "BUG", "GRASS" }, hp = 60, atk = 95, def = 80, spa = 60, spe = 30 },
  [48]  = { t = { "BUG", "POISON" }, hp = 60, atk = 55, def = 50, spa = 40, spe = 45 },
  [49]  = { t = { "BUG", "POISON" }, hp = 70, atk = 65, def = 60, spa = 90, spe = 90 },
  [50]  = { t = { "GROUND" }, hp = 10, atk = 55, def = 25, spa = 45, spe = 95 },
  [51]  = { t = { "GROUND" }, hp = 35, atk = 80, def = 50, spa = 70, spe = 120 },
  [52]  = { t = { "NORMAL" }, hp = 40, atk = 45, def = 35, spa = 40, spe = 90 },
  [53]  = { t = { "NORMAL" }, hp = 65, atk = 70, def = 60, spa = 65, spe = 115 },
  [54]  = { t = { "WATER" }, hp = 50, atk = 52, def = 48, spa = 50, spe = 55 },
  [55]  = { t = { "WATER" }, hp = 80, atk = 82, def = 78, spa = 80, spe = 85 },
  [56]  = { t = { "FIGHTING" }, hp = 40, atk = 80, def = 35, spa = 35, spe = 70 },
  [57]  = { t = { "FIGHTING" }, hp = 65, atk = 105, def = 60, spa = 60, spe = 95 },
  [58]  = { t = { "FIRE" }, hp = 55, atk = 70, def = 45, spa = 70, spe = 60 },
  [59]  = { t = { "FIRE" }, hp = 90, atk = 110, def = 80, spa = 80, spe = 95 },
  [60]  = { t = { "WATER" }, hp = 40, atk = 50, def = 40, spa = 40, spe = 90 },
  [61]  = { t = { "WATER" }, hp = 65, atk = 65, def = 65, spa = 50, spe = 90 },
  [62]  = { t = { "WATER", "FIGHTING" }, hp = 90, atk = 85, def = 95, spa = 70, spe = 70 },
  [63]  = { t = { "PSYCHIC" }, hp = 25, atk = 20, def = 15, spa = 105, spe = 90 },
  [64]  = { t = { "PSYCHIC" }, hp = 40, atk = 35, def = 30, spa = 120, spe = 105 },
  [65]  = { t = { "PSYCHIC" }, hp = 55, atk = 50, def = 45, spa = 135, spe = 120 },
  [66]  = { t = { "FIGHTING" }, hp = 70, atk = 80, def = 50, spa = 35, spe = 35 },
  [67]  = { t = { "FIGHTING" }, hp = 80, atk = 100, def = 70, spa = 50, spe = 45 },
  [68]  = { t = { "FIGHTING" }, hp = 90, atk = 130, def = 80, spa = 65, spe = 55 },
  [69]  = { t = { "GRASS", "POISON" }, hp = 50, atk = 75, def = 35, spa = 70, spe = 40 },
  [70]  = { t = { "GRASS", "POISON" }, hp = 65, atk = 90, def = 50, spa = 85, spe = 55 },
  [71]  = { t = { "GRASS", "POISON" }, hp = 80, atk = 105, def = 65, spa = 100, spe = 70 },
  [72]  = { t = { "WATER", "POISON" }, hp = 40, atk = 40, def = 35, spa = 100, spe = 70 },
  [73]  = { t = { "WATER", "POISON" }, hp = 80, atk = 70, def = 65, spa = 120, spe = 100 },
  [74]  = { t = { "ROCK", "GROUND" }, hp = 40, atk = 80, def = 100, spa = 30, spe = 20 },
  [75]  = { t = { "ROCK", "GROUND" }, hp = 55, atk = 95, def = 115, spa = 45, spe = 35 },
  [76]  = { t = { "ROCK", "GROUND" }, hp = 80, atk = 110, def = 130, spa = 55, spe = 45 },
  [77]  = { t = { "FIRE" }, hp = 50, atk = 85, def = 55, spa = 65, spe = 90 },
  [78]  = { t = { "FIRE" }, hp = 65, atk = 100, def = 70, spa = 80, spe = 105 },
  [79]  = { t = { "WATER", "PSYCHIC" }, hp = 90, atk = 65, def = 65, spa = 40, spe = 15 },
  [80]  = { t = { "WATER", "PSYCHIC" }, hp = 95, atk = 75, def = 110, spa = 80, spe = 30 },
  [81]  = { t = { "ELECTRIC" }, hp = 25, atk = 35, def = 70, spa = 95, spe = 45 },
  [82]  = { t = { "ELECTRIC" }, hp = 50, atk = 60, def = 95, spa = 120, spe = 70 },
  [83]  = { t = { "NORMAL", "FLYING" }, hp = 52, atk = 65, def = 55, spa = 58, spe = 60 },
  [84]  = { t = { "NORMAL", "FLYING" }, hp = 35, atk = 85, def = 45, spa = 35, spe = 75 },
  [85]  = { t = { "NORMAL", "FLYING" }, hp = 60, atk = 110, def = 70, spa = 60, spe = 100 },
  [86]  = { t = { "WATER" }, hp = 65, atk = 45, def = 55, spa = 45, spe = 45 },
  [87]  = { t = { "WATER", "ICE" }, hp = 90, atk = 70, def = 80, spa = 70, spe = 70 },
  [88]  = { t = { "POISON" }, hp = 80, atk = 80, def = 50, spa = 40, spe = 25 },
  [89]  = { t = { "POISON" }, hp = 105, atk = 105, def = 75, spa = 65, spe = 50 },
  [90]  = { t = { "WATER" }, hp = 30, atk = 65, def = 100, spa = 45, spe = 40 },
  [91]  = { t = { "WATER", "ICE" }, hp = 50, atk = 95, def = 180, spa = 85, spe = 70 },
  [92]  = { t = { "GHOST", "POISON" }, hp = 30, atk = 35, def = 30, spa = 100, spe = 80 },
  [93]  = { t = { "GHOST", "POISON" }, hp = 45, atk = 50, def = 45, spa = 115, spe = 95 },
  [94]  = { t = { "GHOST", "POISON" }, hp = 60, atk = 65, def = 60, spa = 130, spe = 110 },
  [95]  = { t = { "ROCK", "GROUND" }, hp = 35, atk = 45, def = 160, spa = 30, spe = 70 },
  [96]  = { t = { "PSYCHIC" }, hp = 60, atk = 48, def = 45, spa = 43, spe = 42 },
  [97]  = { t = { "PSYCHIC" }, hp = 85, atk = 73, def = 70, spa = 73, spe = 67 },
  [98]  = { t = { "WATER" }, hp = 30, atk = 105, def = 90, spa = 25, spe = 50 },
  [99]  = { t = { "WATER" }, hp = 55, atk = 130, def = 115, spa = 50, spe = 75 },
  [100] = { t = { "ELECTRIC" }, hp = 40, atk = 30, def = 50, spa = 55, spe = 100 },
  [101] = { t = { "ELECTRIC" }, hp = 60, atk = 50, def = 70, spa = 80, spe = 140 },
  [102] = { t = { "GRASS", "PSYCHIC" }, hp = 60, atk = 40, def = 80, spa = 60, spe = 40 },
  [103] = { t = { "GRASS", "PSYCHIC" }, hp = 95, atk = 95, def = 85, spa = 125, spe = 55 },
  [104] = { t = { "GROUND" }, hp = 50, atk = 50, def = 95, spa = 40, spe = 35 },
  [105] = { t = { "GROUND" }, hp = 60, atk = 80, def = 110, spa = 50, spe = 45 },
  [106] = { t = { "FIGHTING" }, hp = 50, atk = 120, def = 53, spa = 35, spe = 87 },
  [107] = { t = { "FIGHTING" }, hp = 50, atk = 105, def = 79, spa = 35, spe = 76 },
  [108] = { t = { "NORMAL" }, hp = 90, atk = 55, def = 75, spa = 60, spe = 30 },
  [109] = { t = { "POISON" }, hp = 40, atk = 65, def = 95, spa = 60, spe = 35 },
  [110] = { t = { "POISON" }, hp = 65, atk = 90, def = 120, spa = 85, spe = 60 },
  [111] = { t = { "GROUND", "ROCK" }, hp = 80, atk = 85, def = 95, spa = 30, spe = 25 },
  [112] = { t = { "GROUND", "ROCK" }, hp = 105, atk = 130, def = 120, spa = 45, spe = 40 },
  [113] = { t = { "NORMAL" }, hp = 250, atk = 5, def = 5, spa = 35, spe = 50 },
  [114] = { t = { "GRASS" }, hp = 65, atk = 55, def = 115, spa = 100, spe = 60 },
  [115] = { t = { "NORMAL" }, hp = 105, atk = 95, def = 80, spa = 40, spe = 90 },
  [116] = { t = { "WATER" }, hp = 30, atk = 40, def = 70, spa = 70, spe = 60 },
  [117] = { t = { "WATER" }, hp = 55, atk = 65, def = 95, spa = 95, spe = 85 },
  [118] = { t = { "WATER" }, hp = 45, atk = 67, def = 60, spa = 50, spe = 63 },
  [119] = { t = { "WATER" }, hp = 80, atk = 92, def = 65, spa = 80, spe = 68 },
  [120] = { t = { "WATER" }, hp = 30, atk = 45, def = 55, spa = 70, spe = 85 },
  [121] = { t = { "WATER", "PSYCHIC" }, hp = 60, atk = 75, def = 85, spa = 100, spe = 115 },
  [122] = { t = { "PSYCHIC" }, hp = 40, atk = 45, def = 65, spa = 100, spe = 90 },
  [123] = { t = { "BUG", "FLYING" }, hp = 70, atk = 110, def = 80, spa = 55, spe = 105 },
  [124] = { t = { "ICE", "PSYCHIC" }, hp = 65, atk = 50, def = 35, spa = 95, spe = 95 },
  [125] = { t = { "ELECTRIC" }, hp = 65, atk = 83, def = 57, spa = 85, spe = 105 },
  [126] = { t = { "FIRE" }, hp = 65, atk = 95, def = 57, spa = 85, spe = 93 },
  [127] = { t = { "BUG" }, hp = 65, atk = 125, def = 100, spa = 55, spe = 85 },
  [128] = { t = { "NORMAL" }, hp = 75, atk = 100, def = 95, spa = 70, spe = 110 },
  [129] = { t = { "WATER" }, hp = 20, atk = 10, def = 55, spa = 20, spe = 80 },
  [130] = { t = { "WATER", "FLYING" }, hp = 95, atk = 125, def = 79, spa = 60, spe = 81 },
  [131] = { t = { "WATER", "ICE" }, hp = 130, atk = 85, def = 80, spa = 85, spe = 60 },
  [132] = { t = { "NORMAL" }, hp = 48, atk = 48, def = 48, spa = 48, spe = 48 },
  [133] = { t = { "NORMAL" }, hp = 55, atk = 55, def = 50, spa = 45, spe = 55 },
  [134] = { t = { "WATER" }, hp = 130, atk = 65, def = 60, spa = 110, spe = 65 },
  [135] = { t = { "ELECTRIC" }, hp = 65, atk = 65, def = 60, spa = 110, spe = 130 },
  [136] = { t = { "FIRE" }, hp = 65, atk = 130, def = 60, spa = 95, spe = 65 },
  [137] = { t = { "NORMAL" }, hp = 65, atk = 60, def = 70, spa = 75, spe = 40 },
  [138] = { t = { "ROCK", "WATER" }, hp = 35, atk = 40, def = 100, spa = 90, spe = 35 },
  [139] = { t = { "ROCK", "WATER" }, hp = 70, atk = 60, def = 125, spa = 115, spe = 55 },
  [140] = { t = { "ROCK", "WATER" }, hp = 30, atk = 80, def = 90, spa = 45, spe = 55 },
  [141] = { t = { "ROCK", "WATER" }, hp = 60, atk = 115, def = 105, spa = 70, spe = 80 },
  [142] = { t = { "ROCK", "FLYING" }, hp = 80, atk = 105, def = 65, spa = 60, spe = 130 },
  [143] = { t = { "NORMAL" }, hp = 160, atk = 110, def = 65, spa = 65, spe = 30 },
  [144] = { t = { "ICE", "FLYING" }, hp = 90, atk = 85, def = 100, spa = 95, spe = 85 },
  [145] = { t = { "ELECTRIC", "FLYING" }, hp = 90, atk = 90, def = 85, spa = 125, spe = 100 },
  [146] = { t = { "FIRE", "FLYING" }, hp = 90, atk = 100, def = 90, spa = 125, spe = 90 },
  [147] = { t = { "DRAGON" }, hp = 41, atk = 64, def = 45, spa = 50, spe = 50 },
  [148] = { t = { "DRAGON" }, hp = 61, atk = 84, def = 65, spa = 70, spe = 70 },
  [149] = { t = { "DRAGON", "FLYING" }, hp = 91, atk = 134, def = 95, spa = 100, spe = 80 },
  [150] = { t = { "PSYCHIC" }, hp = 106, atk = 110, def = 90, spa = 154, spe = 130 },
  [151] = { t = { "PSYCHIC" }, hp = 100, atk = 100, def = 100, spa = 100, spe = 100 },
}

local function m(id, power, category, type)
  return { id = id, power = power, category = category, type = type }
end

Species.STAB = {
  NORMAL = {
    m("BODY_SLAM", 85, "physical", "NORMAL"),
    m("TACKLE", 35, "physical", "NORMAL"),
    m("QUICK_ATTACK", 40, "physical", "NORMAL"),
    m("SWIFT", 60, "special", "NORMAL"),
  },
  FIRE = {
    m("FLAMETHROWER", 95, "special", "FIRE"),
    m("FIRE_BLAST", 120, "special", "FIRE"),
    m("EMBER", 40, "special", "FIRE"),
    m("FIRE_PUNCH", 75, "physical", "FIRE"),
  },
  WATER = {
    m("HYDRO_PUMP", 120, "special", "WATER"),
    m("SURF", 95, "special", "WATER"),
    m("WATER_GUN", 40, "special", "WATER"),
    m("BUBBLEBEAM", 65, "special", "WATER"),
  },
  ELECTRIC = {
    m("THUNDERBOLT", 95, "special", "ELECTRIC"),
    m("THUNDER", 120, "special", "ELECTRIC"),
    m("THUNDERSHOCK", 40, "special", "ELECTRIC"),
    m("THUNDER_WAVE", 0, "status", "ELECTRIC"),
  },
  GRASS = {
    m("SOLARBEAM", 120, "special", "GRASS"),
    m("RAZOR_LEAF", 55, "special", "GRASS"),
    m("VINE_WHIP", 35, "physical", "GRASS"),
    m("MEGA_DRAIN", 40, "special", "GRASS"),
  },
  ICE = {
    m("ICE_BEAM", 95, "special", "ICE"),
    m("BLIZZARD", 120, "special", "ICE"),
    m("AURORA_BEAM", 65, "special", "ICE"),
    m("ICE_PUNCH", 75, "physical", "ICE"),
  },
  FIGHTING = {
    m("SUBMISSION", 80, "physical", "FIGHTING"),
    m("LOW_KICK", 50, "physical", "FIGHTING"),
    m("SEISMIC_TOSS", 0, "physical", "FIGHTING"),
    m("COUNTER", 0, "physical", "FIGHTING"),
  },
  POISON = {
    m("SLUDGE", 65, "special", "POISON"),
    m("ACID", 40, "special", "POISON"),
    m("POISON_STING", 15, "physical", "POISON"),
    m("TOXIC", 0, "status", "POISON"),
  },
  GROUND = {
    m("EARTHQUAKE", 100, "physical", "GROUND"),
    m("DIG", 80, "physical", "GROUND"),
    m("BONE_CLUB", 65, "physical", "GROUND"),
    m("FISSURE", 0, "physical", "GROUND"),
  },
  FLYING = {
    m("WING_ATTACK", 35, "physical", "FLYING"),
    m("DRILL_PECK", 80, "physical", "FLYING"),
    m("PECK", 35, "physical", "FLYING"),
    m("FLY", 70, "physical", "FLYING"),
  },
  PSYCHIC = {
    m("PSYCHIC", 90, "special", "PSYCHIC"),
    m("PSYBEAM", 65, "special", "PSYCHIC"),
    m("CONFUSION", 50, "special", "PSYCHIC"),
    m("SWIFT", 60, "special", "NORMAL"),
  },
  BUG = {
    m("TWINEEDLE", 25, "physical", "BUG"),
    m("PIN_MISSILE", 14, "physical", "BUG"),
    m("LEECH_LIFE", 20, "physical", "BUG"),
    m("STRING_SHOT", 0, "status", "BUG"),
  },
  ROCK = {
    m("ROCK_SLIDE", 75, "physical", "ROCK"),
    m("ROCK_THROW", 50, "physical", "ROCK"),
    m("TACKLE", 35, "physical", "NORMAL"),
    m("EXPLOSION", 170, "physical", "NORMAL"),
  },
  GHOST = {
    m("LICK", 20, "physical", "GHOST"),
    m("NIGHT_SHADE", 0, "special", "GHOST"),
    m("CONFUSE_RAY", 0, "status", "GHOST"),
    m("MEGA_DRAIN", 40, "special", "GRASS"),
  },
  DRAGON = {
    m("DRAGON_RAGE", 40, "special", "DRAGON"),
    m("SLAM", 80, "physical", "NORMAL"),
    m("HYPER_BEAM", 150, "special", "NORMAL"),
    m("THUNDER_WAVE", 0, "status", "ELECTRIC"),
  },
}

Species.NAMED = {
  PIKACHU = {
    m("THUNDERBOLT", 95, "special", "ELECTRIC"),
    m("THUNDERSHOCK", 40, "special", "ELECTRIC"),
    m("QUICK_ATTACK", 40, "physical", "NORMAL"),
    m("SWIFT", 60, "special", "NORMAL"),
  },
  CHARIZARD = {
    m("FLAMETHROWER", 95, "special", "FIRE"),
    m("EMBER", 40, "special", "FIRE"),
    m("SLASH", 70, "physical", "NORMAL"),
    m("FIRE_BLAST", 120, "special", "FIRE"),
  },
  BLASTOISE = {
    m("HYDRO_PUMP", 120, "special", "WATER"),
    m("WATER_GUN", 40, "special", "WATER"),
    m("BITE", 60, "physical", "NORMAL"),
    m("SURF", 95, "special", "WATER"),
  },
  VENUSAUR = {
    m("SOLARBEAM", 120, "special", "GRASS"),
    m("RAZOR_LEAF", 55, "special", "GRASS"),
    m("VINE_WHIP", 35, "physical", "GRASS"),
    m("MEGA_DRAIN", 40, "special", "GRASS"),
  },
  GOLEM = {
    m("EARTHQUAKE", 100, "physical", "GROUND"),
    m("ROCK_THROW", 50, "physical", "ROCK"),
    m("TACKLE", 35, "physical", "NORMAL"),
    m("EXPLOSION", 170, "physical", "NORMAL"),
  },
  ALAKAZAM = {
    m("PSYCHIC", 90, "special", "PSYCHIC"),
    m("CONFUSION", 50, "special", "PSYCHIC"),
    m("PSYBEAM", 65, "special", "PSYCHIC"),
    m("SWIFT", 60, "special", "NORMAL"),
  },
  ONIX = {
    m("ROCK_THROW", 50, "physical", "ROCK"),
    m("TACKLE", 35, "physical", "NORMAL"),
    m("BIND", 15, "physical", "NORMAL"),
    m("RAGE", 20, "physical", "NORMAL"),
  },
  GYARADOS = {
    m("HYDRO_PUMP", 120, "special", "WATER"),
    m("BITE", 60, "physical", "NORMAL"),
    m("DRAGON_RAGE", 40, "special", "DRAGON"),
    m("TACKLE", 35, "physical", "NORMAL"),
  },
}

function Species.row(dex)
  return Species.DEX[tonumber(dex) or 0]
end

function Species.types(dex)
  local row = Species.row(dex)
  return row and row.t or { "NORMAL" }
end

function Species.stats(dex)
  local row = Species.row(dex)
  if not row then
    return { hp = 80, attack = 55, defense = 50, special = 55, speed = 60 }
  end
  return {
    hp = row.hp,
    attack = row.atk,
    defense = row.def,
    special = row.spa,
    speed = row.spe,
  }
end

function Species.def(dex, name)
  local types = Species.types(dex)
  return {
    dex = tonumber(dex) or 0,
    name = name,
    types = types,
    stats = Species.stats(dex),
  }
end

function Species.typeTag(types)
  types = types or {}
  if types[2] then
    return types[1] .. "/" .. types[2]
  end
  return types[1] or "NORMAL"
end

local function take(pool, dest, used, count)
  for i = 1, #(pool or {}) do
    if #dest >= count then
      return
    end
    local move = pool[i]
    if move and not used[move.id] then
      used[move.id] = true
      dest[#dest + 1] = move
    end
  end
end

function Species.moves(name, types)
  if name and Species.NAMED[name] then
    return Species.NAMED[name]
  end
  types = types or { "NORMAL" }
  local pool = {}
  local used = {}
  take(Species.STAB[types[1]], pool, used, 3)
  if types[2] then
    take(Species.STAB[types[2]], pool, used, 4)
  end
  take(Species.STAB.NORMAL, pool, used, 4)
  if #pool < 1 then
    pool[1] = m("TACKLE", 35, "physical", "NORMAL")
  end
  return pool
end

return Species
