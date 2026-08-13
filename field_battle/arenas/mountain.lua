-- Hand-crafted mountain / plateau pad.
return {
  id = "mountain",
  sizeU = 10,
  sizeV = 5,
  floor = { 0.40, 0.36, 0.32 },
  floor2 = { 0.34, 0.30, 0.26 },
  grassColor = { 0.30, 0.38, 0.22 },
  pondColor = { 0.18, 0.28, 0.40 },
  pondColor2 = { 0.24, 0.36, 0.48 },
  cover = {
    { u = 0, v = 0, kind = "ROCK" },
    { u = 2, v = 4, kind = "ROCK" },
    { u = 8, v = 0, kind = "ROCK" },
    { u = 9, v = 4, kind = "ROCK" },
  },
  grass = {
    { u = 4, v = 1, wu = 2, hv = 1 },
  },
  ponds = {
    { u = 5, v = 4, wu = 2, hv = 1 },
  },
}
