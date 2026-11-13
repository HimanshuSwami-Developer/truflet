# Turflet mobile app

Flutter app for players: find turfs, book slots, pay and manage bookings.
How to run it against local / stage / prod is in the root `README.md`.

## Code layout

```
lib/
  main.dart                   single entry point; APP_ENV picks local / stage / prod → bootstrap(AppConfig)
  bootstrap.dart              system UI, builds dependencies, boots the session, runApp
  app/
    app.dart                  MaterialApp.router
    app_dependencies.dart     builds config → storage → ApiClient → repositories → AppCubit (once)
    app_scope.dart            provides every repository + AppCubit to the widget tree
    router/
      app_routes.dart         every path, plus route args (SlotBookingArgs) and the FadeIn marker
      app_router.dart         GoRouter: path → screen
      app_navigation.dart     typed helpers: context.pushVenue(id), context.goTab(1), …
    session/
      app_cubit.dart          app-wide state: player, config, sports, chosen area, active tab, favourites
  core/                       no feature code in here
    config/app_config.dart    local / stage / prod base URLs
    network/                  ApiClient (Dio) + interceptors: auth → refresh-on-401 → error mapping → logging
    storage/                  tokens and device preferences (SharedPreferences)
    bloc/data_cubit.dart      loading / data / error for single-request screens
    theme/                    colours (C), text styles (t, d), shadows, ThemeData
    utils/                    rupee/time formatting, maps / calendar / share
    widgets/                  shared UI kit (buttons, pills, cards, Loader/DataBuilder, sheet, toast…)
  data/repositories/          one class per API area; the only place that knows endpoint paths
  features/<feature>/
    cubit/                    state + cubit: owns data and calls repositories
    view/                     screens: layout, toasts and navigation only
    widgets/                  pieces used by that feature only
```

Features: splash, onboarding, location, auth (login, profile form, sign-in guards), shell (bottom tabs),
explore, venue, booking (my bookings, slot matrix, payment, confirmation, ticket), lobby (open lobbies, squad
builder, match room, request thread, my matches, split checkout), saved, notifications, support (help, policies),
profile. Tabs: Explore · Matches · Bookings · Profile (`AppTab`).

## Conventions

- **Data flow:** view → cubit → repository → `ApiClient`. Views never call the API directly.
- **Screens build their own cubit.** Each `XScreen` is a small `BlocProvider` that wraps a private `_XView`,
  so a screen can be opened on its own (that's how the integration tests use it).
- **Cubits return outcomes, views react.** Action methods return an error message (or a result) and the view
  shows the toast or navigates. Cubits don't hold a `BuildContext`.
- **View-only state stays in the widget:** text controllers, animations, which FAQ is open, "Copied" labels.
- **States are plain classes** (no `==` override), so every `emit` rebuilds — same as `setState`.
- **API data stays as JSON maps** (`Json`), exactly as the backend sends it.
- **Navigation:** go through `app_navigation.dart`. `replaceWith…` resolves the replaced screen's `push` future,
  like `Navigator.pushReplacement`; `goTab` switches tab and pops back to the shell.

## Tests

```bash
flutter test                                  # routing smoke tests (offline)
flutter test integration_test/screens_test.dart -d <simulator>   # every screen against the local backend
```
