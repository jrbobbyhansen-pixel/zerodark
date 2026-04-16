// TacticalCorpus.swift — Comprehensive Tactical Field Knowledge Base
// Sources: TCCC v5, FM 3-05.70 Survival, FM 4-25.11 First Aid,
//          ICS 100/200, ARRL ARES Manual, CERT Curriculum,
//          USMC Small Wars Manual principles, NPS Wilderness Survival

import Foundation
import SwiftUI

// MARK: - TacticalCorpus

class TacticalCorpus: ObservableObject {
    static let shared = TacticalCorpus()

    @Published var firstAidKnowledge: [String: String] = [:]
    @Published var survivalKnowledge: [String: String] = [:]
    @Published var navigationKnowledge: [String: String] = [:]
    @Published var radioProcedures: [String: String] = [:]
    @Published var sarProtocols: [String: String] = [:]
    @Published var weatherPatterns: [String: String] = [:]
    @Published var tacticalProcedures: [String: String] = [:]
    @Published var incidentCommand: [String: String] = [:]
    @Published var signaling: [String: String] = [:]

    init() {
        loadKnowledgeBase()
    }

    // MARK: - Indexable Documents

    func allDocuments() -> [(key: String, content: String, category: String)] {
        var docs: [(key: String, content: String, category: String)] = []
        let sources: [(source: [String: String], category: String)] = [
            (firstAidKnowledge,     "First Aid"),
            (survivalKnowledge,     "Survival"),
            (navigationKnowledge,   "Navigation"),
            (radioProcedures,       "Radio"),
            (sarProtocols,          "SAR"),
            (weatherPatterns,       "Weather"),
            (tacticalProcedures,    "Tactical"),
            (incidentCommand,       "ICS"),
            (signaling,             "Signaling"),
        ]
        for (source, category) in sources {
            for (key, value) in source {
                docs.append((key: key, content: value, category: category))
            }
        }
        return docs
    }

    // MARK: - Knowledge Base Load

    private func loadKnowledgeBase() {
        loadFirstAid()
        loadSurvival()
        loadNavigation()
        loadRadio()
        loadSAR()
        loadWeather()
        loadTactical()
        loadICS()
        loadSignaling()
    }

    // MARK: - First Aid (TCCC v5 + FM 4-25.11)

