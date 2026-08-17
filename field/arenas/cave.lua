-- Hand-crafted cave pad. u = player → foe, v = lateral.
-- Authored for 10×5. Keep the fight lane (v ≈ 2, u 3 and 7) open.
return {
  id = "cave",
  sizeU = 10,
  sizeV = 5,
  floor = { 0.30, 0.28, 0.26 },
  floor2 = { 0.24, 0.22, 0.20 },
  grassColor = { 0.22, 0.32, 0.24 },
  pondColor = { 0.14, 0.22, 0.34 },
  pondColor2 = { 0.20, 0.32, 0.42 },
  cover = {
    { u = 1, v = 0, kind = "ROCK" },
    { u = 2, v = 4, kind = "ROCK" },
    { u = 8, v = 0, kind = "ROCK" },
    { u = 6, v = 4, kind = "ROCK" },
  },
  grass = {
    { u = 4, v = 1, wu = 2, hv = 1 },
    { u = 5, v = 3, wu = 2, hv = 1 },
  },
  ponds = {
    { u = 0, v = 3, wu = 2, hv = 2 },
  },
}
