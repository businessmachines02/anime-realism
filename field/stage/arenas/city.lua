-- Hand-crafted city / town pad. Pavement and crates; keep the street open.
return {
  id = "city",
  sizeU = 10,
  sizeV = 5,
  floor = { 0.52, 0.50, 0.46 },
  floor2 = { 0.46, 0.44, 0.40 },
  grassColor = { 0.28, 0.48, 0.24 },
  pondColor = { 0.30, 0.42, 0.52 },
  pondColor2 = { 0.36, 0.50, 0.60 },
  cover = {
    { u = 1, v = 0, kind = "CRATE" },
    { u = 8, v = 4, kind = "CRATE" },
  },
  grass = {
    { u = 5, v = 0, wu = 1, hv = 1 },
  },
  ponds = {},
}