    private func loadFirstAid() {
        firstAidKnowledge = [

            "MARCH Protocol": """
MARCH is the TCCC sequence for casualty care under fire and tactical field care.

M — MASSIVE HEMORRHAGE: Control life-threatening external bleeding immediately.
    • Extremity bleeding: Apply tourniquet 2–3 inches proximal to wound. Tighten until bleeding stops. Record time.
    • Junctional/truncal: Use wound packing + pressure dressing (Combat Gauze preferred — holds XA-impregnated gauze in wound for 3 min with direct pressure).
    • Do NOT remove tourniquet once applied. Note time on casualty card or tourniquet itself.

A — AIRWAY: Open and maintain airway.
    • Unconscious, breathing: Nasopharyngeal airway (NPA) — lubricate, insert through right nare, beveled end toward septum, advance until hub rests against nostril.
    • No gag reflex, apneic: Supraglottic airway or surgical cricothyrotomy.
    • Penetrating neck trauma: High index of suspicion for expanding hematoma. Prepare for surgical airway.

R — RESPIRATION: Identify and treat chest injuries.
    • Sucking chest wound: Apply vented chest seal (Hyfin or HyFin Vent) to front AND back if exit wound present.
    • Tension pneumothorax signs: Absent/decreased breath sounds, respiratory distress, tracheal deviation (late). Treatment: Needle decompression at 2nd ICS MCL with 14ga 3.25" catheter. If no improvement: 4th/5th ICS AAL. After decompression, monitor; repeat if re-tension.

C — CIRCULATION: Treat shock. IV/IO access.
    • Two large-bore IVs (18ga or larger) or IO (humeral head preferred in tactical setting).
    • Hemorrhagic shock: Whole blood preferred. If unavailable: 1:1:1 (PRBC:FFP:Platelets) or LR 1L bolus, reassess.
    • TXA: 1g in 100mL NS over 10 min within 3 hours of injury. Repeat 1g in next 8 hours. Do NOT give if >3 hours from injury or clot is forming.
    • Hypothermia prevention: Hypothermia Prevention Kit, wet clothes off, warm fluids if possible.

H — HYPOTHERMIA / HEAD:
    • Cover with hypothermia prevention blanket (reflective side in).
    • TBI: Do NOT hyperoxygenate. Monitor pupils bilaterally. Keep SpO2 >90%, SBP >90mmHg.
    • Penetrating head wound: No hyperventilation. Elevate head 30°.

E — EVERYTHING ELSE: Secondary survey, medications, evacuation.
""",

            "Tourniquet Application": """
TCCC TOURNIQUET APPLICATION — CAT or SOFTT-W

WHEN TO APPLY:
• Extremity hemorrhage that cannot be controlled by direct pressure alone.
• Amputation (traumatic or surgical) — apply immediately.
• High-threat environment where hands-off-wound time must be minimized.

PROCEDURE (CAT example):
1. Place tourniquet 2–3 inches proximal to wound (above wound, toward torso).
2. Pull tail through buckle, tighten strap hand-tight.
3. Twist rod until bleeding stops — typically 4–5 turns for thigh, 3–4 for arm.
4. Lock rod in clip/holder.
5. Tighten windlass strap over rod.
6. RECORD TIME on tourniquet band with permanent marker or blood.

CRITICAL NOTES:
• Pain is expected and does NOT indicate incorrect placement — do not loosen.
• A correctly applied tourniquet renders the limb pulseless distal to the TQ.
• Conversion to wound pack: only by trained provider in care under cover, never in contact.
• Two-tourniquet technique: if first TQ fails (bleeding continues), apply second TQ directly proximal to first.
• Improvised TQs: cravat + stick/pen as windlass is LAST resort — must be at least 4 inches wide, non-elastic.

DOCUMENTATION: Write time applied on forehead (T-12:45) and on TCCC card.
""",

            "Wound Packing and Pressure Dressing": """
WOUND PACKING — JUNCTIONAL AND TRUNCAL HEMORRHAGE

INDICATIONS:
• Junctional wounds (groin, axilla, neck base, perineum) not amenable to tourniquet.
• Truncal wounds where tourniquet cannot be applied.

SUPPLIES:
• Combat Gauze (kaolin-impregnated): First-line hemostatic gauze (TCCC guideline).
• Celox or ChitoGauze: Acceptable alternatives.
• Emergency Bandage (Israeli Bandage) for pressure dressing.

PROCEDURE:
1. Expose wound — cut away clothing.
2. Pack wound with hemostatic gauze: pack as deep as possible (finger-packing). Fill dead space.
3. Apply direct pressure for 3 minutes (use knuckles if necessary to concentrate force).
4. Do NOT remove packed gauze — apply additional gauze on top if needed.
5. Secure with pressure bandage. For Israeli bandage: primary pad over wound, wrap twice, lock closure bar, apply pressure.

JUNCTIONAL WOUNDS SPECIFIC:
• Groin: Pack into inguinal crease. SAM Junctional Tourniquet or Combat Ready Clamp if available.
• Axilla: Pack tightly. Position casualty arm across chest to maintain pressure.
• Neck: Apply pressure dressing. Do NOT circumferentially wrap neck — risk of airway compromise.
""",

            "Needle Decompression": """
NEEDLE DECOMPRESSION — TENSION PNEUMOTHORAX

INDICATIONS (2 or more):
• Penetrating chest trauma with respiratory distress.
• Unilateral absent or significantly decreased breath sounds.
• Increasing respiratory distress, SpO2 dropping despite O2.
• Hypotension with distended neck veins (late sign, may be absent in hypovolemia).
• Tracheal deviation away from affected side (late, unreliable).

SUPPLIES:
• 14ga, 3.25 inch (minimum) over-the-needle catheter.
• Alcohol prep pad.

PROCEDURE:
1. Identify 2nd intercostal space, midclavicular line (MCL) on affected side (absent breath sounds).
2. Clean with alcohol.
3. Insert needle perpendicular to skin, ABOVE rib (avoids neurovascular bundle which runs inferior to rib).
4. Advance until rush of air felt/heard (pleural pop). Remove needle. Leave catheter.
5. Secure catheter. Cover with one-way valve or flutter valve if available.
6. Reassess: improved respiratory status, bilateral breath sounds.
7. If no improvement in 60 seconds: repeat at 4th/5th ICS anterior axillary line (AAL).

ALTERNATE SITE: 4th/5th ICS, AAL — used when chest wall is thick or initial decompression ineffective.

CONSIDERATIONS:
• Thick chest walls (BMI >30) may require 3.25" or longer needle.
• Catheter can kink — if tension recurs, attempt second decompression at alternate site.
• Chest tube (thoracostomy) should follow at definitive care.
""",

            "CPR and Resuscitation": """
CPR — ADULT (AHA Guidelines)

RECOGNITION:
• Unresponsive, no normal breathing (absent or agonal gasping).
• No pulse palpable at carotid within 10 seconds.

SEQUENCE — CAB (Compressions-Airway-Breathing):
1. CALL FOR HELP / AED.
2. COMPRESSIONS: 100–120/min. Depth 2–2.4 inches (5–6cm). Full chest recoil between compressions. Minimize interruptions (<10 sec).
3. AIRWAY: Head-tilt chin-lift (jaw thrust if C-spine concern).
4. BREATHS: 2 rescue breaths (1 sec each) after every 30 compressions. If advanced airway (supraglottic or ETT): 1 breath every 6 seconds, asynchronous with compressions.

DEFIBRILLATION:
• AED: Power on → attach pads → analyze → shock if advised → immediately resume CPR.
• Shock after 2 minutes of CPR if no pulse. Then CPR 2 min → reassess.
• VF/pulseless VT: defibrillate. PEA/asystole: CPR + epinephrine, treat reversible causes.

FIELD CPR LIMITATIONS:
• Do NOT start CPR if: obvious signs of death (rigor mortis, dependent lividity, decapitation, evisceration of brain), or continued hostile fire prevents care.
• TCCC does NOT mandate CPR after traumatic cardiac arrest in tactical environment unless resources available.
• Survivable traumatic arrest: address tension PTX and massive hemorrhage FIRST.
""",

            "Airway Management": """
AIRWAY MANAGEMENT — FIELD PROCEDURES

NASOPHARYNGEAL AIRWAY (NPA):
• Indication: Unconscious patient with gag reflex present; semi-conscious trauma patient.
• Sizing: Diameter of nostril or small finger. Length from tip of nose to earlobe.
• Procedure: Lubricate with lidocaine jelly or water. Right nostril preferred. Insert beveled end toward septum. Rotate slightly while advancing. Stop when hub at nostril.
• Contraindication: Suspected basilar skull fracture (raccoon eyes, Battle's sign, CSF rhinorrhea).

SUPRAGLOTTIC AIRWAY (King LT-D, LMA):
• Indication: Unconscious, no gag reflex, cannot ventilate by BVM.
• King LT-D: Deflate cuffs, lubricate, size 3 (50–70kg), size 4 (70–100kg). Advance until resistance. Inflate cuff per size marking (typically 45–60mL). Ventilate. Confirm chest rise and ETCO2 if available.

SURGICAL CRICOTHYROTOMY:
• Indication: Cannot intubate, cannot ventilate (CICO scenario). Apneic with airway obstruction above cords.
• Procedure (Bougie-assisted):
  1. Palpate cricothyroid membrane (CTM) — between thyroid and cricoid cartilages, midline.
  2. Stabilize larynx with non-dominant hand.
  3. Vertical skin incision 3cm over CTM.
  4. Horizontal stab incision through CTM membrane. Hook inferior edge with finger.
  5. Insert bougie through incision, angle toward carina.
  6. Railroad 6.0 cuffed ETT over bougie. Remove bougie.
  7. Inflate cuff 10mL. Ventilate. Confirm bilateral chest rise and ETCO2.
  8. Secure tube.
• Cric Kit (Rüsch or CTOM): Follow manufacturer sequence.
""",

            "TCCC Vital Signs Assessment": """
FIELD ASSESSMENT — VITAL SIGNS AND LEVEL OF CONSCIOUSNESS

AVPU SCALE:
• A — Alert: Responds normally to verbal stimulation.
• V — Verbal: Responds only when spoken to loudly.
• P — Pain: Responds only to painful stimulus (sternal rub or supraorbital pressure).
• U — Unresponsive: No response to any stimulus.

GCS (GLASGOW COMA SCALE) — abbreviated field version:
• Eye (4): Spontaneous (4), To voice (3), To pain (2), None (1).
• Verbal (5): Oriented (5), Confused (4), Words (3), Sounds (2), None (1).
• Motor (6): Obeys commands (6), Localizes pain (5), Withdraws (4), Flexion (3), Extension (2), None (1).
• Normal = 15. Severe TBI = <8.

PULSE ASSESSMENT:
• Radial: If palpable, SBP ≥80mmHg.
• Femoral: If palpable, SBP ≥70mmHg.
• Carotid: If palpable, SBP ≥60mmHg.
• Absence of radial with carotid present = severe shock.

RESPIRATIONS:
• Normal: 12–20/min.
• Tachypnea >20: pain, shock, tension PTX, anxiety.
• Bradypnea <10: CNS depression, opioids, severe TBI.
• Count for 15 sec × 4.

SHOCK RECOGNITION:
• Class I (<15% blood loss): HR normal, BP normal.
• Class II (15–30%): HR >100, narrow pulse pressure, skin cool.
• Class III (30–40%): HR >120, BP drops, altered mental status.
• Class IV (>40%): HR >140, BP drops precipitously, unconscious.
""",

            "Hypothermia Prevention and Treatment": """
HYPOTHERMIA — PREVENTION AND FIELD TREATMENT

RECOGNITION:
• Mild (32–35°C / 90–95°F): Shivering, impaired coordination, slurred speech, pale skin.
• Moderate (28–32°C / 82–90°F): Shivering stops, confusion, muscle rigidity, bradycardia.
• Severe (<28°C / <82°F): Unconscious, no palpable pulse, appears dead — do NOT assume dead.

FIELD TREATMENT:
1. Remove wet clothing. Avoid rough handling (risk of VF in moderate/severe).
2. Insulate from ground (ground conducts heat 25× faster than air).
3. Apply Hypothermia Prevention Kit (HPK): vapor barrier bag or casualty blanket, reflective side in.
4. Cover head — 40–50% of heat loss through head.
5. Chemical heat packs: armpits, groin, neck — NOT directly on skin.
6. Warm fluids if conscious and able to swallow (warm water, warm sweet drinks).
7. Active core rewarming: only at medical facility. Field: prevent further cooling, evacuate.

PREVENT HYPOTHERMIA IN CASUALTIES:
• Remove wet gear immediately.
• "Pack, heat, wrap" — HPK standard.
• Every trauma casualty: assume hypothermia risk.

REWARMING RATE: 0.5–1°C per hour is acceptable. Do NOT attempt rapid active rewarming in field (afterdrop risk).

NOTE: A severely hypothermic patient is NOT dead until warm and dead. Begin CPR and evacuate.
""",

            "Improvised Litter and Casualty Movement": """
CASUALTY MOVEMENT — TACTICAL FIELD CARRY AND EXTRACTION

ONE-PERSON DRAGS:
• Clothes drag: Grab collar at shoulders, drag backward. Head protected.
• Arm drag: Under armpits, hands across chest, drag backward.
• Blanket drag: Roll onto blanket, grab corner near head, drag.

TWO-PERSON CARRIES:
• Two-hand seat: Interlace hands under thighs, arm around back.
• Four-hand seat: Both rescuers grip wrists forming platform. Patient wraps arms around shoulders.
• Pack strap: Rescuer carries on back. Casualty's arms over rescuer's shoulders, hands interlocked in front.

LITTERS:
• Improved litter from poles + clothing: Thread poles through sleeves of 2 jackets, button closed.
• Pole and blanket: Two poles with blanket wrapped around them (test weight before committing).
• Rigid board: Door, plywood, vehicle hood.

MOVEMENT CONSIDERATIONS:
• C-spine precaution: Unnecessary delay in penetrating trauma (no benefit demonstrated in TCCC). Use for blunt mechanism.
• Drag first, package later: Get to cover, then assess.
• TCCC mandate: Get to cover within 10 seconds if under fire.
• Femur fracture: Traction splint (Kendrick) or improvised traction before moving if possible.
""",
        ]
    }

