# muscle-grail

<img src="Design/icon.png" width="160" alt="Muscle Grail: a flexed arm lifting a dumbbell">

Muscle Grail App

Offline-first gym tracker for iPhone and Apple Watch. Plans are created in a Mac app, everything syncs through iCloud in the background, and a watch complication shows today's steps and km.

Open `MuscleGrail.xcodeproj` and follow **First run** in [PLAN.md](PLAN.md).
Core tests: `cd Core && ./fetch-catalog.sh && swift test`. The exercise catalog is downloaded at build time, not committed: its license forbids republishing it.

## Credits

Exercise data by [RepDB](https://repdb.co) ([exercise-dataset](https://github.com/RepDB/exercise-dataset), free tier, used under its [data license](https://github.com/RepDB/exercise-dataset/blob/main/LICENSE-DATA.md)).
