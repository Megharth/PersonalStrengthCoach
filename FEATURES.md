# Personal Strength Coach — Features Guide

Personal Strength Coach is an iOS strength-training tracker that helps you log workouts, monitor recovery, and optimize your training with AI-powered insights. Everything runs on-device with Apple Health integration — no account required.

---

## 🏠 Today Tab

Your daily training dashboard showing current readiness and personalized recommendations.

**What you'll see:**
- **Readiness Score** — A 0-100 score combining sleep, HRV, resting heart rate, and recent training load. Green (75+) means you're primed for hard work; yellow (55-74) suggests steady training; red (<55) signals recovery priority.
- **Recovery Metrics** — Today's sleep hours, HRV (heart rate variability), and resting heart rate pulled from Apple Health.
- **Recommended Workout** — Exercise suggestions based on muscle recovery status and training history (e.g., "Upper Body Push — Chest and shoulders recovered, last trained 4 days ago").
- **Coach Summary** — Contextual guidance on whether to push hard, maintain steady effort, or prioritize rest based on your readiness data.

**How to use it:**
Check this tab each morning to decide what to train. If readiness is low but you feel good, the factors list shows exactly what's affecting your score (e.g., "Sleep below baseline" or "High training load this week").

---

## 📊 Dashboard Tab

Performance analytics and training trends over time.

**What you'll see:**
- **Weekly Volume** — Total weight moved across all exercises in the past 7 days, displayed in your selected kg/lb unit. Calculations remain canonical kilograms.
- **Workout Count** — Number of sessions completed this week.
- **Strength Trend** — Estimated 1RM progression for your most-trained exercise, charted across recent weeks. Requires the same exercise logged in at least two different weeks.
- **Sleep & HRV Trends** — 7-day rolling charts showing recovery patterns.

**How to use it:**
Use strength trends to confirm progressive overload is working. If your estimated 1RM plateaus or drops, check recovery trends and weekly volume to diagnose whether you're under-recovering or under-stimulating.

---

## 🕐 History Tab

All logged workouts with session details and personal records.

**Workout List:**
Tap any workout to see:
- **Session stats** — Total volume (kg), duration (minutes), estimated calories burned.
- **Exercises performed** — Grouped by exercise name with set count and volume per movement.
- **Personal Records** — Highlighted PRs achieved in that session (e.g., "Bench Press — heaviest set" or "Squat — most reps at weight").
- **Coach Notes** — Contextual feedback on the session (high volume, PR achieved, general encouragement).

**Exercise Deep Dive:**
Tap an exercise within a workout to view:
- **Estimated 1RM** — Current Brzycki formula estimate based on your best recent set.
- **Best Set** — Heaviest weight logged for this exercise across all history.
- **1RM Progression Chart** — Estimated 1RM over time to visualize strength gains or plateaus.
- **Progression Guidance** — Coach feedback on whether you're gaining, plateauing, or regressing, with actionable suggestions.

**Fixing or Removing a Workout:**
- **Edit** — Tap a workout, then the pencil in the top-right. You can change the
  title, date, duration, and every set's weight and reps, and add or remove sets
  and whole exercises. Saving recomputes volume, PRs, 1RM trends, and readiness
  immediately — so correcting a mistyped `500` back to `50` also clears the bogus
  PR it created.
- **Delete** — Swipe a row in the workout list, or use **Delete Workout** at the
  bottom of a workout's detail screen. Both ask for confirmation first.
- **There is no undo.** Deleting a workout permanently removes the session and
  all of its sets.
- **Deleting a workout rewrites history honestly.** If the deleted session set a
  PR, the next-best lift becomes the PR again, and past coach notes referring to
  that record change accordingly.
- **One caveat when editing:** if a single session contained the same exercise in
  two separate blocks (e.g. heavy bench early, back-off bench later), the editor
  shows them as one combined block. Every set, weight, and rep is preserved — only
  the split between the blocks is lost.