    // MARK: - Survival (FM 3-05.70)

    private func loadSurvival() {
        survivalKnowledge = [

            "SURVIVAL Acronym": """
FM 3-05.70 — SURVIVAL ACRONYM

S — SIZE UP THE SITUATION: Surroundings (hostility, terrain, weather). Physical condition. Equipment available.
U — USE ALL YOUR SENSES: Stop → Observe → Listen → Smell. Avoid hasty decisions.
R — REMEMBER WHERE YOU ARE: Map position. Nearest friendly forces. Nearest water. Nearest concealment route.
V — VANQUISH FEAR AND PANIC: Fear is normal. Control it. One problem at a time.
I — IMPROVISE: No tool? Make one. Adapt available materials.
V — VALUE LIVING: The will to survive is the critical factor. Stay motivated.
A — ACT LIKE THE NATIVES: Observe local patterns — animals, plants, weather.
L — LIVE BY YOUR WITS: Use knowledge and training. Remember SERE principles.

USE IN A SURVIVAL SITUATION:
1. Apply STOP: Stop → Think → Observe → Plan.
2. Address immediate threats: weather, injury, water, fire, signaling.
3. Prioritize: Protection first, then water, then fire, then food (food is last).
""",

            "Water Procurement and Purification": """
WATER — PROCUREMENT AND PURIFICATION (FM 3-05.70 Chapter 6)

DAILY REQUIREMENTS:
• Minimum: 2 liters/day (sedentary, moderate climate).
• Operations: 4–8 liters/day (activity, heat).
• Urine color guide: Clear/pale = hydrated. Yellow/dark = dehydrated. No urine = critical.

FINDING WATER:
• Valleys and low ground: follow terrain downhill.
• Green vegetation: willows, cottonwood, cattails indicate water within 1 meter of surface.
• Animal trails: usually lead to water, especially at dawn and dusk.
• Birds: circle or converge toward water.
• Insects: bees — within 6km of water. Mosquitoes — within 100m.
• Rock outcroppings: may have natural cisterns after rain.
• Dew collection: wipe grass with absorbent cloth at dawn, wring into container.
• Solar still: 24-hour output 0.5–1L. Dig 90cm deep × 90cm wide hole, place green vegetation in, cover with clear plastic, small stone in center over collection container.
• Transpiration bag: seal green leafy branch in clear plastic bag. Sun-facing. 0.5–1L/day.
• Seawater: NEVER drink untreated. Distill only.

PURIFICATION METHODS:
1. BOILING: Most reliable. Rolling boil 1 minute (3 min above 6,500ft elevation). Kills pathogens, does not remove chemicals.
2. CHEMICAL: Iodine tablets (2 tabs/L, 30 min, 60 min cold water). Chlorine tabs similar. Does NOT kill Cryptosporidium.
3. FILTER: MSR Sweetwater, Sawyer Squeeze — removes bacteria and protozoa. Add iodine for viruses.
4. UV STERIPEN: 60 seconds for 1L — kills bacteria, protozoa, viruses. Requires clear water.

WATER SOURCES TO AVOID:
• Stagnant water with algae blooms (cyanobacteria).
• Water near industrial sites, mines (heavy metals).
• Murky, discolored water — pre-filter through cloth before treatment.
""",

            "Fire Building and Maintenance": """
FIRE — CONSTRUCTION AND MAINTENANCE (FM 3-05.70 Chapter 7)

FIRE TRIANGLE: Fuel + Air + Heat = Fire.

SELECTING SITE:
• Concealment: reflector walls hide light. Dig fire pit if possible (reduces signature).
• Wind protection: natural windbreaks. Overhang protection from rain.
• Safety: clear 3-foot circle of debris. Never build under overhanging branches.

TINDER COLLECTION:
• Dry materials that catch spark easily: dry grass, bark shreddings, cattail fluff, birch bark, dry leaves.
• Collect more than you think you need (3–4 handfuls).

KINDLING:
• Small dry sticks, ≈finger-diameter. Dry needles, pine cones.
• Split wood has more exposed surface = catches faster.

FUEL:
• Thumb-diameter up to wrist-diameter. Hardwoods (oak, hickory) burn hotter and longer.
• Green wood for smoke signals (daytime — white smoke visible).
• Deadwood on the ground dries faster than standing dead.

FIRE LAYS:
• Teepee: Tinder in center, kindling in cone around it, fuel leaned in teepee. Good for cooking and signaling.
• Log cabin: Platform of parallel sticks, alternating layers at 90°, tinder in center. Burns steady.
• Star fire: Large logs pushed in from 5 points. Feed as outer ends burn. Good for overnight.
• Trench fire: Dig 30cm trench aligned with wind. Poles across trench support cooking vessel.

FIRE STARTING:
• Lighter/matches: Primary. Protect from moisture.
• Ferrocerium rod: Works wet. Strike at 45° with knife spine. Direct sparks to tinder bundle.
• Battery + steel wool: Touch wire from battery poles to fine steel wool. Catches immediately.
• Friction fire (bow drill): Only when other methods unavailable. Takes 10–30 min for untrained.
""",

            "Shelter Construction": """
SHELTER — FIELD CONSTRUCTION (FM 3-05.70 Chapter 5)

PRIORITIES IN ORDER:
1. Protection from elements (wind, rain, ground cold) more important than warmth.
2. Ground insulation: 15cm of dry material between body and ground prevents heat loss to ground.
3. Size: Smaller is warmer. Body heat fills small space faster.
4. Camouflage: blend with environment. Avoid military green on natural background.

LEAN-TO:
• Fastest construction. String ridgeline between two trees at shoulder height.
• Lay poles at 45° angle from ridgeline to ground.
• Layer bark, leaves, boughs shingle-style from bottom up. 4–6 inches thick.
• Add windbreak walls if needed. Add reflector fire in front.
• Time: 1–2 hours. Not waterproof without good layering.

DEBRIS HUT:
• Best single-person cold-weather shelter with no gear.
• Drive ridgepole into ground crotch or between trees at 45° angle (length = arm + leg span).
• Lean ribs along both sides. Cover with debris 1 meter deep (must resist arm-push).
• Stuff inside with dry leaves. Plug entrance with debris bundle.
• Time: 2–3 hours. 90°F interior possible in sub-freezing with body heat.

SNOW SHELTERS:
• Quinzhee: Pile snow 2m high, let sinter 2 hours. Hollow out, leave 15cm wall. Sleeping temp: just below freezing.
• Tree pit: Natural cavity under conifer. Quickest cold-weather shelter.
• Snow trench: Dig trench, cover with skis/poles/boughs, add snow on top. 30-min construction.

CRITICAL: Block entrance with pack/debris bundle — prevents wind chill and heat loss.
""",

            "Food Procurement": """
FOOD — FIELD PROCUREMENT (FM 3-05.70)

SURVIVAL TIMELINE: Humans can survive 3 weeks without food. Water and shelter take priority.

EDIBLE PLANTS (Universal Edibility Test):
1. Smell separated plant part — avoid if smells of almonds/peach pits (cyanide).
2. Skin contact: rub on wrist, wait 15 min for irritation.
3. Lip test: touch to lip, wait 3 min.
4. Tongue test: hold on tongue 15 min.
5. Chew small amount, wait 8 hours. If no reaction, consume small quantity, wait 8 more hours.
• Test ONE part (root, leaf, berry) at a time.
• Never test mushrooms — universal edibility test does not apply.

SAFE PLANTS (CONUS):
• Cattail: Pollen and roots edible. Pollen as flour. Roots ground into starch.
• Clover: Entire plant edible raw or cooked. High protein.
• Pine needles: Brew as tea (vitamin C). Inner bark edible (emergency).
• Dandelion: Entire plant edible. Roots roasted = coffee substitute.
• Acorns: Leach tannins in running water or 3 changes of boiling water. Grind into flour.

ANIMAL PROTEIN:
• Insects: Highest calorie-to-effort ratio. Avoid brightly colored, stinging, hairy. Boil or roast all.
• Earthworms: Purge in water 2 hours. High protein. Cook.
• Freshwater fish: Gill net from paracord + wood frame. Figure-4 deadfall with fish offal as bait.
• Snares: Simple loop snare from paracord at small animal trail. Set near water. Check every 4–6 hours.

AVOID: Mushrooms (identification requires expert knowledge). Berries you cannot identify. Marine animals without cooking.
""",

            "Navigation Without GPS": """
NAVIGATION — GPS-DENIED METHODS (FM 3-21.18 / FM 3-05.70)

MAP AND COMPASS — BASIC PROCEDURE:
1. Orient map: align compass with North line on map. Rotate map until compass needle aligns with magnetic north arrow on map.
2. Determine position: identify 2–3 terrain features visible around you. Find those features on map. Draw azimuth lines from each. Where they cross = your position (resection).
3. Plot route: draw line from current position to destination. Read azimuth (bearing in degrees from north).
4. March on azimuth: compass set to desired bearing. Pick intermediate landmark on that bearing. Walk to it. Re-shoot bearing. Repeat.
5. Account for declination: add East declination, subtract West declination from true azimuth to get magnetic azimuth.

PACE COUNT:
• Know your 100-meter pace count on flat, uphill, downhill terrain.
• Average adult: 60–68 double paces per 100m.
• Use pace beads or tally marks.

CELESTIAL NAVIGATION:
• North Star (Polaris): Find Big Dipper, extend outer edge of cup 5× cup height = Polaris. Directly north.
• Moon: If moon rises before midnight, illuminated side faces west. After midnight, faces east.
• Shadow tip method: Place stick, mark shadow tip at 15-min intervals. First mark = west, second = east.
• Southern Cross (CONUS south): longest axis of cross points toward south celestial pole.

TERRAIN ASSOCIATION:
• Use terrain features to confirm position: ridgelines, creek bends, road junctions.
• Handrails: linear feature (road, river, power line) parallel to your route to guide travel.
• Catching features: linear feature that intercepts your route and tells you you've gone far enough.
• Attack point: close-in feature to aim for before final navigation to objective.
""",
        ]
    }

