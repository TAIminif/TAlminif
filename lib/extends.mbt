// Explicitly preserve the derived methods exposed by the initial public API.
// Current MoonBit no longer implicitly promotes trait methods.

///|
pub extend C3dError with @debug.Debug::{to_repr}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Header with @debug.Debug::{to_repr}

///|
pub extend Header with Eq::{equal, not_equal}

///|
pub extend Group with @debug.Debug::{to_repr}

///|
pub extend Group with Eq::{equal, not_equal}

///|
pub extend Parameter with @debug.Debug::{to_repr}

///|
pub extend Parameter with Eq::{equal, not_equal}

///|
pub extend Parameters with @debug.Debug::{to_repr}

///|
pub extend Parameters with Eq::{equal, not_equal}

///|
pub extend Marker with @debug.Debug::{to_repr}

///|
pub extend Marker with Eq::{equal, not_equal}

///|
pub extend Frame with @debug.Debug::{to_repr}

///|
pub extend Frame with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Channel with @debug.Debug::{to_repr}

///|
pub extend Channel with Eq::{equal, not_equal}

///|
pub extend Layout with @debug.Debug::{to_repr}

///|
pub extend Layout with Eq::{equal, not_equal}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub extend Document with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Report with @debug.Debug::{to_repr}

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub extend Distribution with @debug.Debug::{to_repr}

///|
pub extend Distribution with Eq::{equal, not_equal}

///|
pub extend MarkerSummary with @debug.Debug::{to_repr}

///|
pub extend MarkerSummary with Eq::{equal, not_equal}

///|
pub extend AnalogSummary with @debug.Debug::{to_repr}

///|
pub extend AnalogSummary with Eq::{equal, not_equal}

///|
pub extend TrialSummary with @debug.Debug::{to_repr}

///|
pub extend TrialSummary with Eq::{equal, not_equal}
