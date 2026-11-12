# Turflet

A turf and court booking app: a Flutter mobile app built from the "Turf Booking App – UI/UX Flow" design, a Django REST backend, and a custom admin panel made with Django templates, Tailwind and jQuery.

```
traffy/
├── backend/   Django 5.2 + DRF + JWT · PostgreSQL · Cloudinary · admin panel (/admin-panel/)
└── mobile/    Flutter app (Android + iOS) · all 19 screens from the design
```

## 1. Backend

```bash
cd backend
python3.13 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # fill in DATABASE_URL, CLOUDINARY_URL, SECRET_KEY
createdb turflet               # or point DATABASE_URL at your Postgres
python manage.py migrate
python manage.py createsuperuser        # email + password, used for the admin panel
python manage.py seed_demo              # optional: sample venues, players, tournaments from the design
python manage.py runserver 0.0.0.0:8000
```

- Admin panel: http://localhost:8000/admin-panel/ (sign in with the superuser's email and password)
- Raw Django admin, as a fallback: http://localhost:8000/django-admin/
- API base: http://localhost:8000/api/v1/

**Cloudinary.** Set `CLOUDINARY_URL=cloudinary://KEY:SECRET@CLOUD`. Every `ImageField` then uploads to Cloudinary through `core/storage.py`: venue photos, sport images, the offer banner, group images and avatars. If you run `seed_demo` with this set, the sample photos are uploaded to Cloudinary too. Without it, files are saved in `backend/media/`.

**Postgres.** Set `DATABASE_URL=postgres://user:pass@host:5432/turflet`. If it is unset, the backend uses SQLite so you can try things quickly.

**Things to plug in before going live**
| What | Where | Dev behaviour |
|---|---|---|
| SMTP for sign-in codes (Gmail app password, SES, SendGrid, Mailgun…) | `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, `DEFAULT_FROM_EMAIL` in `.env`, then `OTP_DEV_MODE=False` | Without `EMAIL_HOST`, emails print in the server console; in dev mode the code is always `123456` and the API returns it |
| Payment gateway (Razorpay…) | `bookings/payments.py`, `PAYMENT_PROVIDER` | `mock` confirms payments instantly |

## 2. Mobile app

```bash
cd mobile
flutter pub get
flutter run                              # local backend: Android emulator → 10.0.2.2:8000, iOS sim → 127.0.0.1:8000
flutter run --dart-define=APP_ENV=stage        # stage (STAGE_API_BASE, see below)
flutter run --dart-define=APP_ENV=prod         # prod  → https://truflet.vercel.app/api/v1
flutter build apk --dart-define=APP_ENV=prod   # release build against prod
```

Environments live in `lib/core/config/app_config.dart`. The stage URL defaults to `https://truflet-stage.vercel.app/api/v1`; change it there or pass `--dart-define=STAGE_API_BASE=...`. `--dart-define=API_BASE=...` overrides the URL for any environment — for a physical phone on the same Wi-Fi use your computer's LAN IP, e.g. `--dart-define=API_BASE=http://192.168.1.20:8000/api/v1`. Local and stage builds print one line per API call (`[api] GET /venues/ → 200 84ms`); prod does not.

See `mobile/README.md` for how the app code is organised.

Demo player after `seed_demo`: email **arjun@turflet.app**, code **123456** (dev mode).

**Sign-in** is passwordless: the player enters their email, receives a 6-digit code (valid 10 minutes, 5 attempts, one resend every 30 seconds), and gets JWT tokens. Players can add an optional mobile number in Profile so venues can contact them. The email template is in `backend/templates/emails/`.

### Screens (same order as the design)
1 Splash · 2 Onboarding · 3 Choose location (GPS + cities/areas) · 4 Explore (sport chips, search, sort, offer banner, favourites) · 5 Turf details · 6 Slot booking (sport · date · court · duration · live slot grid with peak/booked/past) · 7 Review & pay (10-min hold countdown, coupon, payment methods) · 8 Booking confirmed (real QR) · 9 My bookings (upcoming/completed/cancelled, rate, book again) · 10 Ticket (QR pass, directions, call, cancel with the refund quote, reschedule) · 11 Saved venues · 12 Help & support (FAQs, chat ticket, call, email) · 13 Policies · 14 Play hub · 15 Create match/tournament (4-step wizard) · 16 Tournament host dashboard (fixtures, ball-by-ball cricket scoring or points scoring, teams & payments) · 17 Squad (groups, friends, requests, players nearby) · 18 Group (RSVP, cost split, invite) · 19 Profile.

Two screens are additions that the design implied but didn't draw, styled with the same tokens: **email code sign-in** and **notifications** (the bell on Explore).

## 3. Admin panel (`/admin-panel/`)

Built with Django templates, Tailwind (CDN) and jQuery: live search and filters, AJAX toggles and deletes, drag-and-drop photo upload to Cloudinary, image previews, and global search.

- **Dashboard**: today's bookings, monthly revenue chart, top venues, today's games, recent bookings
- **Check-in desk**: scan or type the QR / booking ID to validate a ticket and check the player in
- **Venues**: details, sport pricing (base + peak surcharge), courts, photos, blocked slots, and a day-by-day **slot board**
- **Bookings**: filter by status/payment/venue, detail page, check in, mark completed, cancel with full refund, internal notes
- **Coupons, reviews, players** (wallet top-ups, bookings history), **squad groups, matches, tournaments** (generate fixtures, edit scores), teams, fixtures
- **Content**: FAQs, refund rules (these drive the real refund calculation), policy sections, support tickets (reply), notifications
- **Broadcast** a notification to every player, and **App settings** (convenience fee, GST, hold minutes, offer banner, support contacts)

### Turf owners (venue staff role)

- An admin opens **People → Players & staff** and switches on **Turf owner** for a user, then sets that user as **Owner** on their venue(s).
- The owner signs in at `/admin-panel/` with **"Turf owner? Sign in with an email code"**, so no password is needed.
- Owners only see **their own grounds**: dashboard numbers, bookings (check in, complete, cancel with full refund, notes), the check-in desk, the slot board, courts, sports & pricing, photos, blocked slots and reviews. Players, coupons, content, settings and other venues are hidden and return 404.
- Owners can onboard a new ground with **Add a ground**. It stays hidden in the app until an admin approves it by switching the venue to **Active**. Admins see a "waiting for approval" banner on the dashboard.
- Demo after `seed_demo --reset`: turf owner **owner@turflet.app**, code **123456** (dev mode), owns the first venue.

## 4. Key business rules (backend)
- A slot is held for `hold_minutes` (default 10) while the player pays. Held, confirmed and venue-blocked hours show as booked.
- Price = base price per hour, plus the peak surcharge for hours inside the venue's peak window. Then the convenience fee, plus GST on that fee, minus any coupon.
- Refund % is set by the `RefundRule` table (100% at 24h or more, 50% at 6h or more, otherwise 0%). The convenience fee is not refunded, except when the venue cancels.
- One free reschedule, allowed up to 2 hours before the slot.
- Tournaments: knockout, league or groups + knockout with 4/8/16 teams. Fixtures are generated and scheduled across courts and days; winners move on to the next round automatically.