    // MARK: - Navigation

    private func loadNavigation() {
        navigationKnowledge = [

            "MGRS Grid System": """
MGRS — MILITARY GRID REFERENCE SYSTEM

STRUCTURE: Grid Zone Designator + 100km Square ID + Easting + Northing
Example: 14RPU1234567890
• 14R = Grid Zone (6° wide latitude band)
• PU = 100km square identifier
• 12345 = Easting (5 digits = 1m precision)
• 67890 = Northing (5 digits = 1m precision)

READING A GRID:
• Always read RIGHT then UP (Easting then Northing).
• "Read right, read up" — like X-Y coordinates.
• 4-digit grid: 1km × 1km (operational planning).
• 6-digit grid: 100m × 100m (patrol planning).
• 8-digit grid: 10m × 10m (precision targeting/casualty pickup).
• 10-digit grid: 1m × 1m (survey quality, seldom used in field).

BREVITY CODES:
• "Grid follows": precedes MGRS coordinate in radio traffic.
• "Break": pause in long MGRS string for clarity.

CONVERTING FROM DECIMAL DEGREES (DD) TO MGRS:
• Use phone (offline MGRS app), GPS, or 1:50,000 topo map.
• Western hemisphere longitudes are Easting, Northern hemisphere latitudes are Northing.
""",

            "Compass Use and Azimuths": """
COMPASS — OPERATION AND AZIMUTHS

TYPES:
• Lensatic compass (military standard): liquid-filled, tritium bezel.
• Baseplate compass (civilian): ruler, rotating bezel, good for map work.

MAGNETIC DECLINATION:
• The angle between magnetic north (compass) and true north (map).
• CONUS varies from +20° (Pacific NW) to -20° (New England).
• Grid declination: angle between grid north and magnetic north.
• Diagram in map margin gives current values.
• Mnemonic: "Grid to Mag, ADD. Mag to Grid, GET RID." (for East declination).

SHOOTING A BEARING:
1. Hold compass level, thumb through loop if lensatic.
2. Point at target through sighting notch and wire.
3. Keep bezel horizontal, read azimuth under index line.
4. Add/subtract declination as needed.

BACK AZIMUTH: Add 180° if azimuth <180°. Subtract 180° if >180°.
• Example: Azimuth 060° → Back azimuth 240°.

RESECTION (FINDING YOUR POSITION):
1. Identify 2–3 terrain features on both ground and map.
2. Shoot azimuth to each feature with compass.
3. Convert to back azimuths.
4. Draw back azimuth lines from each feature on map.
5. Intersection = your position.

INTERSECTION (FINDING UNKNOWN POSITION):
• You know your position. Shoot azimuth to unknown point.
• Move to second known position. Shoot azimuth to same point.
• Convert to back azimuths. Lines cross at unknown point location.
""",

            "Land Navigation at Night": """
NIGHT NAVIGATION

CHALLENGES: Reduced depth perception, compressed distances, landmark obscurement.

PREPARATION:
• Plan route before dark. Identify night-visible landmarks (terrain silhouettes, water reflection, lights).
• Pace count more critical — cannot confirm position visually.
• Brief all team members on route before dark.
• Reduce rucksack noise: secure loose items.

TECHNIQUES:
• Hand on compass: maintain constant bearing with short legs between terrain checks.
• Terrain following: use ground slope and drainage as handrails.
• Star navigation: use Polaris or Southern Cross as constant reference.
• Bounding: designate point man at night observation limit (30–50m). Others follow.

NIGHT VISION:
• Red-light adaptation: red light preserves 80% of night vision adjustment.
• Full dark adaptation: 30 minutes minimum.
• Rods (night-sensitive) most dense around fovea periphery — look slightly to side of target.
• Scanning pattern: slow, irregular figure-8 movement of eyes, not staring at one point.

LIGHT DISCIPLINE:
• No white light without necessity.
• Shield red light below waist height.
• Infrared light (IR) visible only with NODs — maintain IR discipline if enemy has NVG capability.
""",
        ]
    }

