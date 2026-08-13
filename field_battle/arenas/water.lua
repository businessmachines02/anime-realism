-- Hand-crafted water / Seafoam / ship pad. Sand, rocks, ponds.
return {
  id = "water",
  sizeU = 10,
  sizeV = 5,
  floor = { 0.72, 0.66, 0.48 },
  floor2 = { 0.64, 0.58, 0.40 },
  grassColor = { 0.40, 0.56, 0.28 },
  pondColor = { 0.20, 0.42, 0.62 },
  pondColor2 = { 0.28, 0.54, 0.74 },
  cover = {
    { u = 1, v = 4, kind = "ROCK" },
    { u = 8, v = 0, kind = "ROCK" },
  },
  grass = {
    { u = 3, v = 0, wu = 2, hv = 1 },
    { u = 6, v = 3, wu = 2, hv = 1 },
  },
  ponds = {
    { u = 0, v = 0, wu = 2, hv = 2 },
    { u = 8, v = 3, wu = 2, hv = 2 },
  },
}
