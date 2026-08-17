-- Hand-crafted route pad. Open lane, two trees, grass patches.
return {
  id = "route",
  sizeU = 10,
  sizeV = 5,
  floor = { 0.42, 0.62, 0.28 },
  floor2 = { 0.36, 0.54, 0.24 },
  grassColor = { 0.32, 0.58, 0.22 },
  pondColor = { 0.22, 0.40, 0.58 },
  pondColor2 = { 0.30, 0.52, 0.68 },
  cover = {
    { u = 2, v = 0, kind = "TREE" },
    { u = 8, v = 4, kind = "TREE" },
  },
  grass = {
    { u = 4, v = 0, wu = 2, hv = 1 },
    { u = 5, v = 3, wu = 2, hv = 2 },
    { u = 1, v = 3, wu = 2, hv = 1 },
  },
  ponds = {},
}