    // MARK: - Radio Procedures (ARRL ARES + Military)

    private func loadRadio() {
        radioProcedures = [

            "Radio Communication Procedures": """
RADIO PROCEDURES — TACTICAL AND EMERGENCY COMMUNICATIONS

NATO PROWORDS (PROCEDURE WORDS):
• ACTUAL: Identifies the commander/unit itself (not the radio operator). "Bravo 6 actual."
• BREAK: Pause in transmission — more to follow.
• BREAK BREAK: Urgent interruption of ongoing traffic. Priority message follows.
• SEND IT: Acknowledge, transmit your message.
• SAY AGAIN: Repeat last transmission (NOT "repeat" — repeat has artillery connotations).
• ROGER: Message received and understood.
• WILCO: Will comply. (Never "Roger Wilco" — redundant.)
• OVER: End of transmission, reply expected.
• OUT: End of communication, no reply expected. Never "Over and Out."
• STANDBY: Wait briefly.
• FIGURES: Precedes numbers (to distinguish from phonetic letters).
• GRID FOLLOWS: Precedes MGRS coordinate.
• ACTUAL: Commander speaking (not RTO).

PHONETIC ALPHABET:
Alpha, Bravo, Charlie, Delta, Echo, Foxtrot, Golf, Hotel, India, Juliet, Kilo, Lima, Mike, November, Oscar, Papa, Quebec, Romeo, Sierra, Tango, Uniform, Victor, Whiskey, X-ray, Yankee, Zulu.

NUMBERS: Niner (not "nine"), to avoid confusion with German "Nein."

RADIO CHECK:
CALLER: "[Station X], this is [Station Y], radio check, over."
REPLY: "[Station Y], this is [Station X], roger, out." OR strength report: "Lima Charlie" (loud and clear).

SIGNAL STRENGTH REPORT:
1 — Barely perceptible. 2 — Weak. 3 — Readable. 4 — Readable, slight interference. 5 — Perfectly readable.
Lima Charlie = Loud and Clear. Romeo Kilo = Readable but Weak.
""",

            "MEDEVAC 9-Line Request": """
9-LINE MEDEVAC REQUEST (NATO Standard)

LINE 1 — Location of pickup site (MGRS 8-digit grid).
LINE 2 — Radio frequency and call sign at pickup site.
LINE 3 — Number of casualties by precedence:
    A — Urgent (1 hour): life, limb, eyesight at risk.
    B — Urgent Surgical (<2 hr): requires surgery to survive.
    C — Priority (4 hour): deterioration probable.
    D — Routine (24 hour): evacuation required but stable.
    E — Convenience: no significant impact if delayed.
LINE 4 — Special equipment required: N (none), A (hoist), B (extraction equipment), C (ventilator).
LINE 5 — Number of casualties by type: L (litter), A (ambulatory).
LINE 6 — Security at pickup site: N (no enemy), P (possible enemy), E (enemy in area — expect armed escort), X (enemy in area — armed escort required).
LINE 7 — Method of marking pickup site: A (panels), B (pyrotechnics), C (smoke), D (none), E (other).
LINE 8 — Casualty nationality and status: A (military US), B (military allied), C (civilian), D (EPW).
LINE 9 — NBC contamination: N (nuclear), B (biological), C (chemical).

TRANSMISSION FORMAT: Send lines 1–5 first. Authenticate if required. Send 6–9 after acknowledgment.
Speak clearly. Avoid rushing. Critical information first.
""",

            "Meshtastic Mesh Network Operations": """
MESHTASTIC — TACTICAL MESH NETWORK OPERATIONS

FREQUENCY BANDS:
• 915 MHz (US): Primary. Good penetration, 1–5 km direct, 10+ km relay.
• 433 MHz: Europe/Canada. Longer range, slower data rate.
• 2.4 GHz (WiFi): Rarely used for mesh.

NODE PLACEMENT FOR COVERAGE:
• Line-of-sight preferred. Elevation significantly extends range.
• High-point relay nodes: mountain tops, buildings, vehicles — multiply network range.
• Repeater nodes: devices in relay-only mode forwarding all packets.

CHANNEL CONFIGURATION:
• Same channel name + PSK = same network. Mismatched = no communication.
• AES-256 encryption. Pre-shared key must be distributed OOB (verbally or physical media).
• Default channel "LongFast" — unencrypted, public. NEVER use for sensitive traffic.
• Tactical channels: custom name + unique key generated per operation.

MESSAGE TYPES:
• Text message: up to 237 bytes per packet. Auto-fragments longer messages.
• Position: GPS lat/lon/alt/speed/heading. Configurable broadcast interval.
• Telemetry: battery, temperature, barometric pressure.

LIMITATIONS:
• Low bandwidth (~300–1200 bps effective). Not suitable for voice or images.
• Duty cycle restrictions (FCC): 10% duty cycle on ISM bands.
• Latency: 1–10 seconds per hop depending on network congestion.
• Max hops: 3 by default (configurable). Each hop adds latency and packet loss risk.

INTEROPERABILITY WITH TAK:
• Meshtastic → TAK gateway: sends CoT (Cursor on Target) XML positions to TAK server.
• TAK → Meshtastic: position data from TAK can be sent as mesh text messages.
""",

            "Emergency Frequencies": """
EMERGENCY COMMUNICATION FREQUENCIES

CIVILIAN EMERGENCY:
• 156.800 MHz (Marine VHF CH 16): International distress, safety, calling.
• 121.500 MHz (Aviation guard): International aeronautical emergency. Monitored by military/civil aviation.
• 243.000 MHz (Military aviation guard): Identical to 121.5 MHz function, military band.
• 406 MHz: PLB (Personal Locator Beacon) — satellite uplink to COSPAS-SARSAT. No voice.

AMATEUR RADIO EMERGENCY:
• 146.520 MHz (2m simplex calling): Primary 2m calling frequency. Local coordination.
• 446.000 MHz (UHF simplex): National UHF simplex calling.
• 7.285 MHz / 3.985 MHz (HF USB): ARRL nets. Long-range during power outages.
• ARES/RACES: State-specific frequencies. Coordinate with local ARRL emergency coordinator.

FEDERAL / INTEROP CHANNELS:
• VCALL10 (155.340 MHz): Incident Command calling channel (NIMS/NPSPAC).
• VTAC11–14 (151.1375–158.7375 MHz): Interoperability tactical channels.
• 155.475 MHz: FEMA National Simplex.
• National Interoperability Channels: Designated by FCC for mutual aid — obtain from local emergency management.

FRS/GMRS (No License Required for FRS):
• CH 1–7: FRS/GMRS shared.
• CH 8–14: FRS only (lower power).
• CH 15–22: GMRS only (requires license).
• Emergency: FRS CH 1 (462.5625 MHz) — commonly monitored.
• Output: 2W FRS, 50W GMRS.
""",
        ]
    }

