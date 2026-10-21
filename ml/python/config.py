"""Shared constants. Anything the iOS app must reproduce lives here or in the
exported policy_params.json, never hard-coded in two places."""

# A grade completa considerada pelo pipeline. 22h existe aqui só para ser filtrada
# por `is_quiet` abaixo; a grade que o app realmente usa
# (Constants.notificationFixedHours) é ACTIVE_SLOT_HOURS, sem 22h.
SLOT_HOURS = [8, 10, 12, 14, 16, 18, 20, 22]

# Quiet hours, local time: no reminder may fire in [QUIET_START, QUIET_END).
# The window wraps midnight, so 22:00 is excluded and 08:00 is allowed.
QUIET_START_MIN = 22 * 60
QUIET_END_MIN = 8 * 60


def is_quiet(minute_of_day: float) -> bool:
    s, e = QUIET_START_MIN, QUIET_END_MIN
    return (minute_of_day >= s or minute_of_day < e) if s > e else (s <= minute_of_day < e)


ACTIVE_SLOT_HOURS = [h for h in SLOT_HOURS if not is_quiet(h * 60)]   # 8..20

RESPONSE_WINDOW_MIN = 10          # same as notificationResponseWindowMinutes in the app
DEFAULT_TZ = "America/Sao_Paulo"  # fallback when UserProfile.fusoHorario is missing/invalid

CONTAINER = "iCloud.com.hidratapoc"
RECORD_TYPES = ["UserProfile", "IntakeLog", "NotificationEvent", "SlotDecision"]

# Features of the linear model (population prior + on-device bandit).
# ORDER MATTERS: it is the order of the vector on the device.
LINEAR_FEATURES = [
    "hour_sin", "hour_cos", "hour_sin2", "hour_cos2",   # 24h + 12h harmonics: up to two peaks/day
    "weekend",
    "apparent_temp", "humidity",
    "busy", "event_density",
    "deficit_frac", "log_min_since_last", "no_intake_yet",
    "age", "female",
]
BINARY_FEATURES = {"weekend", "busy", "no_intake_yet", "female"}

# Features whose effect may vary per user in the hierarchical model.
RANDOM_SLOPES = ["hour_sin", "hour_cos", "hour_sin2", "hour_cos2"]          # bootstrap fit (send only)
# Refit on SlotDecision (send + skip) uses separate skip and send blocks
# (columns f_k = f * skip, f_s = f * send) instead of [x, send * x]: same model,
# but no shared columns, so NUTS does not hit max tree depth. Per-user terms:
# baseline when skipped, baseline when sent, and the daily shape of the response
# to reminders. Other coefficients still adapt per user on the device (var floor).
DECISION_RANDOM_TERMS = ["skip", "send", "hour_sin_s", "hour_cos_s"]

# On-device forgetting: every day, precision moves this fraction of the way back
# toward the prior precision (means are kept). Effective memory ~ 1 / (1 - decay) days.
DAILY_DECAY = 0.97

# Extra features only the offline tree model uses.
GBM_EXTRA_FEATURES = ["bmi", "goal_l", "dow", "variant", "user_prev_rate", "user_prev_n"]
GBM_CATEGORICAL = ["dow", "variant"]

# Outcome columns: never features.
LEAKY_COLUMNS = ["statusInteracao", "tempoAteAgirMin", "resultouEmConsumo"]
