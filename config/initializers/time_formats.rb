# frozen_string_literal: true

# Override Rails' default :short time format with an ISO-style one. The
# stats view leans on this for first/last click summaries; the format
# stays stable across timezones because callers force .utc before
# rendering.
Time::DATE_FORMATS[:short] = "%Y-%m-%d %H:%M %Z"