- Emptying a workout is never treated as a delete: removing every exercise and
  tapping Save prompts you to add an exercise instead.

**Logging New Workouts:**
Tap the **+** menu (top-right) to:
- **Log Workout** — Manually enter exercises, sets, weight, and reps for a new session.
- **Routines** — View and manage saved workout templates (see Routines below).
- **Import from Strong** — Migrate your history from the Strong app (CSV, JSON, or shared-workout text).

If a workout was started but not finished, History shows a **Resume** card. Starting another workout asks whether to resume the draft, discard it and start fresh, or cancel; an unfinished workout is never silently replaced.

---

## 💓 Recovery Tab

Detailed recovery metrics and muscle-group readiness.

**What you'll see:**
- **Overall Readiness Card** — Same score as the Today tab, with detailed factors.
- **Muscle Recovery Grid** — 8 tiles (Chest, Back, Shoulders, Arms, Legs, Glutes, Core, Full Body) showing 0-100% recovery per muscle group. Green (70%+) means recovered; yellow (45-69%) means recovering; red (<45%) means fatigued.
- **Weekly Averages** — 7-day average sleep and HRV to track baseline trends.

**How recovery is calculated:**
Each muscle group's recovery percentage is based on time since last trained and training volume. Heavy sessions require more recovery time. The algorithm accounts for overlapping muscle groups (e.g., shoulders fatigue from both overhead press and bench press).

**How to use it:**
Before starting a workout, check which muscle groups are recovered. If legs show 35% recovery but upper body is 85%, prioritize upper body work or take a full rest day.

---

## ✨ Coach Tab

AI-powered training advisor with chat interface.

**What it does:**
Ask questions about your training, recovery, or next session. The coach has access to:
- Your current readiness score and recovery metrics
- Weekly training volume
- Recommended next workout
- Recent training history

**Example questions:**
- "Should I train heavy today?"
- "Why is my readiness score low?"
- "What should I focus on this week?"
- "How's my chest recovery looking?"

**How it works:**
Questions are sent to an AI proxy (configured per environment). If the proxy is unavailable, the coach falls back to local rule-based recommendations from the `RecommendationEngine`.

**Privacy note:**
The app never sends personally identifiable data. Only aggregated metrics (readiness score, volume, muscle recovery percentages) are shared with the AI service.

---

## 🏋️ Workout Logger

Log training sessions with exercise-by-exercise tracking.

**To log a workout:**
1. From History tab, tap **+** → **Log workout**.
2. Set workout name and date/time.
3. Tap **Add exercise** to choose from the library or create a custom exercise.
4. For each exercise, log sets with weight in your selected kg/lb unit and reps. These primary fields stay visible for fast entry; tap **Set details** when you need set type or optional RPE. Saved values remain canonical kilograms.
   Set types distinguish warmups, working sets, drop sets, and failure sets. When
   the exercise has prior history, the corresponding sets are prefilled from the
   most recent workout and remain fully editable; prior RPE is never copied. Adding
   another set continues any remaining historical defaults, then carries forward
   the current set's weight, reps, and type without copying completion or RPE.
5. Tap **Save** when complete.

**Features:**
- **Custom exercises** — Add any movement not in the built-in library. Assign it a primary muscle group for accurate recovery tracking.
- **Set management** — Add/remove sets on the fly. Each set shows its set number, weight, reps, and set type. Optional RPE is stored in half-point increments from 0 to 10; RIR is derived from RPE. Warmup sets remain visible but are excluded from volume and strength analytics, while working, drop, and failure sets count normally.
- **Duration tracking** — Workout duration is automatically calculated from session start to save time.
- **Resumable sessions** — The in-progress workout is persisted on-device, including exercise/set values, completion state, elapsed time, and an absolute rest-timer deadline. The Session section shows completed-set volume and elapsed time while logging. Backgrounding and view recreation restore the draft; History provides an explicit Resume action after relaunch.
- **Rest timer** — Completing a set starts a 90-second in-sheet countdown; it survives backgrounding and view recreation and never displays negative time. Use **Skip rest** when ready early; completion announces the transition and provides haptic feedback. The timer is a local in-sheet indicator; ActivityKit/Live Activities are not part of this feature.
- **Draft safety** — Unfinished drafts are excluded from completed-workout exports. Delete All Local Data removes drafts and their saved sets. Saving a completed workout removes its draft only after the completed save succeeds; invalid or failed saves leave the draft recoverable. Discard is explicit and confirmed.
- **Start from Routine** — Load a saved routine to pre-fill exercises and target sets/reps (see below). Routine targets take precedence over previous-workout prefill.