    // MARK: - SAR Protocols

    private func loadSAR() {
        sarProtocols = [

            "LAST Known Point and Initial Search": """
SEARCH AND RESCUE — INITIAL PROCEDURES

IMMEDIATE ACTIONS WHEN PERSON REPORTED MISSING:
1. GET LKP (Last Known Point): Last confirmed sighting with time, location, direction of travel.
2. GET PLS (Point Last Seen): Where subject was actually seen vs. where known to have been.
3. Interview witnesses: What was subject wearing? Health status? Experience level? Mood? Equipment? Planned route?
4. Confine the search area: Set containment using roads, rivers, ridgelines — subject unlikely to cross.
5. Establish command post: Communications, staging, accountability.
6. Begin hasty search: Fast teams on trails and roads in likely areas before committing systematic resources.

SEARCH THEORY:
• Probability of Area (POA): likelihood subject is in a particular area.
• Probability of Detection (POD): % chance search team will find subject if present.
• Probability of Success (POS): POA × POD.
• Debrief teams after each sweep — update POA based on findings.

SUBJECT BEHAVIOR PATTERNS:
• Children <6: Stay near last point, hide in enclosed spaces (closets, culverts), do not respond to calls.
• Alzheimer's/dementia: Travel in straight lines, do not respond to name, avoid people.
• Despondent: Actively avoid searchers, may be in concealed location.
• Hikers/campers: Follow trails, camp near water.
• Hunters: Know terrain, may be injured in rugged areas.
""",

            "Search Pattern Methods": """
SEARCH PATTERNS (ICS FIELD GUIDE)

HASTY SEARCH:
• Purpose: Quick sweep of high-probability areas before committing teams.
• Technique: Teams move quickly on trails, roads, drainages.
• Coverage: Low but fast. Used to find easy finds and gather intelligence.
• Best for: Early stages, good trail networks.

GRID SEARCH (SYSTEMATIC):
• Divide search area into grid squares.
• Teams sweep each grid in parallel with spacing = detection width (varies by terrain and visibility).
• Efficient but slow. High POD when properly spaced.
• Track POD on map as each grid cleared.

EXPANDING SQUARE:
• Start at LKP, expand outward in squares.
• Spacing = 2 × detection width.
• Best for known LKP with subject mobility limited.
• Can miss subject in blind spots between spiral arms.

PARALLEL TRACKS (SHORELINE/OPEN TERRAIN):
• Multiple searchers in line, equal spacing.
• Move parallel to each other.
• Track spacing based on visibility.
• Best for open terrain, water edges.

CONTOUR SEARCH:
• Follow contour lines across slope.
• Good for steep terrain, avalanche debris.

ATTRACTION TECHNIQUES:
• Sound: Whistles, air horns, call out at intervals, listen for 30 seconds.
• Light: Lights at night, reflective signals.
• Scent: Dogs most effective for tracking and area search.
""",

            "METHANE Incident Report": """
METHANE — MASS CASUALTY INCIDENT REPORT FORMAT

M — MAJOR INCIDENT: Declare major incident. Request resources.
E — EXACT LOCATION: Grid reference or address. Access routes.
T — TYPE OF INCIDENT: Explosion, vehicle, structural collapse, CBRN, etc.
H — HAZARDS: Present, potential (fire, gas, structural instability, secondary device risk).
A — ACCESS AND EGRESS: Best route in and out. Staging area location.
N — NUMBER OF CASUALTIES: Approximate counts by TRIAGE category.
    P1 — Immediate (red): life-threatening, survivable.
    P2 — Delayed (yellow): serious but can wait.
    P3 — Minor (green): walking wounded.
    P4 — Expectant (black): unsurvivable or deceased.
E — EMERGENCY SERVICES: On scene and required.

TRIAGE START METHOD (FIELD):
1. Walk → all walking = P3 (minor). Move to casualty collection point.
2. BREATHING? → No: Reposition airway → still not breathing → P4 (expectant).
3. BREATHING RATE: >30/min = P1. <30/min = continue.
4. PERFUSION: Radial pulse absent OR capillary refill >2 sec = P1.
5. MENTAL STATUS: Cannot follow simple commands = P1.
6. All others = P2 (delayed).

JumpSTART (PEDIATRIC TRIAGE): Same as START but: if apneic after positioning airway, give 5 rescue breaths — if breathing begins = P1. If not = P4.
""",
        ]
    }

