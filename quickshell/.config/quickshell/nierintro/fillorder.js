// Triangle fill order extracted frame-by-frame from the NieR:Automata menu-open
// transition (see README). 9 rows x 17 slots; the digit is the step (0..8) at
// which that shape pops to the beige fill. Not random at runtime - this is the
// exact order from the source footage.
.pragma library

var ROWS = 9;
var SLOTS = 17;
var STEPS = 9;

var ORDER = [
  "53125422443346154",
  "42154046507534206",
  "44264841343104233",
  "42642354563473468",
  "23512742231562062",
  "47734642745442462",
  "14234104340475533",
  "45115266147314603",
  "44425524441346122"
];

function stepAt(row, slot) { return ORDER[row].charCodeAt(slot) - 48; }