**Tips:**
- For bodyweight exercises (push-ups, pull-ups), log 0 in your selected unit; it remains canonical zero kilograms in storage.
- The logger validates that each workout has at least one exercise with one set before saving, and repetitions must be between 1 and 999.
- Invalid repetitions are highlighted before saving; deleting a set offers an accessible Undo recovery.
- Tap the trash icon next to an exercise to remove it from the session.

---

## 📋 Routines

Save and reuse workout templates for faster logging.

**What routines are:**
A routine is a template containing:
- Workout name (e.g., "Upper Body Push A")
- Ordered list of exercises
- Target sets, reps, and optionally target weight per exercise

**Creating a routine:**
1. From History tab, tap **+** → **Routines** → **+** (top-right).
2. Name your routine.
3. Add exercises from the library.
4. Set target sets/reps for each exercise. Optionally set a target weight.
5. Reorder exercises by tapping **Edit** (top-right) and dragging.
6. Tap **Save**.

**Using a routine:**
When logging a workout, tap **Start from a routine** and select a saved template. All exercises, sets, and targets will pre-fill. You can still edit sets, weights, or add/remove exercises before saving.

**Editing/deleting routines:**
From Routines list, tap any routine to edit. Tap **Delete Routine** at the bottom to remove it (logged workouts are unaffected).

**Why use routines:**
If you follow a program (e.g., PPL, 5/3/1, Upper/Lower split), save each session as a routine. Logging becomes one tap + entering actual weights/reps instead of rebuilding the workout every time.

---

## 📥 Import from Strong

Migrate your training history from the Strong app.

**Supported formats:**
- **CSV export** — Strong's "Export to CSV" feature. Supports workouts, exercises, sets, weight (kg/lb auto-converted), reps, duration, and warmup markers from Set Order.
- **JSON export** — Strong's JSON export format, including optional set type and RPE metadata when present.
- **Shared workout text** — Copy/paste text from Strong's "Share Workout" feature (includes exercise names and set-by-set breakdowns).

**To import:**
1. From History tab, tap **+** → **Import from Strong**.
2. Tap **Choose file** to select a CSV/JSON export from Files app, or **Paste export** to paste shared-workout text.
3. Review the parsed workouts. The importer shows set count and total volume per workout.
4. Tap **Import** to save.

**Import behavior:**
- **Duplicate detection** — If a workout with the same title, date (within 1 minute), and sets already exists, it's skipped.
- **Error handling** — Malformed rows are skipped. The import summary shows how many workouts were imported, skipped, or failed.
- **Exercise mapping** — Exercise names are normalized (e.g., "Barbell Bench Press" and "bench press" map to the same exercise). Muscle groups are inferred from the exercise name using the built-in catalog.

**Tips:**
- Strong exports use either kg or lb depending on your Strong settings. The importer auto-detects and converts lb to kg.
- Large exports (10+ MB) are rejected to prevent performance issues. Filter your Strong export by date range if needed.
- The importer validates that weight/reps are positive and finite. Bodyweight sets (0 kg) are allowed.

---

## ⚙️ Settings Tab (Data Management)

Manage your data and privacy.