    // MARK: - Weather

    private func loadWeather() {
        weatherPatterns = [

            "Weather Indicators and Forecasting": """
FIELD WEATHER FORECASTING (FM 3-05.70 Chapter 15)

PRESSURE TRENDS (barometric):
• Rapidly falling (>4 mbar/3hr): Severe storm approaching within 12–24 hours.
• Slowly falling: Rain or snow within 24–48 hours.
• Steady/rising: Fair weather likely.
• Rapidly rising after low: Temperature drop, gusty winds.

CLOUD TYPES AND FORECASTING:
• Cirrus (high, wispy): Fair weather now, but frontal system possible in 24–48 hours.
• Cirrostratus: Halo around sun/moon = rain within 24 hours.
• Altocumulus (mid-level, gray rippled): "Mackerel sky" — change within 24 hours.
• Cumulonimbus (anvil-shaped, dark): Thunderstorm imminent. Seek shelter. Avoid high ground, lone trees, metal.
• Stratus (low gray sheet): Drizzle, reduced visibility.
• Fog: Dense fog usually clears by 0900 local time in fair weather.

WIND INDICATORS:
• Veering winds (clockwise shift, e.g., S→SW→W): improving weather in Northern Hemisphere.
• Backing winds (counter-clockwise shift): deteriorating weather.
• Red sky at night: Sailors delight (fair weather westerly).
• Red sky at morning: Storm warning (moisture moving in from east).

LIGHTNING SAFETY:
• If thunder heard, lightning is possible — seek shelter.
• Lightning position: Feet together, crouch low, cover ears, no metal contact.
• Avoid: ridgelines, lone trees, water, metal fences.
• Count seconds between flash and thunder ÷ 5 = miles away.
• Wait 30 minutes after last thunder before leaving shelter.

HEAT CASUALTIES:
• Heat cramps: Electrolyte imbalance. Rest + fluids + electrolytes.
• Heat exhaustion: Heavy sweating, weakness, cold/clammy skin. Remove from heat, supine, cool, oral fluids if conscious.
• Heat stroke: Confusion, hot/dry OR wet skin, altered LOC. Medical emergency. Ice water immersion if available. Evaporative cooling otherwise.
""",
        ]
    }

    // MARK: - Tactical Procedures

    private func loadTactical() {
        tacticalProcedures = [

            "Immediate Action Drills": """
IMMEDIATE ACTION DRILLS — SMALL UNIT TACTICS

REACT TO CONTACT (enemy fire received):
1. RETURN FIRE immediately from current position.
2. TAKE COVER: move from exposed position.
3. SUPPRESS: maintain fire superiority.
4. REPORT: alert team/higher to contact.
5. BOUND: use fire and movement to break contact or assault.

BUDDY TEAM BOUNDS:
• "I'm up, they see me, I'm down" = 3–5 seconds maximum exposed time.
• One element fires while other moves. Alternate.
• Move to next covered position, signal "set," then cover partner.

BREAK CONTACT (withdrawal):
1. Identify covered withdrawal route.
2. Alternate bounds toward cover/egress.
3. Smoke concealment if available.
4. Peeling: last person in column fires and peels around to front. Repeat.
5. Rally point: pre-briefed secondary rally point outside contact area.

NEAR AMBUSH (within 35 meters):
• ASSAULT THROUGH: return fire immediately, charge through ambush.
• Surprise, violence of action negates ambush advantage.

FAR AMBUSH (beyond 35 meters):
• BREAK CONTACT: bound to cover, suppress, withdraw.
• Do NOT charge through long-range ambush.

RALLY POINTS:
• Initial Rally Point: last terrain feature before objective. Consolidate if separated.
• En Route Rally Point: designated point to reassemble if contact during movement.
• Objective Rally Point (ORP): assembly point before assault.
""",

            "OPSEC — Operational Security": """
OPSEC — OPERATIONAL SECURITY PRINCIPLES

OPSEC PROCESS (FM 3-13.3):
1. IDENTIFY CRITICAL INFORMATION: What does enemy need to know to harm your mission?
2. ANALYZE THREATS: Who is threat? What are their collection capabilities?
3. ANALYZE VULNERABILITIES: Where can enemy intercept your critical information?
4. ASSESS RISK: Probability × impact.
5. APPLY COUNTERMEASURES: Change patterns, encrypt, limit information sharing.

COMMUNICATIONS SECURITY:
• Assume all unencrypted communications are intercepted.
• Encrypt at rest: files, messages, voice.
• Never discuss locations, personnel, timelines on open channels.
• Radio silence during movement phases if possible.
• Use callsigns, not personal names or unit designations.
• Change encryption keys per COMSEC plan.

PHYSICAL SECURITY:
• No photos of equipment, positions, or team members.
• Social media blackout during operations.
• Cover trail: no discernible pattern in routes, schedules, or contacts.
• Debrief team: what CAN and CANNOT be discussed, where, and with whom.

COUNTER-SURVEILLANCE:
• SDR (Surveillance Detection Route): deliberate route taken to identify surveillance.
• Vary routes, timing, vehicles.
• Three-person tail: follows in shifts. Identify by repetition at different locations.
• If surveillance suspected: do NOT react. Continue to safe house. Brief and report.

INFORMATION CLASSIFICATION:
• Do not discuss details of capabilities, vulnerabilities, or future plans with non-essential personnel.
• Need-to-know: provide only the minimum information required for the task.
""",

            "Checkpoint and Rally Point Planning": """
PLANNING — CHECKPOINTS, RALLY POINTS, OBJECTIVES

MARCH ORDER PLANNING:
• Order of march: Point, main body, rear guard.
• Movement formation: file (narrow terrain), wedge (open terrain with threat), echelon.
• Movement techniques: traveling (speed), traveling overwatch (speed + security), bounding overwatch (highest threat).
• Rate of movement: assume 2–3 km/hr cross-country, 4–5 km/hr road, adjust for terrain/load/visibility.

PATROL BASE:
• No regular geometric shape — varies with terrain.
• 360° security: sectors assigned.
• ORP 200–300m before patrol base.
• Stand-to: 30 min before dawn and dusk.
• No fires, cooking smells, noise, lights.
• Two-person exit only (no individual movement).

OBJECTIVE RALLY POINT (ORP):
• Last covered position before objective, within 200m.
• Full 360° security established.
• Final brief.
• Cache rucks, leave one team to secure.
• Report from ORP to higher before assault.

PRIORITIES OF WORK AT NEW POSITION:
1. Security (assign sectors, post guard).
2. Wire communications (land line if available).
3. Mutual support fighting positions.
4. Overhead cover.
5. Camouflage.
6. Sustainment (water, food, medical).
7. Sleep plan (50% security minimum in threat).
""",
        ]
    }

