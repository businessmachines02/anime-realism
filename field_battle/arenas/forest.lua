-- Hand-crafted forest pad. Trees on the laterals, grass in the mid belt.
return {
  id = "forest",
  sizeU = 10,
  sizeV = 5,
  floor = { 0.20, 0.38, 0.18 },
  floor2 = { 0.16, 0.32, 0.14 },
  grassColor = { 0.28, 0.52, 0.22 },
  pondColor = { 0.16, 0.28, 0.40 },
  pondColor2 = { 0.22, 0.38, 0.50 },
  cover = {
    { u = 1, v = 0, kind = "TREE" },
    { u = 2, v = 4, kind = "TREE" },
    { u = 8, v = 4, kind = "TREE" },
    { u = 7, v = 0, kind = "TREE" },
  },
  grass = {
    { u = 3, v = 1, wu = 2, hv = 1 },
    { u = 5, v = 1, wu = 2, hv = 1 },
    { u = 4, v = 3, wu = 3, hv = 1 },
  },
  ponds = {
    { u = 9, v = 3, wu = 1, hv = 2 },
  },
}