**What's here:**
- **Weight unit preference** — Choose kilograms or pounds for weight entry and display throughout the app. Workout calculations, imports, duplicate detection, and JSON exports remain in canonical kilograms.
- **Export All Data** — Export your complete completed-workout history (workouts, sets, recovery data, custom exercises, routines) as a JSON file. Unfinished workout drafts are intentionally excluded. Use this for backups or to migrate to another device.
- **Delete All Local Data** — Permanently erase all workouts, unfinished workout drafts and their saved sets, recovery data, custom exercises, and routines. This cannot be undone. Apple Health data is unaffected.
- **HealthKit Sync** — The app automatically syncs sleep, HRV, resting heart rate, and body mass from Apple Health on every app launch. If sync fails, you'll see a retry prompt.

**Privacy & permissions:**
- **Apple Health permissions** — The app requests read-only access to Sleep, Heart Rate Variability, Resting Heart Rate, and Body Mass. Grant these in Settings → Health → Data Access & Devices → Personal Strength Coach.
- **No account required** — All data lives on-device in SwiftData. Nothing is uploaded to a server (except optional AI coach queries, which only send aggregated metrics).
- **Dark mode** — The app forces dark mode for better readability during gym sessions.

---

## 🧠 How the App Calculates Things

### Readiness Score (0-100)
Combines:
- **Sleep** — Compared to your 7-day baseline. Below baseline lowers score.
- **HRV** — Heart rate variability. Higher is better. Compared to baseline.
- **Resting Heart Rate** — Lower is better. Elevated RHR suggests incomplete recovery.
- **Training Load** — Weekly volume and recent high-intensity sessions. Too much volume lowers score.

Confidence is marked "low" if you have fewer than 3 days of recovery data. Sync Apple Health daily to build a reliable baseline.

### Estimated 1RM
Uses the Epley formula: `weight × (1 + reps / 30)`. Warmup sets are excluded; the estimate is calculated per exercise from the best eligible recent set. Progression charts track 1RM over time to visualize strength gains.

### Personal Records (PRs)
Detected automatically when you:
- Lift more weight for the same reps (or more reps) than any prior set for that exercise.
- Achieve a new estimated 1RM for an exercise.

PRs are highlighted in workout detail views with a trophy icon.

### Muscle Recovery Percentage
Each muscle group's recovery is based on:
- **Time since last trained** — Recovery increases linearly over 48-72 hours (varies by muscle group size).
- **Volume** — Heavier/higher-volume sessions require longer recovery.
- **Overlapping stress** — Shoulders count as partially trained when you bench press or overhead press.

Recovery percentages update in real-time as you log new workouts.

### Weekly Volume
Sum of canonical-kilogram `weight × reps` for all sets logged in the past 7 days. It is displayed in your selected kg/lb unit (divided by 1,000 for readability, e.g., "12k kg" means 12,000 kg total).

### Workout Duration
Automatically calculated from the time you open the workout logger to the time you tap Save. Editable via the date picker if you log a workout after completing it.

### Calories
Estimated using the formula: `(volume in kg × 0.01) + (duration in minutes × 5)`. This is a rough approximation for strength training; actual calorie burn varies by intensity, rest periods, and individual metabolism.

---

## 🎯 Tips for Getting the Most Out of the App

1. **Sync Apple Health daily** — Wear your Apple Watch to bed and the app will automatically pull sleep/HRV data each morning. This builds a reliable readiness baseline.

2. **Log workouts immediately** — Duration tracking starts when you open the logger. If you log after the fact, manually adjust the date/time.

3. **Use routines for repeated sessions** — If you follow a program, save each workout as a routine. You'll log 3x faster.

4. **Check muscle recovery before training** — The Recovery tab shows exactly which muscle groups need rest. Avoid training fatigued muscles to reduce injury risk.

5. **Track progression via 1RM trends** — If your estimated 1RM isn't climbing over 4-6 weeks, you're not progressively overloading. Increase weight or volume slightly.

6. **Name exercises consistently** — The app normalizes exercise names (e.g., "Bench Press" and "bench press" are the same), but wildly different names ("BB Bench" vs "Barbell Flat Bench") won't merge. Stick to one naming convention.