    // MARK: - ICS (NIMS / FEMA ICS 100/200)

    private func loadICS() {
        incidentCommand = [

            "ICS Structure and Roles": """
INCIDENT COMMAND SYSTEM (ICS) — NIMS STANDARD

ICS COMMAND STAFF:
• Incident Commander (IC): Overall responsibility for incident management.
• Public Information Officer (PIO): Media and public information.
• Safety Officer (SO): Monitors safety conditions, authority to halt unsafe operations.
• Liaison Officer (LNO): Coordinates with outside agencies.

ICS GENERAL STAFF (SECTION CHIEFS):
• Operations Section: Tactical operations to achieve incident objectives.
• Planning Section: Situation status, resources, documentation, demobilization.
• Logistics Section: Support needs — facilities, transportation, supplies, communications.
• Finance/Admin Section: Cost tracking, procurement, time recording.

COMMAND PRINCIPLES:
• Unity of command: Each person reports to ONE supervisor.
• Span of control: 1 supervisor to 3–7 subordinates (optimal 5).
• Common terminology: Standard language, no agency-specific jargon.
• Modular organization: Expand/contract as incident demands.
• Management by objectives: Objectives → Strategies → Tactics → Tasks.
• Incident Action Plan (IAP): Written objectives and tactics for each operational period.

OPERATIONAL PERIOD:
• Typically 12–24 hours.
• Planning cycle: IC sets objectives → Planning develops IAP → Operations implements → repeat.
• Briefing at start of each operational period.

RESOURCE STATUS:
• Available: Ready for assignment.
• Assigned: Working on task.
• Out of service: Unavailable (maintenance, rest, rehab).
""",

            "ICS Common Terminology and Forms": """
ICS FORMS AND DOCUMENTATION

ICS 201 — Incident Briefing:
• Used first hour of incident. Records initial situation, resources committed, sketch map, current actions, initial priorities.

ICS 202 — Incident Objectives:
• Operational period objectives. Weather/safety considerations. General guidance.

ICS 204 — Assignment List:
• Operations Section. Assigns resources to specific tasks with supervisor.

ICS 205 — Communications Plan:
• Radio frequencies by function. Mutual aid frequencies. Phone numbers.

ICS 206 — Medical Plan:
• Incident medical resources. Hospital locations. Evacuation routes.

ICS 214 — Activity Log:
• Individual/unit activity documentation. Date/time of actions. Key decisions.

STAGING AREAS:
• Base: Primary logistics/admin location. Resources that have been assigned and are available.
• Camp: Smaller than Base. Sustains resources remote from Base.
• Staging Area: Temporary location for resources awaiting assignment. NOT same as Base.
• Helibase / Helispot: Helicopter operations.

INCIDENT TYPES:
• Type 5: Small, local incident. 1 agency, 1 operational period.
• Type 4: Multiple resources, limited agencies.
• Type 3: Multi-agency, extended. Regional response.
• Type 2: Nationwide resources. Deployed ICS team.
• Type 1: Most complex. National deployment.
""",
        ]
    }

    // MARK: - Signaling

    private func loadSignaling() {
        signaling = [

            "Ground-to-Air Signals": """
GROUND-TO-AIR SIGNALS (SERE / FM 3-05.70)

STANDARD GROUND-TO-AIR SIGNALS:
• V: Require assistance.
• X: Require medical assistance.
• → (Arrow): Traveling in this direction.
• LL: All is well (parallel lines).
• N: No (negative).
• Y: Yes (affirmative).

CONSTRUCTION:
• Minimum size: 10 feet (3m) long, 3 feet (1m) wide, contrasting color.
• Best materials: rocks, logs, branches, fabric panels, trampled vegetation.
• Best locations: open clearings, hilltops, beach, snow field.
• Contrast: dark material on light background or vice versa.

PYROTECHNIC SIGNALS:
• Red smoke: Distress signal. Always use code first.
• Orange smoke: Daytime primary marker — highly visible.
• White smoke: Marking for aircraft approach.
• SOLAS flares: Red parachute flare — distress. Handheld red — close-range distress.
• Signal mirror: Visible up to 100 miles in clear conditions. Flash toward aircraft.

SIGNAL MIRROR TECHNIQUE:
1. Hold mirror between thumb and forefinger.
2. Reflect sunlight onto ground or hand.
3. Raise mirror until reflection is directed toward aircraft.
4. Flash repeatedly with deliberate signals.

AT NIGHT:
• Strobe light: Most effective. Alternating strobe is internationally recognized distress.
• Fire: Three fires in a triangle (50m apart) = distress signal.
• Flashlight: SOS in Morse (... --- ...) directed at aircraft or horizon.

SOS MORSE:
• Dot = short flash/sound (1 unit). Dash = long (3 units). Between letters: pause 3 units. Between words: pause 7 units.
• S = ... O = --- S = ...
""",
        ]
    }
}

// MARK: - TacticalCorpusView

struct TacticalCorpusView: View {
    @ObservedObject private var viewModel = TacticalCorpus.shared

    var body: some View {
        NavigationStack {
            List {
                CorpusSectionView(title: "First Aid (TCCC)", items: viewModel.firstAidKnowledge)
                CorpusSectionView(title: "Survival (FM 3-05.70)", items: viewModel.survivalKnowledge)
                CorpusSectionView(title: "Navigation", items: viewModel.navigationKnowledge)
                CorpusSectionView(title: "Radio / Comms", items: viewModel.radioProcedures)
                CorpusSectionView(title: "SAR Protocols", items: viewModel.sarProtocols)
                CorpusSectionView(title: "Weather", items: viewModel.weatherPatterns)
                CorpusSectionView(title: "Tactical Procedures", items: viewModel.tacticalProcedures)
                CorpusSectionView(title: "ICS / Incident Command", items: viewModel.incidentCommand)
                CorpusSectionView(title: "Signaling", items: viewModel.signaling)
            }
            .navigationTitle("Field Manual Corpus")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct CorpusSectionView: View {
    let title: String
    let items: [String: String]

    var body: some View {
        Section(header: Text(title).font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)) {
            ForEach(items.keys.sorted(), id: \.self) { key in
                NavigationLink(destination: CorpusDetailView(title: key, content: items[key] ?? "")) {
                    Text(key).font(.subheadline)
                }
            }
        }
    }
}

private struct CorpusDetailView: View {
    let title: String
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack { TacticalCorpusView() }
}
