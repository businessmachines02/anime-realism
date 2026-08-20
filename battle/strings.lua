-- Battle dialogue strings and tunables.
-- Shared table (callouts, banter, Focus flavor, delays). main.lua aliases
-- `local S = Battle.Strings` so React.bind / Dialogue.bind see one copy.

local S = {}
S.PLAYER_LOW = {
    "Your POKéMON is\nlooking weak!",
    "Your POKéMON is\nlooking tired!",
    "Your POKéMON looks\nweak...",
    "Your POKéMON looks\ntired...",
}
S.ENEMY_LOW = {
    "The enemy POKéMON\nis looking weak!",
    "The enemy POKéMON\nis looking tired!",
    "The foe's POKéMON\nlooks weak!",
    "The foe's POKéMON\nlooks tired...",
}
S.PAR_REACT_FAIL_EXTRA = 0.25
S.PAR_SHAKE_OFF = 0.10
S.COUNTER_EXTRA_MISS = 0.05
S.COUNTER_SNAPBACK_CHANCE = 0.40
S.COUNTER_SNAPBACK_MULT = 0.50 -- of the foe's stashed whiff estimate
S.LEVEL_UP_LINES = {
    "Your POKéMON has grown stronger!",
    "Your POKéMON looks more powerful!",
    "Your POKéMON's power has surged!",
    "Your POKéMON has become tougher!",
}
S.PLAYER_MOVE_CALLS = {
    "%s! Use %s!",
    "%s, use %s!",
    "Go! %s! %s!",
    "%s! %s!",
    "%s! Now! %s!",
    "%s! Quick, %s!",
    "OK, %s! %s!",
    "%s, go! Use %s!",
    "That's it! %s! %s!",
    "%s! Hit 'em! %s!",
    "Come on! %s! %s!",
    "%s! %s! Go!",
}
S.PLAYER_FINISH_CALLS = {
    "Finish it! %s! %s!",
    "%s! Finish it!",
    "%s! Finish it! %s!",
    "Now's our chance! %s! %s!",
    "%s! End it! %s!",
    "One more! %s! %s!",
    "%s! Take 'em down!",
    "Go for it! %s! %s!",
    "%s! This is it! %s!",
    "Finish them! %s! %s!",
}
S.AUTO_COUNTER_CALLS = {
    "%s! Counter with %s!",
    "Now, %s! Counter- %s!",
    "%s! Hit back! %s!",
    "Counter! %s, use %s!",
}
S.PLAYER_COUNTER_CALLS = {
    AUTO = {
        "Now, %s! %s!",
        "%s! Hit back! %s!",
        "%s! Counter with %s!",
        "That's our opening! %s! %s!",
    },
    BOLD = {
        "%s! Strike back! %s!",
        "%s! Hit 'em hard!",
        "Now, %s! Smash back!",
        "%s! Return it! %s!",
    },
    TRICKY = {
        "%s! Turn it around!",
        "Now, %s! Catch 'em!",
        "%s! Use that opening!",
        "%s! Slip in- %s!",
    },
    SHOWY = {
        "Show 'em, %s! %s!",
        "%s! Make it flashy!",
        "That's it! %s! %s!",
        "%s! Hero time! %s!",
    },
}
S.DODGE_STYLE = {
    AUTO = {
        "%s! Dodge it!",
        "Dodge, %s!",
        "%s! Look out!",
        "Quick, %s! Dodge!",
    },
    BOLD = {
        "%s! Shrug it off!",
        "%s! Stand tall-dodge!",
        "No way, %s! Move!",
        "%s! Break clear!",
    },
    TRICKY = {
        "%s! Slip aside!",
        "Fake 'em out, %s!",
        "%s! Weave through!",
        "Easy, %s! Sidestep!",
    },
    SHOWY = {
        "%s! Dance aside!",
        "Show off, %s! Dodge!",
        "%s! Make it clean!",
        "Stylish, %s! Move!",
    },
}
S.BRACE_STYLE = {
    AUTO = {
        "%s! Get ready!",
        "%s! Brace yourself!",
        "Hold on, %s!",
    },
    BOLD = {
        "%s! Take it head-on!",
        "Stand firm, %s!",
    },
    TRICKY = {
        "Wait for it, %s!",
        "%s! Let 'em commit!",
        "%s! Then we hit!",
    },
    SHOWY = {
        "%s! Make it look easy!",
        "Chin up, %s!",
        "%s! Pose-and brace!",
        "Cool under fire, %s!",
    },
}
S.DODGE_SCENE = {
    cave = {
        "%s! Onto that rock!",
        "%s! Behind the rocks!",
        "Dodge-jump, %s! That ledge!",
    },
    forest = {
        "%s! Behind that tree!",
        "%s! Into the brush!",
        "Dodge-leaf, %s! Hide!",
    },
    city = {
        "%s! Behind that cart!",
        "%s! Use that alley!",
        "Dodge-corner, %s!",
    },
    route = {
        "%s! Into the grass!",
        "%s! Off the path!",
        "Wide berth, %s!",
    },
    mountain = {
        "%s! Up that cliff!",
        "%s! Use the ledge!",
        "Higher ground, %s!",
    },
    gym = {
        "%s! Use the pillars!",
        "%s! Around the court!",
        "Sidestep, %s! Pillar!",
    },
    water = {
        "%s! Along the shore!",
        "%s! Splash aside!",
        "Over the spray, %s!",
    },
    grave = {
        "%s! Behind a stone!",
        "%s! Into the dark!",
        "Fade back, %s!",
    },
    indoor = {
        "%s! Behind cover!",
        "%s! Use the wall!",
        "Clear the floor, %s!",
    },
}
S.BRACE_SCENE = {
    cave = {
        "%s! Brace on the rock!",
        "%s! Dig in here!",
    },
    forest = {
        "%s! Root in place!",
        "%s! Hold the line!",
    },
    city = {
        "%s! Hold the street!",
        "%s! Stand your ground!",
    },
    route = {
        "%s! Hold firm!",
        "%s! Hold the path!",
    },
    mountain = {
        "%s! Brace on stone!",
        "%s! Don't slip!",
    },
    gym = {
        "%s! Center court-hold!",
        "%s! Guard the mark!",
    },
    water = {
        "%s! Brace in the surf!",
        "%s! Hold the tide!",
    },
    grave = {
        "%s! Stand your ground!",
        "%s! Don't yield!",
    },
    indoor = {
        "%s! Hold the room!",
        "%s! Brace up!",
    },
}
S.DODGE_TYPE = {
    FLYING = {
        "%s! Fly up high!",
        "%s! Take the air!",
        "Wing it, %s! Up!",
    },
    WATER = {
        "%s! Dive aside!",
        "%s! Ride the splash!",
    },
    FIRE = {
        "%s! Burst aside!",
        "%s! Heat-dash clear!",
    },
    ELECTRIC = {
        "%s! Zip aside!",
        "%s! Spark-step!",
    },
    GRASS = {
        "%s! Into the leaves!",
        "%s! Bloom-step clear!",
    },
    PSYCHIC = {
        "%s! Sense-and move!",
        "%s! Bend aside!",
    },
    GHOST = {
        "%s! Fade through!",
        "%s! Phase aside!",
    },
    BUG = {
        "%s! Flutter clear!",
        "%s! Buzz aside!",
    },
    GROUND = {
        "%s! Dust-dash!",
        "%s! Low and aside!",
    },
    ROCK = {
        "%s! Stone-step clear!",
    },
    ICE = {
        "%s! Slide clear!",
    },
    DRAGON = {
        "%s! Soar clear!",
    },
    POISON = {
        "%s! Slip aside!",
    },
    FIGHTING = {
        "%s! Bob and weave!",
    },
}
S.BRACE_TYPE = {
    FIGHTING = {
        "%s! Guard up!",
        "%s! Tough it out!",
    },
    ROCK = {
        "%s! Be the boulder!",
        "%s! Rock-solid!",
    },
    GROUND = {
        "%s! Root down!",
    },
    STEEL = {
        "%s! Steel yourself!",
    },
    NORMAL = {
        "%s! Tough it out!",
    },
    WATER = {
        "%s! Roll with the wave!",
    },
    FLYING = {
        "%s! Hover-and hold!",
    },
}
S.NAMED_TRAINERS = {
    BROCK = true,
    MISTY = true,
    ["LT.SURGE"] = true,
    ERIKA = true,
    KOGA = true,
    SABRINA = true,
    BLAINE = true,
    GIOVANNI = true,
    LORELEI = true,
    BRUNO = true,
    AGATHA = true,
    LANCE = true,
    ["PROF.OAK"] = true,
    CHIEF = true,
    ROCKET = true,
}
S.TRAINER_MOVE_CALLS = {
    "%s:\n%s, use %s!",
    "%s:\n%s! %s!",
    "%s:\nGo, %s! %s!",
    "%s:\n%s, %s!",
    "%s:\n%s, now! %s!",
    "%s:\nDo it, %s! %s!",
}
S.FOE_MOVE_CALLS = {
    "%s!\nUse %s!",
    "%s, use\n%s!",
    "Go, %s!\n%s!",
    "%s!\n%s!",
    "%s!\n%s, now!",
    "%s!\nQuick, %s!",
    "Come on,\n%s! %s!",
}
S.BATTLE_TEXT_COLS = 18
S.DODGE_FAIL_CALLS = {
    "...but it was\ntoo slow!",
}
S.DODGE_TOO_SLOW = "...but it was\ntoo slow!"
S.PAR_REACT_FAIL = "...but it couldn't\nmove right!"
S.PAR_SHAKE_CALLS = {
    "%s shook off\nthe paralysis!",
    "%s's body\nlimbered up!",
    "%s fought through\nthe paralysis!",
    "The paralysis\nleft %s!",
}
S.COVER_HIT_CALLS = {
    "But it found\n%s!",
    "Still got hit,\n%s!",
    "%s!\nHit through cover!",
    "Cover wasn't\nenough!",
}
S.DODGE_WHIFF_CALLS = {
    "But %s\ndodged aside!",
    "%s slipped\naway!",
    "Too slow!\n%s dodged!",
    "The attack\nwhiffed past!",
    "%s!\nSafe in cover!",
}
S.VANISH_CHANCE = 0.40
S.VANISH_EVADE_BONUS = 1
S.VANISH_CALLS = {
    "Vanished from\nthe foe's sight!",
    "%s vanished from\nsight!",
    "Out of the foe's\nsight!",
    "%s slipped from\nview!",
    "Gone from view!",
    "%s melted into\ncover!",
    "Can't be seen!",
    "%s winked out of\nsight!",
}
S.DODGE_EVADE_ROLL = {
    basic = { 1, 1, 1, 1, 2, 2 },
    hide = { 1, 2, 2, 2, 2, 3, 3, 3, 3, 4 },
}
S.DODGE_EVADE_HIGH_CALLS = {
    "Sharp instincts!",
    "Perfect timing!",
    "%s moved like\na blur!",
    "What a read!",
}
S.BREAKTHROUGH_CALLS = {
    "Broke through\nthe guard!",
    "The defense\nshattered!",
    "Pushed past\n%s!",
    "Guard broken!\n%s!",
}
S.LEAVE_COVER_CALLS = {
    "%s!\nLeft cover!",
    "Breaking cover,\n%s!",
    "%s!\nComing out!",
    "Leave cover,\n%s! Strike!",
    "%s!\nCome out!",
    "Out of hiding,\n%s!",
    "%s!\nSurface and\nstrike!",
}
S.HOLD_POSITION_CALLS = {
    "%s!\nHold on!",
    "Stay in cover,\n%s!",
    "%s!\nKeep hiding!",
    "Hold tight,\n%s!",
    "%s!\nDon't come out!",
    "Stay put,\n%s!",
    "%s!\nKeep cover!",
    "Stay ready\nin cover, %s!",
}
S.DEEP_COVER_CHANCE = 0.30
S.DEEP_COVER_CALLS = {
    TREE = {
        "%s is still\nup the tree!",
        "%s can't climb\ndown yet!",
        "Still perched-\n%s, hold!",
    },
    BRUSH = {
        "%s is deep in\nthe brush!",
        "Can't leave the\nthicket yet!",
    },
    GRASS = {
        "%s is buried\nin the grass!",
        "Still hidden in\nthe tall grass!",
    },
    ROCK = {
        "%s is pinned\nbehind a rock!",
        "Can't leave the\nboulder yet!",
    },
    STONE = {
        "%s ducks behind\nthe stone!",
        "Still behind the\nstone!",
    },
    CLIFF = {
        "%s is stuck up\nthe cliff!",
        "Can't descend\nyet!",
    },
    LEDGE = {
        "%s clings to\nthe ledge!",
        "Still on the\nledge!",
    },
    ["FLY UP"] = {
        "%s is still\nhigh above!",
        "%s can't land\nyet!",
        "Still airborne-\nhold!",
    },
    DIVE = {
        "%s is still\nunderwater!",
        "%s can't surface\nyet!",
        "Deep below-\nhold breath!",
    },
    SPLASH = {
        "%s is still\nin the water!",
        "Can't leave the\nwaves yet!",
    },
    SHORE = {
        "%s hugs the\nshoreline!",
        "Still along the\nshore!",
    },
    CART = {
        "%s is tucked\nbehind the cart!",
        "Still using the\ncart for cover!",
    },
    ALLEY = {
        "%s is deep in\nthe alley!",
        "Can't leave the\nalley yet!",
    },
    PILLAR = {
        "%s stays behind\nthe pillar!",
        "Still using the\npillar!",
    },
    SHADOW = {
        "%s is lost in\nthe dark!",
        "Still in the\nshadows!",
    },
    COVER = {
        "%s can't leave\ncover yet!",
        "Still dug in-\nhold!",
    },
    WALL = {
        "%s presses to\nthe wall!",
        "Still using the\nwall!",
    },
    _default = {
        "%s can't leave\ncover yet!",
        "%s is stuck in\nhiding!",
        "Too deep in\ncover-hold!",
        "%s needs a\nmoment more!",
    },
}
S.SCENE_COVER_SPOT = {
    forest = "TREE",
    cave = "ROCK",
    water = "DIVE",
    mountain = "CLIFF",
    grave = "STONE",
    route = "GRASS",
    city = "CART",
    gym = "PILLAR",
    indoor = "COVER",
}
S.AMBIENT_DELAY = 2.2
S.AMBIENT_DELAY_JITTER = 1.0
S.AMBIENT_BRACE_MOVES = {
    "HARDEN", "WITHDRAW", "DEFENSE_CURL", "HARDEN", "MEDITATE",
}
S.AMBIENT_ENTRENCH_MOVES = {
    "HARDEN", "BARRIER", "WITHDRAW", "ACID_ARMOR", "HARDEN",
}
S.AMBIENT_HIDE_MOVES = {
    GRASS = { "GROWTH", "RAZOR_LEAF", "GROWTH", "VINE_WHIP" },
    BRUSH = { "GROWTH", "RAZOR_LEAF", "STUN_SPORE" },
    TREE = { "GROWTH", "RAZOR_LEAF", "LEECH_SEED" },
    DIVE = { "SURF", "WITHDRAW", "BUBBLE", "CLAMP" },
    SPLASH = { "SURF", "WATER_GUN", "BUBBLE" },
    SHORE = { "SURF", "WATER_GUN", "SAND_ATTACK" },
    ROCK = { "DIG", "ROCK_THROW", "HARDEN" },
    STONE = { "DIG", "ROCK_THROW", "HARDEN" },
    LEDGE = { "DIG", "QUICK_ATTACK" },
    CLIFF = { "DIG", "FLY", "ROCK_SLIDE" },
    ["FLY UP"] = { "FLY", "GUST", "WING_ATTACK", "SKY_ATTACK" },
    PATH = { "DIG", "SAND_ATTACK", "DOUBLE_TEAM" },
    CART = { "DOUBLE_TEAM", "SMOKESCREEN", "DIG" },
    ALLEY = { "SMOKESCREEN", "DOUBLE_TEAM", "DIG" },
    SHADOW = { "NIGHT_SHADE", "TELEPORT", "LICK" },
    PILLAR = { "BARRIER", "HARDEN", "REFLECT" },
    WALL = { "BARRIER", "HARDEN", "REFLECT" },
    COURT = { "DOUBLE_TEAM", "QUICK_ATTACK" },
    COVER = { "DIG", "DOUBLE_TEAM", "MINIMIZE" },
    ZIP = { "FLASH", "THUNDER_WAVE", "DOUBLE_TEAM" },
    BURST = { "SMOKESCREEN", "EMBER", "FLAMETHROWER", "FIRE_SPIN" },
    FADE = { "TELEPORT", "NIGHT_SHADE" },
    SENSE = { "CONFUSION", "TELEPORT", "DISABLE" },
}
S.COVER_CALLS = {
    "%s! Take cover!",
    "Get down, %s!",
    "%s! Behind cover!",
    "Hide, %s!",
    "%s! Use cover!",
}
S.COMMIT_CALLS = {
    "%s! Take it!",
    "Hang in there, %s!",
    "%s! You can take this!",
    "Endure it, %s!",
    "%s! Don't give in!",
}
S.FIRE_NOW_CALLS = {
    "%s! Now!",
    "Hit them, %s!",
    "%s! While they're open!",
    "Fire, %s!",
}
S.ENTRENCH_MAX_TURNS = 3
S.STAY_ENTRENCHED_CALLS = {
    "Stay entrenched, %s!",
    "%s! Hold the trench!",
    "Keep digging in, %s!",
    "%s! Stay firm!",
    "Don't break, %s!",
    "%s! Weather it!",
}
S.BREAK_ENTRENCH_CALLS = {
    "%s! Break stance!",
    "Enough- %s, move!",
    "%s! Can't hold!",
}
S.TRAINER_FOE_DODGE_CALLS = {
    "%s: %s, dodge!",
    "%s: Dodge it, %s!",
    "%s: %s, get aside!",
    "%s: Move, %s!",
    "%s: %s, now-dodge!",
}
S.FOE_DODGE_CALLS = {
    "%s! Dodge it!",
    "%s, get aside!",
    "%s! Move!",
    "Quick, %s! Dodge!",
}
S.TRAINER_FOE_BRACE_CALLS = {
    "%s: %s, brace!",
    "%s: Dig in, %s!",
    "%s: %s, hold firm!",
    "%s: Stand firm, %s!",
}
S.FOE_BRACE_CALLS = {
    "%s! Brace!",
    "%s, dig in!",
    "%s! Hold firm!",
    "Stand firm, %s!",
}
S.TRAINER_FOE_COUNTER_CALLS = {
    "%s: %s, hit back!",
    "%s: Counter, %s!",
    "%s: Now, %s! Strike!",
}
S.FOE_COUNTER_CALLS = {
    "%s! Hit back!",
    "%s! Counter!",
    "Now, %s! Strike!",
}
S.TRAINER_FOE_COUNTER_BACK_CALLS = {
    "%s: Too slow! %s, counter!",
    "%s: %s! Punish that!",
    "%s: Got you! Counter, %s!",
}
S.FOE_COUNTER_BACK_CALLS = {
    "%s! Counters!",
    "Too slow! %s hits back!",
    "%s! Punished!",
}
S.TRAINER_FOE_AGAIN_CALLS = {
    "%s: Again, %s!",
    "%s: %s, once more!",
    "%s: Don't stop, %s!",
    "%s: They're open! %s, again!",
    "%s: Keep going, %s!",
    "%s: %s! One more!",
    "%s: Don't let up!",
    "%s: Hit 'em again, %s!",
}
S.FOE_AGAIN_CALLS = {
    "%s! Again!",
    "%s, once more!",
    "Don't stop, %s!",
    "They're open! %s, again!",
    "%s! One more!",
    "Don't let up! %s!",
}
S.TRAINER_FOE_LEAVE_COVER_CALLS = {
    "%s: %s, break cover!",
    "%s: Come out, %s!",
    "%s: %s, now-strike!",
}
S.FOE_LEAVE_COVER_CALLS = {
    "%s! Break cover!",
    "Come out, %s!",
    "%s, now-strike!",
}
S.AGAIN_CALLS = {
    "%s! One more!",
    "Don't stop, %s!",
    "%s! Keep going!",
    "There's an opening—hit again!",
    "They're reeling—one more time!",
    "Now's your chance, %s!",
    "Don't let up, %s!",
    "Press in! %s, again!",
    "You've got them! Again!",
    "They're open—strike again!",
    "%s! Finish it!",
    "Keep up the pressure!",
    "One more hit, %s!",
    "Go again, %s!",
    "Don't give them space!",
    "You have the opening—again!",
    "%s! Hit again!",
}
S.BANTER = {
    kid = {
        player = {
            "%s: A %s, huh?! Looks tough!",
            "%s: Wow, a %s!",
            "%s: %s looks so cool!",
            "%s: Hi, %s! Let's play!",
            "%s: Whoa! A real %s!",
            "%s: %s?! I want one!",
            "%s: Your %s is awesome!",
            "%s: Neat! A %s!",
            "%s: Is %s your favorite?",
            "%s: A %s... I'm nervous!",
        },
        enemy = {
            "%s: Go, %s!",
            "%s: Do your best, %s!",
            "%s: I believe in %s!",
            "%s: You can do it, %s!",
            "%s: Show them, %s!",
            "%s: Ready, %s?!",
            "%s: Please win, %s!",
            "%s: Go go go, %s!",
        },
        idle = {
            "%s: This is fun!",
            "%s: You're good!",
            "%s: Nice moves!",
            "%s: Wow!",
            "%s: My heart's racing!",
            "%s: Best battle ever!",
            "%s: Don't go easy!",
            "%s: I'm learning so much!",
            "%s: Again! Again!",
            "%s: This rules!",
        },
        ahead = {
            "%s: Am I winning?!",
            "%s: Yes! Go me!",
            "%s: I'm doing it!",
            "%s: See? I'm good!",
        },
        behind = {
            "%s: Uh-oh...",
            "%s: Wait, no fair!",
            "%s: I can still catch up!",
            "%s: Don't cry... focus!",
        },
        player_weak = {
            "%s: One more? Maybe?",
            "%s: Your mon looks tired...",
            "%s: Hang in there!",
        },
        self_weak = {
            "%s: Ow ow ow!",
            "%s: We're okay! ...Right?",
            "%s: Don't give up!",
        },
        long = {
            "%s: So long... but cool!",
            "%s: My legs are tired!",
            "%s: Still going?!",
        },
    },
    cocky = {
        player = {
            "%s: A %s? That all?",
            "%s: %s? Hah! Weak!",
            "%s: Don't bore me with %s!",
            "%s: %s... Easy prey!",
            "%s: %s? Cute. Not enough!",
            "%s: Bringing %s? Bold.",
            "%s: I've beaten better than %s!",
            "%s: %s won't last a minute!",
            "%s: Stand aside, %s!",
            "%s: Try harder than %s next time!",
        },
        enemy = {
            "%s: Crush them, %s!",
            "%s: Show off, %s!",
            "%s: No contest!",
            "%s: Flex on them, %s!",
            "%s: End this, %s!",
            "%s: Make it flashy, %s!",
            "%s: Don't blink- %s!",
            "%s: Own the field, %s!",
        },
        idle = {
            "%s: Too easy!",
            "%s: Wake me when it's over!",
            "%s: Is that it?",
            "%s: Yawn...",
            "%s: Speed it up!",
            "%s: I'm barely trying!",
            "%s: Come on, impress me!",
            "%s: Predictable!",
            "%s: I've seen worse... barely!",
            "%s: Step it up!",
        },
        ahead = {
            "%s: Outmatched!",
            "%s: As expected!",
            "%s: Too slow!",
            "%s: Know your league!",
            "%s: This is why I'm top tier!",
            "%s: Don't look so surprised!",
        },
        behind = {
            "%s: Hmph-fine!",
            "%s: Don't celebrate!",
            "%s: A fluke. Nothing more!",
            "%s: Tch... lucky!",
            "%s: I'm just toying with you!",
        },
        player_weak = {
            "%s: Finish it!",
            "%s: They're done!",
            "%s: Tap out already!",
            "%s: One hit left. Maybe.",
            "%s: Smell the defeat!",
        },
        self_weak = {
            "%s: Whatever- still winning!",
            "%s: I meant to take that!",
            "%s: Cute hit. My turn!",
        },
        long = {
            "%s: Dragging this? Rude!",
            "%s: Wrap it up!",
            "%s: I'm getting bored again!",
        },
   
    },
    evil = {
        player = {
            "%s: A %s...? Hand it over to Team Rocket!",
            "%s: %s? That's nothing special!",
            "%s: That %s is blocking our plans!",
            "%s: Hmm, a %s... Could be valuable!",
            "%s: %s looks easy to take!",
            "%s: We'll wipe out %s and take what we want!",
            "%s: Another %s to capture!",
            "%s: Keep %s out of Team Rocket's way!",
            "%s: %s... won't save you now!",
            "%s: We'll steal it later. Take down %s first!",
        },
        enemy = {
            "%s: Go, %s! Show them Team Rocket's strength!",
            "%s: Make them regret facing us!",
            "%s: No mercy, %s!",
            "%s: Crush them, %s!",
            "%s: Show no pity, %s!",
            "%s: Attack now, %s!",
            "%s: Obey, %s! No holding back!",
            "%s: Make them fear Team Rocket, %s!",
        },
   
        idle = {
            "%s: This is Team Rocket's show!",
            "%s: Nobody outsmarts Team Rocket!",
            "%s: Heh heh heh...",
            "%s: You can't run from us!",
            "%s: Your journey ends here!",
            "%s: Team Rocket always comes out on top!",
            "%s: Squirm a bit more for us!",
            "%s: Crime pays—watch and learn!",
            "%s: You'll hand over your cash eventually!",
        },
        ahead = {
            "%s: You can't win!",
            "%s: Just as we planned!",
            "%s: Too easy for Team Rocket!",
            "%s: Music to our ears!",
            "%s: You fell for Team Rocket's trap!",
        },
        behind = {
            "%s: This can't be...!",
            "%s: You'll pay for that!",
            "%s: Just a minor setback!",
            "%s: The boss will hear about this...",
        },
        player_weak = {
            "%s: Give up already!",
            "%s: It's finished!",
            "%s: Down on your knees!",
            "%s: End them! Show no mercy!",
            "%s: That Pokémon is done for!",
        },
        self_weak = {
            "%s: You'll regret that!",
            "%s: You haven't won yet!",
            "%s: I'll double down on you!",
        },
        long = {
            "%s: We don't have all day—lose already!",
            "%s: A %s...? Hand it over!",
            "%s: %s? Pathetic!",
            "%s: That %s is in our way!",
            "%s: Hmm, a %s... Useful!",
            "%s: %s looks ripe for taking!",
            "%s: We'll crush %s and move on!",
            "%s: Another %s to break!",
            "%s: Keep %s out of Rocket business!",
            "%s: %s... won't save you!",
            "%s: Steal? Later. Beat %s first!",
        },
        enemy = {
            "%s: Get them, %s!",
            "%s: Make it hurt!",
            "%s: No mercy!",
            "%s: Ruin them, %s!",
            "%s: Show no pity, %s!",
            "%s: Tear in, %s!",
            "%s: Obey me, %s!",
            "%s: Make them scream, %s!",
        },
   
        idle = {
            "%s: Prepare to suffer!",
            "%s: Heh heh heh...",
            "%s: No escape!",
            "%s: Your hopes end here!",
            "%s: We always win in the end!",
            "%s: Squirm a little more!",
            "%s: Crime pays- watch!",
        },
        ahead = {
            "%s: Yes... suffer!",
            "%s: All according to plan!",
            "%s: Broken already?",
            "%s: Fall for Team Rocket!",
        },
        behind = {
            "%s: How are you ahead? Impossible...!",
            "%s: You'll regret that!",
            "%s: A setback- nothing more!",
            "%s: Boss won't like this...",
        },
        player_weak = {
            "%s: Beg for mercy!",
            "%s: It's over!",
            "%s: Kneel!",
            "%s: Finish the worm!",
            "%s: Your mon is done!",
        },
        self_weak = {
            "%s: How dare you!",
            "%s: This changes nothing!",
            "%s: I'll make you pay double!",
        },
        long = {
            "%s: Stop stalling and lose!",
            "%s: Our time is money!",
            "%s: Endurance? How quaint!",
        },
   
    },
    gym = {
        player = {
            "%s: A %s, huh? Interesting!",
            "%s: %s... Show me its skill!",
            "%s: So you chose %s!",
            "%s: That %s looks trained!",
            "%s: %s carries your pride, yes?",
            "%s: A worthy %s. Come then!",
            "%s: I see the care in that %s!",
            "%s: %s... let's test its spirit!",
            "%s: Gym rules: hold nothing back!",
            "%s: Your %s meets my standard!",
        },
        enemy = {
            "%s: Go, %s!",
            "%s: This is a real battle!",
            "%s: Don't hold back!",
            "%s: Show our gym's strength, %s!",
            "%s: Stand tall, %s!",
            "%s: Earn this win, %s!",
            "%s: Press the advantage, %s!",
            "%s: Battle with honor, %s!",
        },
        idle = {
            "%s: Stay focused!",
            "%s: Good-keep it up!",
            "%s: Not bad!",
            "%s: Prove yourself!",
            "%s: Read the next exchange!",
            "%s: Breathe. Then strike!",
            "%s: That's the spirit!",
            "%s: Pressure makes diamonds!",
            "%s: A Leader expects your best!",
            "%s: Don't freeze-adapt!",
        },
        ahead = {
            "%s: Feel the gap in skill!",
            "%s: Push harder!",
            "%s: This is gym-level play!",
            "%s: Can you climb back?",
            "%s: Experience talks!",
        },
        behind = {
            "%s: Well done-don't stop!",
            "%s: You've grown!",
            "%s: Impressive...again!",
            "%s: I won't yield easily!",
            "%s: Good! Make me work for it!",
        },
        player_weak = {
            "%s: Finish with pride!",
            "%s: One decisive blow!",
            "%s: Your mon is on the ropes!",
        },
        self_weak = {
            "%s: A Leader still stands!",
            "%s: Pain sharpens focus!",
            "%s: Now it gets serious!",
        },
        long = {
            "%s: A true test of endurance!",
            "%s: This is a fine battle!",
            "%s: Long battles forge trainers!",
            "%s: Neither backing down-good!",
        },
    },
    rival = {
        player = {
            "%s: A %s, huh?! Looks tough! ...As if!",
            "%s: %s?! Don't make me laugh!",
            "%s: That %s? Pathetic!",
            "%s: Oh, a %s... Smell ya later!",
            "%s: %s? Still weak!",
            "%s: Hah! A %s? What a joke!",
            "%s: Bringing %s? Outclassed!",
            "%s: %s won't save you!",
            "%s: %s again? Predictable!",
            "%s: Your precious %s? Please!",
            "%s: Gramps would laugh at %s!",
            "%s: I outgrew %s already!",
        },
        enemy = {
            "%s: Go! %s!",
            "%s: Watch this!",
            "%s: I'm the best!",
            "%s: Show them up, %s!",
            "%s: Crush this chump!",
            "%s: Easy win, %s!",
            "%s: Make it hurt, %s!",
            "%s: Don't hold back!",
            "%s: My %s eats losers!",
            "%s: Style points, %s!",
            "%s: Wipe that look off- %s!",
            "%s: Teach them, %s!",
        },
        idle = {
            "%s: Bored yet?",
            "%s: I'm just warming up!",
            "%s: You call this a fight?",
            "%s: Try harder!",
            "%s: Still think you can win?",
            "%s: Hahaha!",
            "%s: My grandpa's stronger!",
            "%s: Give it up!",
            "%s: You're wasting my time!",
            "%s: Come on, make it fun!",
            "%s: I've got places to be!",
            "%s: Smell ya-soon!",
            "%s: That all the fire you've got?",
            "%s: Keep up if you can!",
        },
        ahead = {
            "%s: Told you I was better!",
            "%s: This is too easy!",
            "%s: You're finished!",
            "%s: Hah! Know your place!",
            "%s: Maybe forfeit?",
            "%s: I'm in a whole other league!",
            "%s: Should've stayed home!",
            "%s: Who's the loser now?!",
        },
        behind = {
            "%s: Lucky shot...",
            "%s: Don't get cocky!",
            "%s: That won't happen again!",
            "%s: Tch-whatever!",
            "%s: I'm not done yet!",
            "%s: Beginner's luck!",
            "%s: You just got lucky, twerp!",
            "%s: I'll wipe that grin off!",
        },
        player_weak = {
            "%s: Look at that HP!",
            "%s: Almost done!",
            "%s: One more hit!",
            "%s: Going down!",
            "%s: Savor it-you lose!",
            "%s: Say goodbye!",
            "%s: Any last words?",
        },
        self_weak = {
            "%s: N-no big deal!",
            "%s: I meant to do that!",
            "%s: Shut up!",
            "%s: This isn't over!",
            "%s: You'll pay for that!",
            "%s: Don't you dare laugh!",
            "%s: I was going easy!",
        },
        long = {
            "%s: Still dragging this out?",
            "%s: Hurry up and lose!",
            "%s: I'm getting impatient!",
            "%s: End this already!",
            "%s: What, writing a novel?!",
            "%s: Finish strong or fold!",
        },
    },
    spooky = {
        player = {
            "%s: A %s... Ooooh...",
            "%s: %s... Spirits stir...",
            "%s: That %s... How dreadful!",
            "%s: %s walks with shadows...",
            "%s: I feel a chill from %s...",
            "%s: %s... will you scream for us?",
            "%s: The veil thins near %s...",
            "%s: Such a living %s... curious!",
        },
        enemy = {
            "%s: Rise, %s!",
            "%s: Haunt them!",
            "%s: From beyond...",
            "%s: Awaken, %s!",
            "%s: Drain their hope, %s!",
            "%s: Whisper ruin, %s!",
            "%s: Possess the field, %s!",
            "%s: Night falls- %s!",
        },
        idle = {
            "%s: I sense fear...",
            "%s: The spirits watch...",
            "%s: Hee hee hee...",
            "%s: Do you hear them too?",
            "%s: This place remembers...",
            "%s: Your pulse is loud...",
            "%s: Don't look behind you...",
            "%s: Cold air...good omen!",
            "%s: The candles flicker for you!",
            "%s: Join us...eventually!",
        },
        ahead = {
            "%s: Yes... sink...",
            "%s: Your light fades!",
            "%s: The spirits approve!",
            "%s: Terror suits you!",
        },
        behind = {
            "%s: Impossible warmth...!",
            "%s: The dead grow restless!",
            "%s: A bright spark ...annoying!",
        },
        player_weak = {
            "%s: One step from the grave!",
            "%s: Say goodnight!",
            "%s: Your soul wavers!",
        },
        self_weak = {
            "%s: Pain is only a whisper!",
            "%s: We do not stay down!",
            "%s: From ash...again!",
        },
        long = {
            "%s: An endless vigil...",
            "%s: Time means nothing here!",
            "%s: Still bound to this duel...",
        },
    },
    nerd = {
        player = {
            "%s: A %s! Fascinating!",
            "%s: %s... Statistically notable!",
            "%s: Hmm, %s... Interesting data!",
            "%s: %s matches my models... mostly!",
            "%s: Recording %s for science!",
            "%s: A %s specimen! Excellent!",
            "%s: %s's typing...intriguing!",
            "%s: I'll need notes on that %s!",
            "%s: Probability favors... wait!",
            "%s: %s appears well-trained!",
        },
        enemy = {
            "%s: Deploy %s!",
            "%s: Optimal pick: %s!",
            "%s: As calculated!",
            "%s: Initialize, %s!",
            "%s: Run protocol %s!",
            "%s: Variable %s-engage!",
            "%s: Hypothesis: %s wins!",
            "%s: Field test- %s!",
        },
        idle = {
            "%s: As expected! Just as my models predicted for this matchup.",
            "%s: Collecting data—your tactics are worth studying in battle.",
            "%s: Hypothesis holds! Your Pokémon fits the scenario perfectly.",
            "%s: Recalculating... Your move changed my equation.",
            "%s: Variance accepted! These results still fit my battle data.",
            "%s: Noted—your technique deserves further analysis.",
            "%s: This exchange is a fascinating clash of skill and stats.",
            "%s: My charts anticipated your last attack.",
            "%s: Awaiting peer review—these conclusions need more tests.",
            "%s: Science and skill are carrying me through this fight!",
        },
   
        ahead = {
            "%s: Result matches forecast!",
            "%s: Superior parameters!",
            "%s: Your error margin grows!",
            "%s: Q.E.D.!",
        },
        behind = {
            "%s: Anomaly detected!",
            "%s: Recalibrate! Quickly!",
            "%s: Outliers...humbling!",
            "%s: I must revise my thesis!",
        },
        player_weak = {
            "%s: Critical HP threshold!",
            "%s: One more data point to KO!",
            "%s: Collapse is imminent!",
        },
        self_weak = {
            "%s: Unexpected damage spike!",
            "%s: Still within recovery!",
            "%s: Pain is just feedback!",
        },
        long = {
            "%s: Sample size: getting large!",
            "%s: A lengthy trial... good!",
            "%s: Endurance is a variable too!",
        },
    },
    chill = {
        player = {
            "%s: A %s, huh? Looks tough!",
            "%s: Fine %s you've got!",
            "%s: %s, eh? Good luck!",
            "%s: Nice pick- %s!",
            "%s: Respect for that %s!",
            "%s: %s seems well cared for!",
            "%s: A solid %s. Let's enjoy!",
            "%s: Hey there, %s!",
            "%s: No hard feelings either way!",
            "%s: %s... this'll be pleasant!",
        },
        enemy = {
            "%s: Go on, %s!",
            "%s: Steady now!",
            "%s: Let's enjoy this!",
            "%s: Easy does it, %s!",
            "%s: You've got this, %s!",
            "%s: Smooth and steady, %s!",
            "%s: Take your time, %s!",
            "%s: Have fun out there, %s!",
        },
        idle = {
            "%s: Nice pace!",
            "%s: Well fought!",
            "%s: Carry on!",
            "%s: Good clean fight!",
            "%s: Love a fair battle!",
            "%s: No rush-do your thing!",
            "%s: You're sharp today!",
            "%s: This is the good stuff!",
            "%s: Breathe in...battle out!",
            "%s: Respect either way!",
        },
        ahead = {
            "%s: Looks like my edge for now!",
            "%s: Hang in-you're doing fine!",
            "%s: I've got a bit of room!",
        },
        behind = {
            "%s: You've got me on the ropes!",
            "%s: Nicely done-truly!",
            "%s: I'm impressed! Really!",
        },
        player_weak = {
            "%s: Your mon's fading...",
            "%s: Tough spot-stay calm!",
            "%s: One more good hit maybe!",
        },
        self_weak = {
            "%s: Oof-that stung!",
            "%s: We're alright! Still in it!",
            "%s: Shaky... but smiling!",
        },
        long = {
            "%s: A leisurely slugfest!",
            "%s: No place I'd rather be!",
            "%s: Long battles are the best!",
        },
    },
    generic = {
        player = {
            "%s: A %s, huh?! Looks tough!",
            "%s: Oh, a %s!",
            "%s: %s, eh? Let's battle!",
            "%s: That %s looks ready!",
            "%s: So it's %s! Alright!",
            "%s: A %s... Here we go!",
            "%s: Facing %s? Okay!",
            "%s: Your %s looks sharp!",
            "%s: Bring it, %s!",
            "%s: I've trained for %s!",
        },
        enemy = {
            "%s: Go, %s!",
            "%s: You're up!",
            "%s: Do it!",
            "%s: I choose you, %s!",
            "%s: Let's win this, %s!",
            "%s: Trust me, %s!",
            "%s: Now, %s!",
            "%s: Give it your all, %s!",
        },
        idle = {
            "%s: Come on!",
            "%s: Let's go!",
            "%s: Keep it up!",
            "%s: Focus!",
            "%s: We can do this!",
            "%s: Stay sharp!",
            "%s: Nice exchange!",
            "%s: Don't blink!",
            "%s: Push forward!",
            "%s: Battle on!",
        },
        ahead = {
            "%s: We've got the lead!",
            "%s: Keep pressing!",
            "%s: Looking good!",
        },
        behind = {
            "%s: We're not out yet!",
            "%s: Turn it around!",
            "%s: Dig deep!",
        },
        player_weak = {
            "%s: They're nearly done!",
            "%s: Finish strong!",
            "%s: Almost there!",
        },
        self_weak = {
            "%s: Hold on!",
            "%s: We can still win!",
            "%s: Not yet!",
        },
        long = {
            "%s: What a drawn-out fight!",
            "%s: Endurance wins battles!",
            "%s: Still standing-good!",
        },
    },
       
}
S.SCENE_PICK = {
    cave = {
        { label = "ROCK",  line = "%s!\nOnto that rock!", boost = 2 },
        { label = "LEDGE", line = "%s!\nUp that ledge!",  boost = 2 },
        { label = "DODGE", line = "%s!\nDodge it!",       boost = 1 },
    },
    forest = {
        { label = "TREE",  line = "%s!\nBehind that tree!", boost = 2 },
        { label = "BRUSH", line = "%s!\nInto the brush!",   boost = 2 },
        { label = "DODGE", line = "%s!\nDodge it!",         boost = 1 },
    },
    city = {
        { label = "CART",  line = "%s!\nBehind that cart!", boost = 2 },
        { label = "ALLEY", line = "%s!\nUse that alley!",   boost = 2 },
        { label = "DODGE", line = "%s!\nDodge it!",         boost = 1 },
    },
    route = {
        { label = "GRASS", line = "%s!\nInto the grass!", boost = 2 },
        { label = "PATH",  line = "%s!\nOff the path!",   boost = 1 },
        { label = "DODGE", line = "%s!\nDodge it!",       boost = 1 },
    },
    mountain = {
        { label = "CLIFF", line = "%s!\nUp that cliff!", boost = 2 },
        { label = "LEDGE", line = "%s!\nUse the ledge!", boost = 2 },
        { label = "DODGE", line = "%s!\nDodge it!",      boost = 1 },
    },
    gym = {
        { label = "PILLAR", line = "%s!\nUse the pillars!",  boost = 2 },
        { label = "COURT",  line = "%s!\nAround the court!", boost = 1 },
        { label = "DODGE",  line = "%s!\nDodge it!",         boost = 1 },
    },
    water = {
        { label = "SHORE",  line = "%s!\nAlong the shore!", boost = 2 },
        { label = "SPLASH", line = "%s!\nSplash aside!",    boost = 2 },
        { label = "DODGE",  line = "%s!\nDodge it!",        boost = 1 },
    },
    grave = {
        { label = "STONE",  line = "%s!\nBehind a stone!", boost = 2 },
        { label = "SHADOW", line = "%s!\nInto the dark!",  boost = 2 },
        { label = "DODGE",  line = "%s!\nDodge it!",       boost = 1 },
    },
    indoor = {
        { label = "WALL",  line = "%s!\nUse the wall!", boost = 2 },
        { label = "COVER", line = "%s!\nBehind cover!", boost = 2 },
        { label = "DODGE", line = "%s!\nDodge it!",     boost = 1 },
    },
}
S.SCENE_BRACE_PICK = {
    cave = {
        { label = "ROCK",   line = "%s!\nBrace on the rock!", boost = 2 },
        { label = "DIG IN", line = "%s!\nDig in here!",       boost = 2 },
        { label = "BRACE",  line = "%s!\nBrace yourself!",    boost = 1 },
    },
    forest = {
        { label = "ROOTS", line = "%s!\nRoot in place!",  boost = 2 },
        { label = "HOLD",  line = "%s!\nHold the line!",  boost = 1 },
        { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    city = {
        { label = "STREET", line = "%s!\nHold the street!",   boost = 2 },
        { label = "GROUND", line = "%s!\nStand your ground!", boost = 1 },
        { label = "BRACE",  line = "%s!\nBrace yourself!",    boost = 1 },
    },
    route = {
        { label = "PATH",   line = "%s!\nHold the path!",  boost = 1 },
        -- Strong brace: high DEF, but next attack is locked out (body-agnostic).
        { label = "DIG IN", line = "%s!\nEntrench!",       boost = 2, entrench = true },
        { label = "BRACE",  line = "%s!\nBrace yourself!", boost = 1 },
    },
    mountain = {
        { label = "STONE", line = "%s!\nBrace on stone!", boost = 2 },
        { label = "HOLD",  line = "%s!\nDon't slip!",     boost = 1 },
        { label = "BRACE", line = "%s!\nBrace yourself!", boost = 1 },
    },
    gym = {
        { label = "COURT", line = "%s!\nCenter court-hold!", boost = 2 },
        { label = "GUARD", line = "%s!\nGuard the mark!",    boost = 1 },
        { label = "BRACE", line = "%s!\nBrace yourself!",    boost = 1 },
    },
    water = {
        { label = "SURF",  line = "%s!\nBrace in the surf!", boost = 2 },
        { label = "TIDE",  line = "%s!\nHold the tide!",     boost = 1 },
        { label = "BRACE", line = "%s!\nBrace yourself!",    boost = 1 },
    },
    grave = {
        { label = "STAND", line = "%s!\nStand your ground!", boost = 1 },
        { label = "HOLD",  line = "%s!\nDon't yield!",       boost = 2 },
        { label = "BRACE", line = "%s!\nBrace yourself!",    boost = 1 },
    },
    indoor = {
        { label = "ROOM",  line = "%s!\nHold the room!", boost = 1 },
        { label = "BRACE", line = "%s!\nBrace up!",      boost = 1 },
        { label = "GUARD", line = "%s!\nGuard up!",      boost = 2 },
    },
}
S.TYPE_PICK_EXTRA = {
    FLYING = { label = "FLY UP", line = "%s!\nFly up high!", boost = 2 },
    WATER = { label = "DIVE", line = "%s!\nDive aside!", boost = 2 },
    ELECTRIC = { label = "ZIP", line = "%s!\nZip aside!", boost = 2 },
    FIRE = { label = "BURST", line = "%s!\nBurst aside!", boost = 2 },
    PSYCHIC = { label = "SENSE", line = "%s!\nSense-and move!", boost = 2 },
    GHOST = { label = "FADE", line = "%s!\nFade through!", boost = 2 },
    GRASS = { label = "BRUSH", line = "%s!\nInto the leaves!", boost = 2 },
}
S.CALLOUT_AUTO_DELAY = 55
S.BANTER_CAMEO_IN = 14
S.BANTER_CAMEO_OUT = 12
S.BUBBLE_AUTO_DELAY = 75 -- kept for non-bubble fallbacks / legacy callers
S.BUBBLE_CHAR_DELAY = 7
-- Hold after a FIELD toast types out, if the player does not mash A.
S.FIELD_TOAST_DELAY = 36

return S