7. **Import your Strong history early** — If migrating from Strong, import your history before logging new workouts. This gives the app a complete training history for better recommendations and PR detection.

8. **Use the Coach tab for context** — If you're unsure whether to train or rest, ask the coach. It considers your readiness, muscle recovery, and recent training load.

---

## 🔒 Privacy & Data

- **On-device storage** — All data lives locally in SwiftData. Nothing is uploaded unless you explicitly use the AI coach or export data.
- **Apple Health read-only** — The app never writes to Apple Health. It only reads sleep, HRV, resting HR, and body mass.
- **AI coach data** — When you ask a question, the app sends only your readiness score, weekly volume, and recommended workout to the AI proxy. No workout history, exercise names, or personal info is sent.
- **Exports are unencrypted** — JSON exports contain your full training history in plain text. Store them securely.

---

## 📱 System Requirements

- **iOS 18+** — The app uses SwiftData, which requires iOS 17+, and Charts features from iOS 18.
- **Apple Watch (recommended)** — For automatic sleep and HRV tracking via Apple Health.
- **HealthKit permissions** — Grant read access to Sleep, HRV, Resting Heart Rate, and Body Mass in Settings → Health → Data Access & Devices.

---

## 🐛 Troubleshooting

**Readiness score shows "low confidence":**
- You need at least 3 days of Apple Health data (sleep, HRV, resting HR). Wear your Apple Watch to bed and wait a few days.

**HealthKit sync failed:**
- Check that you've granted read permissions in Settings → Health → Data Access & Devices → Personal Strength Coach.
- Make sure you have recent sleep/HRV data in Apple Health (check the Health app directly).
- Tap "Retry" in the alert to try again.

**Strength trend shows "unavailable":**
- Log the same exercise (exact name match) in at least two different weeks. The trend requires multiple data points over time.

**Import from Strong failed:**
- Ensure the file is under 10 MB. Large exports should be filtered by date range in Strong before exporting.
- CSV files must have headers: Date, Exercise, Weight, Reps. Optional: Workout, Duration.
- JSON files must follow Strong's export format (workouts array with exercises and sets).

**Workout logger shows "Add an exercise first":**
- You tried to save a workout with no exercises or no sets. Add at least one exercise with one set before saving.

**Coach AI is unavailable:**
- The AI proxy URL is either not configured (check Info.plist `AI_PROXY_URL`) or the service is down. The app will fall back to local rule-based recommendations.

---

## 💪 Training Methodology (Behind the Recommendations)

The app's recommendation engine follows evidence-based strength training principles:

- **Frequency** — Recommends training each muscle group every 48-72 hours based on recovery percentage.
- **Progressive overload** — Tracks estimated 1RM to ensure you're adding weight/reps over time.
- **Volume landmarks** — Weekly volume is compared to your baseline to detect under-training or over-training.
- **Readiness-first** — Low readiness scores trigger rest-day recommendations, even if muscles are recovered. Recovery is more important than hitting every planned session.
- **Muscle group balance** — Recommends exercises for under-trained muscle groups to prevent imbalances (e.g., if you've benched 3x this week but haven't trained back, it'll suggest rows/pull-ups).

The app doesn't prescribe a specific program (PPL, 5/3/1, etc.) — it adapts to whatever you're doing and guides you toward sustainable, progressive training.

---

## 🚀 What's Next?

This app is under active development. Planned features include:
- **Workout templates from history** — One-tap routine creation from completed workouts.
- **Exercise video library** — Form cues and demo videos for common lifts.
- **Advanced periodization** — Training block planning with volume/intensity waves.
- **Nutrition tracking** — Optional calorie/protein logging with meal suggestions.
- **Apple Watch app** — Log sets directly from your wrist.

---

**Questions or feedback?** Check the Coach tab or open an issue in the project repository.

**Happy training!** 💪
