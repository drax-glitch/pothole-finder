// lib/detection_config.dart
// -----------------------------------------------------------------------------
// Central configuration for the detection pipeline.
// Change values here; nothing else needs editing.
// -----------------------------------------------------------------------------

/// Minimum detection confidence to enter NMS (0.0 to 1.0).
/// Lower => finds more faint potholes, but may include false positives.
/// Recommended starting range: 0.25 to 0.40.
const double kDefaultConf = 0.30;

/// IoU overlap threshold for non-maximum suppression (0.0 to 1.0).
/// Boxes that overlap more than this fraction with a higher-confidence box
/// are suppressed.
/// Recommended starting range: 0.40 to 0.50.
const double kNmsIouThreshold = 0.45;

/// Hard cap on the number of candidate boxes fed into NMS.
const int kMaxCandidates = 500;

/// Hard cap on kept detections after NMS.
const int kMaxDetections = 30;

// ---------------- Minimum bounding-box size filter ---------------------------
//
// IMPORTANT - UNIT NOTE:
// These values are measured in ORIGINAL IMAGE PIXELS (e.g. from the ESP32-CAM
// stream, NOT the 640x640 model input).
//
// Physical centimetres CANNOT be mapped to pixels without camera calibration
// and ground-plane distance estimation (see PhysicalSizeEstimator).
//
// Default is set to sensible minimums (e.g. 15 px width, 15 px height) to discard
// sensor noise/micro-artifacts while keeping all real small potholes.
// Set to 0 to disable that filter.

/// Minimum bounding-box width in original-image pixels.
const double kMinBoxWidth = 15.0;

/// Minimum bounding-box height in original-image pixels.
const double kMinBoxHeight = 15.0;

/// Minimum bounding-box area in original-image pixels^2.
const double kMinBoxArea = 250.0;

// ---------------- Frame throttle ---------------------------------------------

/// Minimum milliseconds between consecutive inference calls.
const int kFrameThrottleMs = 80;

// ---------------- Voice-alert cooldowns --------------------------------------

/// Minimum ms between any two TTS announcements.
const int kVoiceCooldownMs = 2500;

/// Re-announce the same message only after this many ms.
const int kVoiceRepeatMs = 5000;

// ---------------- Direction guidance -----------------------------------------

/// Fraction of frame width for each lateral region.
/// [0.0, kLeftEdge)          = LEFT
/// [kLeftEdge, kRightEdge)   = CENTER
/// [kRightEdge, 1.0]         = RIGHT
const double kLeftEdge  = 0.33;
const double kRightEdge = 0.67;

// ---------------- Camera Calibration Parameters (Default Prototype) ----------
// Used by GroundPlaneCalibration in vision_math.dart for physical estimation.

/// Camera height above ground plane in centimetres (e.g. 15 cm on 6WD robot).
const double kDefaultCameraHeightCm = 15.0;

/// Camera downward tilt angle in degrees (e.g. 25 deg down towards road).
const double kDefaultCameraPitchDeg = 25.0;

/// Horizontal Field of View (FOV) of the OV2640 camera in degrees (~66 deg).
const double kDefaultCameraFovH = 66.0;

/// Vertical Field of View (FOV) of the OV2640 camera in degrees (~50 deg).
const double kDefaultCameraFovV = 50.0;
